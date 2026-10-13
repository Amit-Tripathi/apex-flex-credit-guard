// Same call an agent action makes before its own work.
// Finds the standard Flex Credits card. A throw stops this transaction.
// A normal return means the action can continue.
FlexCreditOverageGuard.assertWithinEntitlement();
System.debug('GUARD_ALLOWED FlexCredits');
