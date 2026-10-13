# apex-flex-credit-overage-guard

Call `FlexCreditOverageGuard` at the start of an agent action that will consume Flex Credits. If that card is already at its entitlement, the guard throws and rolls back the action’s DML. The caller does not pass an estimate of what this call will use.

```apex
FlexCreditOverageGuard.assertWithinEntitlement();
// then the agent action continues
```

An agent action calls it once, then does its own work. A throw stops that action. A normal return means the action continues. A later scheduled check cannot prevent the transaction that is already running.

The guard reads `computeConsumption` and finds the `sfdw.ConsumptionCard` whose `cardDefinitionDeveloperName` is `FlexCredits`, `businessEnvType` is `Production`, and `usageModel` is `PrePurchased`. Those values are on the standard card. The caller does not pass them.

## Deploy and test

Org alias: `DigitalWalletDemo` (Unlimited, Digital Wallet enabled). The project stores that alias locally, so the global CLI default org stays unchanged.

```bash
sf project deploy start --source-dir force-app --target-org DigitalWalletDemo
sf apex run test --tests FlexCreditOverageGuardTest --code-coverage --result-format human --wait 10 --target-org DigitalWalletDemo
```

## What this does not do

Digital Wallet does not throttle the product at 100%. This sample only stops Apex that calls it.

- It does not reserve credits. Concurrent transactions can all pass.
- It does not undo usage that Agentforce, Data 360, or any other publisher already emitted. Those events are outside the caller’s transaction. The exception aborts this Apex transaction. It does not roll back Digital Wallet usage.
- It blocks when units already consumed are at or over the entitlement. It does not estimate what this call will use. A call that starts under the cap can still finish over it.
- Card values are near-real-time, not a synchronous balance.
- PayGo cards are meant to bill past a prepaid pool. This check uses the PrePurchased Flex Credits card.

## How to read the code

`FlexCreditOverageGuard` is one class. There is no SOQL and no other package dependency.

- `assertWithinEntitlement` is what the agent action calls. It reads the org, then applies the rule.
- `fetchCards` is the only org read. It calls `computeConsumption` once. That action returns every `sfdw.ConsumptionCard`. Tests stub that read with `cardsOverride` or `actionErrorOverride`, then call `resetOverrides`.
- `decide` keeps the card whose `cardDefinitionDeveloperName` is `FlexCredits`, with `businessEnvType` `Production` and `usageModel` `PrePurchased`. It ignores the other cards.

The match uses `String.equals` on `cardDefinitionDeveloperName`, `businessEnvType`, and `usageModel`, because Apex `==` ignores case. The display name “Flex Credits” is not the developer name.

Doubles on the card are compared as Decimals. Values Apex prints in scientific notation still convert, and exception text uses the plain number.

```apex
Invocable.Action computeAction = Invocable.Action.createStandardAction('computeConsumption');
computeAction.addInvocation();
List<Invocable.Action.Result> results = computeAction.invoke();
// results[0].getOutputParameters().get('cards') -> List<sfdw.ConsumptionCard>
```

## API

| Method | Behavior |
| --- | --- |
| `assertWithinEntitlement()` | Finds the Production / PrePurchased Flex Credits card. Blocks when consumed units are already at or over the entitlement. Unlimited pools are not capped. |

`CreditLimitExceededException` means that card was found and `unitsConsumed >= totalEntitlement`. The message starts with `Flex credit overage`.

`ConsumptionUnavailableException` means the action failed, cards were missing, the Flex Credits card was not in the list, or `totalEntitlement` was null. Both stop the action. A null `unitsConsumed` on a matched card is treated as 0.

## Org

Enterprise or Unlimited, or a Data One companion org, with Data 360 turned on. `sourceApiVersion` 67.0 (the `sfdw` namespace and `computeConsumption` action require 63.0 or later). Digital Wallet is not available in sandboxes.

The class compiles only in an org where the `sfdw` namespace exists. Tests do not invoke `computeConsumption`.

To run the same Flex Credits check an agent action makes:

```bash
sf apex run --file scripts/apex/tryOverageGuard.apex --target-org DigitalWalletDemo
```

The script does not catch the exception. If Flex Credits is at or over the entitlement, the anonymous execution fails and the transaction stops. If it is under, the log shows `GUARD_ALLOWED`.

## Related

This project is a sibling of `apex-partner-digital-wallet`. It uses the same GitHub account and the same Digital Wallet org.

- GitHub: [Amit-Tripathi/apex-flex-credit-overage-guard](https://github.com/Amit-Tripathi/apex-flex-credit-overage-guard)
