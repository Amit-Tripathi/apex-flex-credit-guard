/**
 * Stops an agent action when a Flex Credits card is already at its entitlement.
 *
 * Call assertWithinEntitlement at the start of the action. A throw stops the action.
 * A normal return means the action continues. The caller does not pass an estimate.
 * A throw rolls back that transaction's DML. It does not roll back Digital Wallet usage
 * that another publisher already emitted.
 *
 * The check reads computeConsumption and compares unitsConsumed with
 * totalEntitlement on the sfdw.ConsumptionCard whose cardDefinitionDeveloperName
 * is FlexCredits. Those two properties are already on the card. The caller
 * does not pass the card name.
 */
public with sharing class FlexCreditOverageGuard {

    public class CreditLimitExceededException extends Exception {}
    public class ConsumptionUnavailableException extends Exception {}

    // Standard fields on sfdw.ConsumptionCard. FlexCredits is the card definition
    // developer name, not the display label "Flex Credits".
    static final String FLEX_CREDITS_CARD = 'FlexCredits';
    static final String DEFAULT_BUSINESS_ENV = 'Production';
    static final String DEFAULT_USAGE_MODEL = 'PrePurchased';
    static final String CONSUMPTION_ACTION = 'computeConsumption';
    static final String CARDS_OUTPUT = 'cards';
    static final String OVERAGE_REASON = 'Flex credit overage';

    // When set, fetchCards() returns this list and does not call the action.
    // An empty list is a real result. Null means "not stubbed".
    @TestVisible
    static List<sfdw.ConsumptionCard> cardsOverride;

    // When set, fetchCards() throws ConsumptionUnavailableException and does
    // not call the action.
    @TestVisible
    static String actionErrorOverride;

    // --- Public API ---

    /**
     * Stops the action when the Production / PrePurchased Flex Credits card is
     * already at or over its entitlement.
     *
     * @throws CreditLimitExceededException when units already consumed reach the entitlement.
     * @throws ConsumptionUnavailableException when the card cannot be read.
     */
    public static void assertWithinEntitlement() {
        decide(fetchCards());
    }

    /**
     * Clears the fetchCards test doubles. Production calls leave both null.
     */
    @TestVisible
    static void resetOverrides() {
        cardsOverride = null;
        actionErrorOverride = null;
    }

    // --- Decision ---

    /**
     * Applies the entitlement check to an already loaded card list. Tests call
     * this with constructed sfdw.ConsumptionCard values and never invoke the action.
     */
    @TestVisible
    static void decide(List<sfdw.ConsumptionCard> cards) {
        sfdw.ConsumptionCard match = requireCard(cards);
        Decimal entitlement = toDecimal(match.totalEntitlement);
        Decimal consumed = (match.unitsConsumed == null) ? 0 : toDecimal(match.unitsConsumed);
        if (consumed >= entitlement) {
            throw new CreditLimitExceededException(
                outcomeMessage(OVERAGE_REASON, consumed, entitlement)
            );
        }
    }

    static sfdw.ConsumptionCard requireCard(List<sfdw.ConsumptionCard> cards) {
        if (cards == null) {
            throw new ConsumptionUnavailableException(
                outcomeMessage('Consumption cards were not returned', null, null)
            );
        }

        sfdw.ConsumptionCard match = findFlexCreditsCard(cards);
        if (match == null) {
            throw new ConsumptionUnavailableException(
                outcomeMessage('No consumption card matched', null, null)
            );
        }
        if (match.totalEntitlement == null) {
            Decimal consumed = (match.unitsConsumed == null) ? null : toDecimal(match.unitsConsumed);
            throw new ConsumptionUnavailableException(
                outcomeMessage('Total entitlement was null', consumed, null)
            );
        }
        return match;
    }

    // Match the standard ConsumptionCard fields exactly. Apex == is case-insensitive,
    // so this uses String.equals on cardDefinitionDeveloperName.
    static sfdw.ConsumptionCard findFlexCreditsCard(List<sfdw.ConsumptionCard> cards) {
        for (sfdw.ConsumptionCard card : cards) {
            if (card == null) {
                continue;
            }
            if (FLEX_CREDITS_CARD.equals(card.cardDefinitionDeveloperName)
                && DEFAULT_BUSINESS_ENV.equals(card.businessEnvType)
                && DEFAULT_USAGE_MODEL.equals(card.usageModel)) {
                return card;
            }
        }
        return null;
    }

    // --- Cards from the org ---

    static List<sfdw.ConsumptionCard> fetchCards() {
        if (actionErrorOverride != null) {
            throw new ConsumptionUnavailableException(readFailure(actionErrorOverride));
        }
        if (cardsOverride != null) {
            return cardsOverride;
        }

        Invocable.Action computeAction = Invocable.Action.createStandardAction(CONSUMPTION_ACTION);
        computeAction.addInvocation();
        return cardsFromResult(computeAction.invoke());
    }

    @TestVisible
    static List<sfdw.ConsumptionCard> cardsFromResult(List<Invocable.Action.Result> results) {
        if (results == null || results.isEmpty() || !results[0].isSuccess()) {
            throw new ConsumptionUnavailableException(readFailure(errorDetail(results)));
        }
        return cardsFromOutput(results[0].getOutputParameters());
    }

    @TestVisible
    static List<sfdw.ConsumptionCard> cardsFromOutput(Map<String, Object> output) {
        if (output == null || !output.containsKey(CARDS_OUTPUT) || output.get(CARDS_OUTPUT) == null) {
            throw new ConsumptionUnavailableException(readFailure('cards were not returned'));
        }
        try {
            return (List<sfdw.ConsumptionCard>) output.get(CARDS_OUTPUT);
        } catch (System.TypeException ex) {
            throw new ConsumptionUnavailableException(readFailure(ex.getMessage()));
        }
    }

    @TestVisible
    static String errorDetail(List<Invocable.Action.Result> results) {
        if (results == null || results.isEmpty()) {
            return 'no result';
        }
        List<Invocable.Action.Error> errors = results[0].getErrors();
        if (errors == null || errors.isEmpty()) {
            return 'action failed';
        }
        List<String> messages = new List<String>();
        for (Invocable.Action.Error err : errors) {
            if (err != null && String.isNotBlank(err.getMessage())) {
                messages.add(err.getMessage());
            }
        }
        return messages.isEmpty() ? 'action failed' : String.join(messages, '; ');
    }

    static String readFailure(String detail) {
        return 'Digital Wallet consumption could not be read (' + detail
            + '). This Apex transaction was aborted.';
    }

    // --- Messages ---

    static String outcomeMessage(String reason, Decimal consumed, Decimal entitlement) {
        String consumedText = (consumed == null) ? 'unknown' : consumed.toPlainString();
        String entitlementText = (entitlement == null) ? 'unknown' : entitlement.toPlainString();
        return reason + ' for ' + FLEX_CREDITS_CARD
            + ' (' + DEFAULT_BUSINESS_ENV + ' / ' + DEFAULT_USAGE_MODEL + '): consumed ' + consumedText
            + ', entitlement ' + entitlementText
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
