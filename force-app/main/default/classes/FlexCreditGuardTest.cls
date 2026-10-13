@IsTest
private class FlexCreditGuardTest {

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
            FlexCreditGuard.decide(flex(100, 100), 'FlexCredits', 'Production', 'PrePurchased', 0, false);
            Assert.fail('Expected CreditLimitExceededException');
        } catch (FlexCreditGuard.CreditLimitExceededException ex) {
            Assert.isTrue(ex.getMessage().contains('FlexCredits'));
            Assert.isTrue(ex.getMessage().contains('Production'));
            Assert.isTrue(ex.getMessage().contains('PrePurchased'));
            Assert.isTrue(ex.getMessage().contains('consumed 100'));
            Assert.isTrue(ex.getMessage().contains('estimated 0'));
            Assert.isTrue(ex.getMessage().contains('entitlement 100'));
            Assert.isTrue(ex.getMessage().contains('This Apex transaction was aborted.'));
            Assert.isFalse(ex.getMessage().contains('rolled back'));
        }
    }

    @IsTest
    static void throwsWhenEstimateCrossesEntitlement() {
        try {
            FlexCreditGuard.decide(flex(80, 100), 'FlexCredits', 'Production', 'PrePurchased', 25, false);
            Assert.fail('Expected CreditLimitExceededException');
        } catch (FlexCreditGuard.CreditLimitExceededException ex) {
            Assert.isTrue(ex.getMessage().contains('consumed 80'));
            Assert.isTrue(ex.getMessage().contains('estimated 25'));
            Assert.isTrue(ex.getMessage().contains('entitlement 100'));
        }
    }

    @IsTest
    static void allowsEstimateThatStaysUnderEntitlement() {
        FlexCreditGuard.decide(flex(80, 100), 'FlexCredits', 'Production', 'PrePurchased', 10, false);
    }

    @IsTest
    static void throwsWhenUsageModelDoesNotMatch() {
        try {
            FlexCreditGuard.decide(flex(10, 100), 'FlexCredits', 'Production', 'PayGo', 0, false);
            Assert.fail('Expected ConsumptionUnavailableException');
        } catch (FlexCreditGuard.ConsumptionUnavailableException ex) {
            Assert.isTrue(ex.getMessage().contains('No consumption card matched'));
            Assert.isTrue(ex.getMessage().contains('PayGo'));
            Assert.isTrue(ex.getMessage().contains('This Apex transaction was aborted.'));
        }
    }

    @IsTest
    static void throwsWhenCardListIsEmpty() {
        try {
            FlexCreditGuard.decide(
                new List<sfdw.ConsumptionCard>(),
                'FlexCredits',
                'Production',
                'PrePurchased',
                0,
                false
            );
            Assert.fail('Expected ConsumptionUnavailableException');
        } catch (FlexCreditGuard.ConsumptionUnavailableException ex) {
            Assert.isTrue(ex.getMessage().contains('No consumption card matched'));
        }
    }

    @IsTest
    static void throwsWhenCardsAreNull() {
        try {
            FlexCreditGuard.decide(null, 'FlexCredits', 'Production', 'PrePurchased', 0, false);
            Assert.fail('Expected ConsumptionUnavailableException');
        } catch (FlexCreditGuard.ConsumptionUnavailableException ex) {
            Assert.isTrue(ex.getMessage().contains('not returned'));
        }
    }

    @IsTest
    static void skipsUnlimitedEntitlementUnlessCallerCapsIt() {
        Double unlimited = 1000000000000.0;
        FlexCreditGuard.decide(flex(unlimited, unlimited), 'FlexCredits', null, null, 1, false);

        try {
            FlexCreditGuard.decide(flex(unlimited, unlimited), 'FlexCredits', 'Production', 'PrePurchased', 0, true);
            Assert.fail('Expected CreditLimitExceededException when unlimited pools are capped');
        } catch (FlexCreditGuard.CreditLimitExceededException ex) {
            Assert.isTrue(ex.getMessage().contains('FlexCredits'));
            Assert.isTrue(ex.getMessage().contains('entitlement'));
        }
    }

    @IsTest
    static void throwsWhenEntitlementIsNull() {
        try {
            FlexCreditGuard.decide(flex(5, null), 'FlexCredits', 'Production', 'PrePurchased', 0, false);
            Assert.fail('Expected ConsumptionUnavailableException');
        } catch (FlexCreditGuard.ConsumptionUnavailableException ex) {
            Assert.isTrue(ex.getMessage().contains('Total entitlement was null'));
            Assert.isTrue(ex.getMessage().contains('consumed 5'));
        }
    }

    @IsTest
    static void treatsNullUnitsConsumedAsZero() {
        FlexCreditGuard.decide(flex(null, 10), 'FlexCredits', 'Production', 'PrePurchased', 0, false);
        try {
            FlexCreditGuard.decide(flex(null, 10), 'FlexCredits', 'Production', 'PrePurchased', 10, false);
            Assert.fail('Expected CreditLimitExceededException');
        } catch (FlexCreditGuard.CreditLimitExceededException ex) {
            Assert.isTrue(ex.getMessage().contains('consumed 0'));
            Assert.isTrue(ex.getMessage().contains('estimated 10'));
        }
    }

    @IsTest
    static void keepsSameNameCardsWithDifferentBuyingModels() {
        List<sfdw.ConsumptionCard> cards = new List<sfdw.ConsumptionCard>{
            card('FlexCredits', 'Production', 'PayGo', 500, 100),
            card('FlexCredits', 'Production', 'PrePurchased', 40, 100)
        };
        FlexCreditGuard.decide(cards, 'FlexCredits', 'Production', 'PrePurchased', 10, false);
    }

    @IsTest
    static void publicEntryUsesOverrideAndTreatsNullEstimateAsZero() {
        FlexCreditGuard.cardsOverride = flex(100, 100);
        try {
            FlexCreditGuard.assertWithinEntitlement('FlexCredits', null);
            Assert.fail('Expected CreditLimitExceededException');
        } catch (FlexCreditGuard.CreditLimitExceededException ex) {
            Assert.isTrue(ex.getMessage().contains('estimated 0'));
        }
    }

    @IsTest
    static void publicEntryFailsClosedWhenActionCannotBeRead() {
        FlexCreditGuard.actionErrorOverride = 'invoke failed';
        try {
            FlexCreditGuard.assertWithinEntitlement('FlexCredits', 1, 'Production', 'PrePurchased');
            Assert.fail('Expected ConsumptionUnavailableException');
        } catch (FlexCreditGuard.ConsumptionUnavailableException ex) {
            Assert.isTrue(ex.getMessage().contains('invoke failed'));
            Assert.isTrue(ex.getMessage().contains('This Apex transaction was aborted.'));
        }
    }
}
