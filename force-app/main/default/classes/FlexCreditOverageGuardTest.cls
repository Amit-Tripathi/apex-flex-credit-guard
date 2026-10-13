@IsTest
private class FlexCreditOverageGuardTest {

    static sfdw.ConsumptionCard card(
        String name,
        String env,
        String model,
        Double consumed,
        Double entitlement
    ) {
        return new sfdw.ConsumptionCard(name, env, model, consumed, entitlement, null);
    }

    static List<sfdw.ConsumptionCard> flex(Double consumed, Double entitlement) {
        return new List<sfdw.ConsumptionCard>{
            card('FlexCredits', 'Production', 'PrePurchased', consumed, entitlement)
        };
    }

    @IsTest
    static void throwsWhenConsumedEqualsEntitlement() {
        try {
            FlexCreditOverageGuard.decide(flex(100, 100), false);
            Assert.fail('Expected CreditLimitExceededException');
        } catch (FlexCreditOverageGuard.CreditLimitExceededException ex) {
            Assert.isTrue(ex.getMessage().contains('Flex credit overage'));
            Assert.isTrue(ex.getMessage().contains('FlexCredits'));
            Assert.isTrue(ex.getMessage().contains('Production'));
            Assert.isTrue(ex.getMessage().contains('PrePurchased'));
            Assert.isTrue(ex.getMessage().contains('consumed 100'));
            Assert.isTrue(ex.getMessage().contains('entitlement 100'));
            Assert.isTrue(ex.getMessage().contains('This Apex transaction was aborted.'));
            Assert.isFalse(ex.getMessage().contains('estimated'));
            Assert.isFalse(ex.getMessage().contains('rolled back'));
        }
    }

    @IsTest
    static void throwsWhenConsumedExceedsEntitlement() {
        try {
            FlexCreditOverageGuard.decide(flex(101, 100), false);
            Assert.fail('Expected CreditLimitExceededException');
        } catch (FlexCreditOverageGuard.CreditLimitExceededException ex) {
            Assert.isTrue(ex.getMessage().contains('consumed 101'));
            Assert.isTrue(ex.getMessage().contains('entitlement 100'));
        }
    }

    @IsTest
    static void allowsWhenConsumedIsUnderEntitlement() {
        FlexCreditOverageGuard.decide(flex(80, 100), false);
    }

    @IsTest
    static void throwsWhenPrePurchasedCardIsMissing() {
        try {
            FlexCreditOverageGuard.decide(
                new List<sfdw.ConsumptionCard>{
                    card('FlexCredits', 'Production', 'PayGo', 10, 100)
                },
                false
            );
            Assert.fail('Expected ConsumptionUnavailableException');
        } catch (FlexCreditOverageGuard.ConsumptionUnavailableException ex) {
            Assert.isTrue(ex.getMessage().contains('No consumption card matched'));
            Assert.isTrue(ex.getMessage().contains('PrePurchased'));
            Assert.isTrue(ex.getMessage().contains('This Apex transaction was aborted.'));
        }
    }

    @IsTest
    static void throwsWhenCardListIsEmpty() {
        try {
            FlexCreditOverageGuard.decide(new List<sfdw.ConsumptionCard>(), false);
            Assert.fail('Expected ConsumptionUnavailableException');
        } catch (FlexCreditOverageGuard.ConsumptionUnavailableException ex) {
            Assert.isTrue(ex.getMessage().contains('No consumption card matched'));
        }
    }

    @IsTest
    static void throwsWhenCardsAreNull() {
        try {
            FlexCreditOverageGuard.decide(null, false);
            Assert.fail('Expected ConsumptionUnavailableException');
        } catch (FlexCreditOverageGuard.ConsumptionUnavailableException ex) {
            Assert.isTrue(ex.getMessage().contains('not returned'));
        }
    }

    @IsTest
    static void skipsUnlimitedEntitlementUnlessCallerCapsIt() {
        Double unlimited = 1000000000000.0;
        FlexCreditOverageGuard.decide(flex(unlimited, unlimited), false);

        try {
            FlexCreditOverageGuard.decide(flex(unlimited, unlimited), true);
            Assert.fail('Expected CreditLimitExceededException when unlimited pools are capped');
        } catch (FlexCreditOverageGuard.CreditLimitExceededException ex) {
            Assert.isTrue(ex.getMessage().contains('Flex credit overage'));
            Assert.isTrue(ex.getMessage().contains('FlexCredits'));
            Assert.isTrue(ex.getMessage().contains('entitlement 1000000000000'));
            Assert.isFalse(ex.getMessage().contains('E'));
        }
    }

    @IsTest
    static void throwsWhenEntitlementIsNull() {
        try {
            FlexCreditOverageGuard.decide(flex(5, null), false);
            Assert.fail('Expected ConsumptionUnavailableException');
        } catch (FlexCreditOverageGuard.ConsumptionUnavailableException ex) {
            Assert.isTrue(ex.getMessage().contains('Total entitlement was null'));
            Assert.isTrue(ex.getMessage().contains('consumed 5'));
        }
    }

    @IsTest
    static void treatsNullUnitsConsumedAsZero() {
        FlexCreditOverageGuard.decide(flex(null, 10), false);
        try {
            FlexCreditOverageGuard.decide(flex(null, 0), false);
            Assert.fail('Expected CreditLimitExceededException');
        } catch (FlexCreditOverageGuard.CreditLimitExceededException ex) {
            Assert.isTrue(ex.getMessage().contains('consumed 0'));
            Assert.isTrue(ex.getMessage().contains('entitlement 0'));
        }
    }

