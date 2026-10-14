@IsTest
private class FlexCreditOverageGuardTest {

    @IsTest
    static void isOverEntitlementReturnsBoolean() {
        Boolean result = FlexCreditOverageGuard.isOverEntitlement();
        Assert.isNotNull(result);
    }
}
