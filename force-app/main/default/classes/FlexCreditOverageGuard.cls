/**
 * Reports whether the Flex Credits card is already at its entitlement.
 *
 * Call isOverEntitlement() at the start of an agent action and react to the
 * boolean in the caller. Returns false for every non-overage outcome (card
 * absent, action unavailable, entitlement null) — the platform enforces the
 * action independently when no FlexCredit entitlement exists.
 */
public with sharing class FlexCreditOverageGuard {

    static final String FLEX_CREDITS_CARD    = 'FlexCredits';
    static final String DEFAULT_BUSINESS_ENV = 'Production';
    static final String DEFAULT_USAGE_MODEL  = 'PrePurchased';
    static final String CONSUMPTION_ACTION   = 'computeConsumption';
    static final String CARDS_OUTPUT         = 'cards';

    /**
     * Returns true when the Production / PrePurchased Flex Credits card shows
     * consumed >= entitlement. Returns false for every other outcome.
     */
    public static Boolean isOverEntitlement() {
        Invocable.Action action = Invocable.Action.createStandardAction(CONSUMPTION_ACTION);
        action.addInvocation();
        List<Invocable.Action.Result> results = action.invoke();
        if (results == null || results.isEmpty() || !results[0].isSuccess()) {
            return false;
        }
        Map<String, Object> output = results[0].getOutputParameters();
        if (output == null || !output.containsKey(CARDS_OUTPUT) || output.get(CARDS_OUTPUT) == null) {
            return false;
        }
        List<sfdw.ConsumptionCard> cards;
        try {
            cards = (List<sfdw.ConsumptionCard>) output.get(CARDS_OUTPUT);
        } catch (System.TypeException ex) {
            return false;
        }
        sfdw.ConsumptionCard match = findFlexCreditsCard(cards);
        if (match == null || match.totalEntitlement == null) {
            return false;
        }
        Decimal entitlement = toDecimal(match.totalEntitlement);
        Decimal consumed = match.unitsConsumed == null ? 0 : toDecimal(match.unitsConsumed);
        return consumed >= entitlement;
    }

    // --- Flex Credits card lookup ---

    // Apex == is case-insensitive on String, so String.equals() is used for the
    // developer name to match the platform contract exactly.
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

    // --- Conversion ---

    // String.valueOf(Double) can produce scientific notation for large values,
    // which Decimal.valueOf(String) rejects; fall back to Decimal.valueOf(Double).
    static Decimal toDecimal(Double value) {
        String raw = String.valueOf(value);
        if (raw != null && raw.containsIgnoreCase('e')) {
            return Decimal.valueOf(value);
        }
        return Decimal.valueOf(raw);
    }
}
