# apex-flex-credit-overage-guard

Call `FlexCreditOverageGuard` at the start of an agent action that will consume Flex Credits. If that card is already at its entitlement, the guard throws and rolls back the action’s DML. The caller does not pass an estimate of what this call will use.

```apex
FlexCreditOverageGuard.assertWithinEntitlement();
// then the agent action continues
```

An agent action calls it once, then does its own work. A throw stops that action. A normal return means the action continues. A later scheduled check cannot prevent the transaction that is already running.

The guard reads `computeConsumption` and compares `unitsConsumed` with `totalEntitlement` on the `sfdw.ConsumptionCard` whose `cardDefinitionDeveloperName` is `FlexCredits`, `businessEnvType` is `Production`, and `usageModel` is `PrePurchased`. Those two amounts are already on the card. The caller does not pass the card name.

## Deploy and test

Deploy to an Enterprise or Unlimited org with Digital Wallet enabled. The commands use the Salesforce CLI default org.

```bash
sf project deploy start --source-dir force-app
sf apex run test --tests FlexCreditOverageGuardTest --code-coverage --result-format human --wait 10
```

## What this does not do

Digital Wallet does not throttle the product at 100%. This sample only stops Apex that calls it.

- It does not reserve credits. Concurrent transactions can all pass.
- It does not undo usage that Agentforce, Data 360, or any other publisher already emitted. Those events are outside the caller’s transaction. The exception aborts this Apex transaction. It does not roll back Digital Wallet usage.
- It blocks when units already consumed are at or over the entitlement. It does not estimate what this call will use. A call that starts under the cap can still finish over it.
- Card values are near-real-time, not a synchronous balance.
- PayGo cards are meant to bill past a prepaid pool. This check uses the PrePurchased Flex Credits card.
- No special handling is applied for very large entitlements. The rule is always `unitsConsumed >= totalEntitlement`.

## Customizing the card filter

The guard matches a specific card by three string constants near the top of
`FlexCreditOverageGuard.cls`:

| Constant | Value | What it matches |
| --- | --- | --- |
| `FLEX_CREDITS_CARD` | `FlexCredits` | `cardDefinitionDeveloperName` |
| `DEFAULT_BUSINESS_ENV` | `Production` | `businessEnvType` |
| `DEFAULT_USAGE_MODEL` | `PrePurchased` | `usageModel` |

To guard a different card, change these values directly in the class. The match
is case-sensitive (`String.equals` is used, not Apex `==`).

## How to read the code

`FlexCreditOverageGuard` is one class. There is no SOQL and no other package dependency.

- `assertWithinEntitlement` is what the agent action calls. It reads the org, then applies the rule.
- `fetchCards` is the only org read. It calls `computeConsumption` once. That action returns every `sfdw.ConsumptionCard`, and each card already has `unitsConsumed` and `totalEntitlement`. Tests stub that read with `cardsOverride` or `actionErrorOverride`, then call `resetOverrides`.
- `decide` keeps the card whose `cardDefinitionDeveloperName` is `FlexCredits`, with `businessEnvType` `Production` and `usageModel` `PrePurchased`. It blocks when `unitsConsumed >= totalEntitlement`.

The match uses `String.equals` on `cardDefinitionDeveloperName`, `businessEnvType`, and `usageModel`, because Apex `==` ignores case. The display name “Flex Credits” is not the developer name.

Doubles on the card are compared as Decimals. Values Apex prints in scientific notation still convert, and exception text uses the plain number.

```apex
Invocable.Action computeAction = Invocable.Action.createStandardAction('computeConsumption');
computeAction.addInvocation();
List<Invocable.Action.Result> results = computeAction.invoke();
// results[0].getOutputParameters().get('cards') -> List<sfdw.ConsumptionCard>
// FlexCredits card: unitsConsumed compared with totalEntitlement
```

## API

| Method | Behavior |
| --- | --- |
| `assertWithinEntitlement()` | Finds the Production / PrePurchased Flex Credits card. Blocks when consumed units are already at or over the entitlement. Unlimited pools are not capped. |

`CreditLimitExceededException` means that card was found and `unitsConsumed >= totalEntitlement`. The message starts with `Flex credit overage`.

`ConsumptionUnavailableException` means the action failed, cards were missing, the Flex Credits card was not in the list, or `totalEntitlement` was null. Both stop the action. A null `unitsConsumed` on a matched card is treated as 0.

## Error message

A throw stops the action. The exception text is not what the user sees unless the calling action returns it. Catch both exceptions, roll back any DML already done in that transaction, and put `getMessage()` on an output variable. The agent reads that output. An uncaught throw still aborts the transaction; the user then gets the agent’s system error message.

```apex
Savepoint sp = Database.setSavepoint();
try {
    FlexCreditOverageGuard.assertWithinEntitlement();
    // then the agent action continues
} catch (FlexCreditOverageGuard.CreditLimitExceededException e) {
    Database.rollback(sp);
    result.errorMessage = e.getMessage();
} catch (FlexCreditOverageGuard.ConsumptionUnavailableException e) {
    Database.rollback(sp);
    result.errorMessage = e.getMessage();
}
```

Declare `errorMessage` as an `@InvocableVariable` on the action output. Both builders take that output and store it in one of their variables, then tell the agent to show it. Follow the current docs for the assignment; the screens and script properties change.

- Agent Script: [Actions](https://developer.salesforce.com/docs/ai/agentforce/guide/ascript-ref-actions.html) (action outputs the agent can read) and [Variables](https://developer.salesforce.com/docs/ai/agentforce/guide/ascript-patterns-variables.html) (store an action output in a variable and show it). The separate system error message is in the [system block](https://developer.salesforce.com/docs/ai/agentforce/guide/ascript-blocks.html).
- Legacy Agent Builder: [Custom agent actions](https://help.salesforce.com/s/articleView?id=ai.copilot_actions_custom.htm&language=en_US&type=5) (map the Apex output and the instructions that tell the agent to show it) and [Agent actions](https://help.salesforce.com/s/articleView?id=sf.copilot_actions.htm&language=en_US&type=5).

## Org

Enterprise or Unlimited, or a Data One companion org, with Data 360 turned on. `sourceApiVersion` 67.0 (the `sfdw` namespace and `computeConsumption` action require 63.0 or later). Digital Wallet is not available in sandboxes.

The class compiles only in an org where the `sfdw` namespace exists. Tests do not invoke `computeConsumption`.

To run the same Flex Credits check an agent action makes:

```bash
sf apex run --file scripts/apex/tryOverageGuard.apex
```

The script does not catch the exception. If Flex Credits is at or over the entitlement, the anonymous execution fails and the transaction stops. If it is under, the log shows `GUARD_ALLOWED`.

## Related

This project is a sibling of `apex-partner-digital-wallet`.

- GitHub: [Amit-Tripathi/apex-flex-credit-overage-guard](https://github.com/Amit-Tripathi/apex-flex-credit-overage-guard)