    @IsTest
    static void keepsSameNameCardsWithDifferentBuyingModels() {
        List<sfdw.ConsumptionCard> cards = new List<sfdw.ConsumptionCard>{
            card('FlexCredits', 'Production', 'PayGo', 500, 100),
            card('FlexCredits', 'Production', 'PrePurchased', 40, 100)
        };
        FlexCreditOverageGuard.decide(cards, false);
    }

    @IsTest
    static void ignoresCardWhoseDeveloperNameDoesNotMatch() {
        try {
            FlexCreditOverageGuard.decide(
                new List<sfdw.ConsumptionCard>{
                    card('flexcredits', 'Production', 'PrePurchased', 100, 100)
                },
                false
            );
            Assert.fail('Expected ConsumptionUnavailableException');
        } catch (FlexCreditOverageGuard.ConsumptionUnavailableException ex) {
            Assert.isTrue(ex.getMessage().contains('No consumption card matched'));
        }
    }

    @IsTest
    static void skipsNullCardEntries() {
        List<sfdw.ConsumptionCard> cards = new List<sfdw.ConsumptionCard>{
            null,
            card('FlexCredits', 'Production', 'PrePurchased', 10, 100)
        };
        FlexCreditOverageGuard.decide(cards, false);
    }

    @IsTest
    static void throwsWhenEnvironmentDoesNotMatch() {
        try {
            FlexCreditOverageGuard.decide(
                new List<sfdw.ConsumptionCard>{
                    card('FlexCredits', 'Sandbox', 'PrePurchased', 10, 100)
                },
                false
            );
            Assert.fail('Expected ConsumptionUnavailableException');
        } catch (FlexCreditOverageGuard.ConsumptionUnavailableException ex) {
            Assert.isTrue(ex.getMessage().contains('No consumption card matched'));
            Assert.isTrue(ex.getMessage().contains('Production'));
        }
    }

    @IsTest
    static void publicEntryBlocksWhenCardIsAlreadyAtEntitlement() {
        FlexCreditOverageGuard.resetOverrides();
        FlexCreditOverageGuard.cardsOverride = flex(100, 100);
        try {
            FlexCreditOverageGuard.assertWithinEntitlement();
            Assert.fail('Expected CreditLimitExceededException');
        } catch (FlexCreditOverageGuard.CreditLimitExceededException ex) {
            Assert.isTrue(ex.getMessage().contains('consumed 100'));
            Assert.isFalse(ex.getMessage().contains('estimated'));
        }
    }

    @IsTest
    static void publicEntryFailsClosedWhenActionCannotBeRead() {
        FlexCreditOverageGuard.resetOverrides();
        FlexCreditOverageGuard.actionErrorOverride = 'invoke failed';
        try {
            FlexCreditOverageGuard.assertWithinEntitlement();
            Assert.fail('Expected ConsumptionUnavailableException');
        } catch (FlexCreditOverageGuard.ConsumptionUnavailableException ex) {
            Assert.isTrue(ex.getMessage().contains('invoke failed'));
            Assert.isTrue(ex.getMessage().contains('This Apex transaction was aborted.'));
        }
    }

    @IsTest
    static void readsCardsFromTheActionOutput() {
        List<sfdw.ConsumptionCard> cards = flex(10, 100);
        Map<String, Object> output = new Map<String, Object>{ 'cards' => cards };
        List<sfdw.ConsumptionCard> read = FlexCreditOverageGuard.cardsFromOutput(output);
        Assert.areEqual(1, read.size());
        FlexCreditOverageGuard.decide(read, false);
    }

    @IsTest
    static void throwsWhenActionOutputHasNoCards() {
        try {
            FlexCreditOverageGuard.cardsFromOutput(null);
            Assert.fail('Expected ConsumptionUnavailableException');
        } catch (FlexCreditOverageGuard.ConsumptionUnavailableException ex) {
            Assert.isTrue(ex.getMessage().contains('cards were not returned'));
        }

        try {
            FlexCreditOverageGuard.cardsFromOutput(new Map<String, Object>());
            Assert.fail('Expected ConsumptionUnavailableException');
        } catch (FlexCreditOverageGuard.ConsumptionUnavailableException ex) {
            Assert.isTrue(ex.getMessage().contains('cards were not returned'));
        }

        try {
            FlexCreditOverageGuard.cardsFromOutput(new Map<String, Object>{ 'cards' => null });
            Assert.fail('Expected ConsumptionUnavailableException');
        } catch (FlexCreditOverageGuard.ConsumptionUnavailableException ex) {
            Assert.isTrue(ex.getMessage().contains('cards were not returned'));
        }
    }

    @IsTest
    static void throwsWhenActionOutputIsNotACardList() {
        try {
            FlexCreditOverageGuard.cardsFromOutput(new Map<String, Object>{ 'cards' => 'not-cards' });
            Assert.fail('Expected ConsumptionUnavailableException');
        } catch (FlexCreditOverageGuard.ConsumptionUnavailableException ex) {
            Assert.isTrue(ex.getMessage().contains('This Apex transaction was aborted.'));
        }
    }

    @IsTest
    static void describesAFailedActionResult() {
        Assert.areEqual('no result', FlexCreditOverageGuard.errorDetail(null));
        Assert.areEqual(
            'no result',
            FlexCreditOverageGuard.errorDetail(new List<Invocable.Action.Result>())
        );
    }
}
