# apex-flex-credit-guard

Apex a partner calls at the start of their own high-consumption transaction. If the chosen Digital Wallet card is already at its entitlement, or the upcoming call’s estimated units would reach it, `FlexCreditGuard` throws and rolls back that transaction’s DML.

```apex
FlexCreditGuard.assertWithinEntitlement('FlexCredits', estimatedUnitsForThisCall);
// then the partner’s own work
```

Call it before the work, in the same transaction. A later scheduled check cannot prevent that transaction.

This folder is a sibling of `apex-partner-digital-wallet`. It uses the same GitHub account and the same Digital Wallet org.

- GitHub: [Amit-Tripathi/apex-flex-credit-guard](https://github.com/Amit-Tripathi/apex-flex-credit-guard)
- Org alias: `DigitalWalletDemo` (Unlimited, Digital Wallet enabled). The project stores that alias locally, so the global CLI default org stays unchanged.

```bash
sf project deploy start --source-dir force-app --target-org DigitalWalletDemo
sf apex run test --tests FlexCreditGuardTest --code-coverage --result-format human --wait 10 --target-org DigitalWalletDemo
```

`FlexCredits` is an example developer name. Confirm the real card definition developer name in the target org. Salesforce Help: “Find the Card Definition Developer Name”. The display name “Flex Credits” is not that value.

## What this does not do

Digital Wallet does not throttle the product at 100%. This sample only stops Apex that calls it.

- It does not reserve credits. Concurrent transactions can all pass.
- It does not undo usage Agentforce, Data 360, or any other publisher already emitted. Those events are outside the caller’s transaction. The exception aborts this Apex transaction. It does not roll back Digital Wallet usage.
- `unitsConsumed >= totalEntitlement` only blocks work that is already at the cap. Preventing the next call from crossing the line requires `estimatedUnits`. A null estimate is treated as 0.
- Card values are near-real-time, not a synchronous balance.
- PayGo cards are meant to bill past a prepaid pool. The default buying model is `PrePurchased`. Pass `PayGo` only when that model should be capped.

## Org

Enterprise or Unlimited, or a Data One companion org, with Data 360 turned on. `sourceApiVersion` 67.0 (the `sfdw` namespace and `computeConsumption` action require 63.0 or later). Digital Wallet is not available in sandboxes.

The class reads the standard action and does not query Data Cloud DMOs:

```apex
Invocable.Action computeAction = Invocable.Action.createStandardAction('computeConsumption');
computeAction.addInvocation();
List<Invocable.Action.Result> results = computeAction.invoke();
// results[0].getOutputParameters().get('cards') -> List<sfdw.ConsumptionCard>
```

A card matches only when `cardDefinitionDeveloperName`, `businessEnvType`, and `usageModel` all match. Developer name alone is not unique. When the caller omits environment and buying model, the check uses `Production` and `PrePurchased`.

Doubles are compared as Decimals via `Decimal.valueOf(String.valueOf(...))`. Values Apex prints in scientific notation use `Decimal.valueOf(Double)` so the conversion still succeeds.

## API

| Method | Behavior |
| --- | --- |
| `assertWithinEntitlement(name, estimatedUnits)` | Production / PrePurchased. Unlimited pools are not capped. |
| `assertWithinEntitlement(name, estimatedUnits, businessEnvType, usageModel)` | Same, with an explicit environment and buying model. |
| `assertWithinEntitlement(name, estimatedUnits, businessEnvType, usageModel, capUnlimited)` | Pass `true` to also cap entitlements at or above 1,000,000,000,000. |

`CreditLimitExceededException` means the card was found and `unitsConsumed + estimatedUnits >= totalEntitlement`.

`ConsumptionUnavailableException` means the action failed, cards were missing, no card matched, or `totalEntitlement` was null. Both abort the transaction. A null `unitsConsumed` on a matched card is treated as 0.

## Tests

```bash
sf apex run test --tests FlexCreditGuardTest --code-coverage --result-format human --wait 10
```

Tests construct `sfdw.ConsumptionCard` and call `decide`. They do not invoke `computeConsumption`. The class compiles only in an org where the `sfdw` namespace exists.
