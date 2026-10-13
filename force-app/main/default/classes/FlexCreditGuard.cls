/**
 * Fails a caller transaction when a Digital Wallet card is already at its
 * entitlement, or when the caller's estimated units would reach it.
 *
 * Reads the standard computeConsumption action. Does not query Data Cloud DMOs
 * and does not depend on any other package.
 *
 * Digital Wallet does not throttle the underlying product. This class only
 * aborts Apex that calls it. See the project README for what it does not do.
 */
public with sharing class FlexCreditGuard {

    public class CreditLimitExceededException extends Exception {}
    public class ConsumptionUnavailableException extends Exception {}

    // Entitlements at or above this quantity are treated as unlimited unless
    // the caller sets capUnlimited.
    @TestVisible
    static final Decimal UNLIMITED_THRESHOLD = 1000000000000L;

    static final String DEFAULT_BUSINESS_ENV = 'Production';
    static final String DEFAULT_USAGE_MODEL = 'PrePurchased';

    // When set, fetchCards() returns this list and does not call the action.
    // An empty list is a real result. Null means "not stubbed".
    @TestVisible
    static List<sfdw.ConsumptionCard> cardsOverride;

    // When set, fetchCards() throws ConsumptionUnavailableException and does
    // not call the action.
    @TestVisible
    static String actionErrorOverride;

    /**
     * Stops the transaction when the Production / PrePurchased card is at or
     * over its entitlement, including estimatedUnits (null means 0).
     * Unlimited entitlements are not capped.
     */
    public static void assertWithinEntitlement(String cardDeveloperName, Decimal estimatedUnits) {
        assertWithinEntitlement(cardDeveloperName, estimatedUnits, null, null, false);
    }

    /**
     * Same check for an explicit environment and buying model.
     * Blank environment defaults to Production. Blank buying model defaults to PrePurchased.
     */
    public static void assertWithinEntitlement(
        String cardDeveloperName,
        Decimal estimatedUnits,
        String businessEnvType,
        String usageModel
    ) {
        assertWithinEntitlement(cardDeveloperName, estimatedUnits, businessEnvType, usageModel, false);
    }

    /**
     * @param capUnlimited when true, an entitlement at or above 1e12 is capped
     *                     like any other pool. When false, that pool is skipped.
     */
    public static void assertWithinEntitlement(
        String cardDeveloperName,
        Decimal estimatedUnits,
        String businessEnvType,
        String usageModel,
        Boolean capUnlimited
    ) {
        decide(
            fetchCards(),
            cardDeveloperName,
            businessEnvType,
            usageModel,
            estimatedUnits,
            capUnlimited
        );
    }

    /**
     * Applies the cap to an already loaded card list. Tests call this with
     * constructed sfdw.ConsumptionCard values and never invoke the action.
     */
    @TestVisible
    static void decide(
        List<sfdw.ConsumptionCard> cards,
        String cardDeveloperName,
        String businessEnvType,
        String usageModel,
        Decimal estimatedUnits,
        Boolean capUnlimited
    ) {
        String env = String.isBlank(businessEnvType) ? DEFAULT_BUSINESS_ENV : businessEnvType;
        String model = String.isBlank(usageModel) ? DEFAULT_USAGE_MODEL : usageModel;
        Decimal estimate = (estimatedUnits == null) ? 0 : estimatedUnits;

        if (String.isBlank(cardDeveloperName)) {
            throw new ConsumptionUnavailableException(
                unavailable('A card developer name is required', null, env, model, estimate, null, null)
            );
        }
        if (cards == null) {
            throw new ConsumptionUnavailableException(
                unavailable('Consumption cards were not returned', cardDeveloperName, env, model, estimate, null, null)
            );
        }

        sfdw.ConsumptionCard match = findCard(cards, cardDeveloperName, env, model);
        if (match == null) {
            throw new ConsumptionUnavailableException(
                unavailable('No consumption card matched', cardDeveloperName, env, model, estimate, null, null)
            );
        }
        if (match.totalEntitlement == null) {
            throw new ConsumptionUnavailableException(
                unavailable(
                    'Total entitlement was null',
                    cardDeveloperName,
                    env,
                    model,
                    estimate,
                    match.unitsConsumed,
                    null
                )
            );
        }

        Decimal entitlement = toDecimal(match.totalEntitlement);
        Decimal consumed = (match.unitsConsumed == null) ? 0 : toDecimal(match.unitsConsumed);
        if (capUnlimited != true && entitlement >= UNLIMITED_THRESHOLD) {
            return;
        }
        if (consumed + estimate >= entitlement) {
            throw new CreditLimitExceededException(
                'Flex Credit entitlement exceeded for ' + cardDeveloperName
                + ' (' + env + ' / ' + model + '): consumed ' + consumed.toPlainString()
                + ', estimated ' + estimate.toPlainString()
                + ', entitlement ' + entitlement.toPlainString()
                + '. This Apex transaction was aborted.'
            );
        }
    }

    static sfdw.ConsumptionCard findCard(
        List<sfdw.ConsumptionCard> cards,
        String cardDeveloperName,
        String businessEnvType,
        String usageModel
    ) {
        for (sfdw.ConsumptionCard card : cards) {
            if (card == null) {
                continue;
            }
            if (card.cardDefinitionDeveloperName == cardDeveloperName
                && card.businessEnvType == businessEnvType
                && card.usageModel == usageModel) {
                return card;
            }
        }
        return null;
    }

    static List<sfdw.ConsumptionCard> fetchCards() {
        if (actionErrorOverride != null) {
            throw new ConsumptionUnavailableException(
                'Digital Wallet consumption could not be read (' + actionErrorOverride
                + '). This Apex transaction was aborted.'
            );
        }
        if (cardsOverride != null) {
            return cardsOverride;
        }

        Invocable.Action computeAction = Invocable.Action.createStandardAction('computeConsumption');
        computeAction.addInvocation();
        List<Invocable.Action.Result> results = computeAction.invoke();
        if (results == null || results.isEmpty() || !results[0].isSuccess()) {
            throw new ConsumptionUnavailableException(
                'Digital Wallet consumption could not be read (' + errorDetail(results)
                + '). This Apex transaction was aborted.'
            );
        }

        Map<String, Object> output = results[0].getOutputParameters();
        if (output == null || !output.containsKey('cards') || output.get('cards') == null) {
            throw new ConsumptionUnavailableException(
                'Digital Wallet consumption could not be read (cards were not returned). This Apex transaction was aborted.'
            );
        }
        try {
            return (List<sfdw.ConsumptionCard>) output.get('cards');
        } catch (Exception ex) {
            throw new ConsumptionUnavailableException(
                'Digital Wallet consumption could not be read (' + ex.getMessage()
                + '). This Apex transaction was aborted.'
            );
        }
    }

    static String errorDetail(List<Invocable.Action.Result> results) {
        if (results == null || results.isEmpty()) {
            return 'no result';
        }
        List<String> messages = new List<String>();
        for (Invocable.Action.Error err : results[0].getErrors()) {
            if (err != null && String.isNotBlank(err.getMessage())) {
                messages.add(err.getMessage());
            }
        }
        return messages.isEmpty() ? 'action failed' : String.join(messages, '; ');
    }

    static String unavailable(
        String reason,
        String cardDeveloperName,
        String businessEnvType,
        String usageModel,
        Decimal estimated,
        Double unitsConsumed,
        Double totalEntitlement
    ) {
        String name = String.isBlank(cardDeveloperName) ? '(none)' : cardDeveloperName;
        String consumed = (unitsConsumed == null) ? 'unknown' : toDecimal(unitsConsumed).toPlainString();
        String entitlement = (totalEntitlement == null) ? 'unknown' : toDecimal(totalEntitlement).toPlainString();
        return reason + ' for ' + name
            + ' (' + businessEnvType + ' / ' + usageModel + '): consumed ' + consumed
            + ', estimated ' + estimated.toPlainString()
            + ', entitlement ' + entitlement
            + '. This Apex transaction was aborted.';
    }

    // String.valueOf(Double) is the requested coercion. Apex prints some large
    // Doubles in scientific notation, which Decimal.valueOf(String) rejects,
    // so those values use Decimal.valueOf(Double) instead.
    static Decimal toDecimal(Double value) {
        String raw = String.valueOf(value);
        if (raw != null && raw.containsIgnoreCase('e')) {
            return Decimal.valueOf(value);
        }
        return Decimal.valueOf(raw);
    }
}
