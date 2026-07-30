# iOS IAP current handoff

Updated: 2026-07-24 11:45 CST

## Confirmed consumable root cause

- The affected client used `in_app_purchase_storekit 0.4.3`.
- A completed StoreKit 2 transaction was not finished.
- On the next purchase attempt, StoreKit replayed that unfinished transaction before a new Apple payment was created.
- The client had already called `applePay/create`, so the new backend order contained a new `app_account_token`.
- The replayed Apple JWS still contained the old transaction's `appAccountToken`.
- The backend correctly rejected verification because the new order token and signed Apple token did not match.

Server evidence:

- New order: `AP20260724111511HDLA7RGD`
- New order token: `0d3ae2b4-c97f-486d-91cd-9bbf9e7dd530`
- Replayed signed token: `9dabd6a8-5e2f-46c1-ba06-3c9c42f1bc72`
- Replayed transaction: `2000001210340492`
- Signed purchase time: 2026-07-24 10:21:07 CST
- Replay/report time: 2026-07-24 11:15:13 CST

The backend screenshot also shows a different `app_account_token` for every
created order. This is expected. It becomes an error only when a transaction
signed with an older token is submitted against a newly created order.

## Implemented client changes

- Updated `in_app_purchase_storekit` to `0.4.10+1`.
- Detect StoreKit 2 unfinished transactions at startup and before purchase.
- Match a transaction to its backend order by signed `appAccountToken`.
- Parse identity fields from the Apple signed JWS and prefer them over local
  StoreKit wrapper fields.
- Verify with the backend before calling `completePurchase`.
- Call `completePurchase` after successful verification.
- Do not report UI success until StoreKit finish succeeds.
- Prevent concurrent duplicate processing.
- Add staged, persistent, copyable payment diagnostics with secret redaction.
- Refresh coin balance after successful purchase and after returning to Profile.
- Add explicit Proxyman proxy support for diagnostic builds.

## Current build/install state

- Device: `00008110-000C313E1EB9401E`
- Bundle ID: `com.yogotv.app`
- Version: `1.0.5 (9)`
- Proxyman: Mac `192.168.0.41:9090`, phone observed as `192.168.0.13`
- A Debug build was installed successfully, but launching it without Flutter
  tooling exits with:
  `Cannot create a FlutterEngine instance in debug mode without Flutter tooling or Xcode`.
- Profile builds were attempted so the app could launch independently.
- The 8 GB Mac repeatedly killed CocoaPods XCFramework copy scripts with signal
  9, including `Pods-Runner-frameworks.sh`, `AdjustSignature-xcframeworks.sh`,
  and `GoogleUserMessagingPlatform-xcframeworks.sh`.
- The last `flutter run --debug` attempt was stopped before computer restart.

## Continue after restart

Keep the phone unlocked and run:

```bash
flutter run --debug \
  -d 00008110-000C313E1EB9401E \
  --dart-define=PAYMENT_DIAGNOSTICS=true \
  --dart-define=PROXY_HOST=192.168.0.41 \
  --dart-define=PROXY_PORT=9090
```

Do not detach the Flutter process while testing a Debug build. For a package
that can launch from the phone later, build and install a Profile build after
the restart frees enough memory.

## Required test

1. Open payment diagnostics before clearing them and preserve any startup
   unfinished-transaction entries.
2. Clear diagnostics.
3. Buy one consumable SKU.
4. Confirm create, Apple sheet, transaction, verify, finish, and balance refresh.
5. Buy the same SKU again.
6. Confirm a second Apple sheet and a new signed transaction/token.
7. Copy the complete diagnostics after either success or failure.

## Auto-renewable subscription conclusion

- Initial subscription purchase uses the same client pipeline as a consumable:
  `applePay/create -> StoreKit purchase -> applePay/verify -> finish`.
- Therefore, the old missing-finish bug could also replay an unfinished initial
  subscription transaction. The client-side finish and signed-token matching
  fix applies to both product types.
- Automatic renewal is different and must not call `applePay/create`.
- Apple creates the renewal transaction in the background. The client
  transaction listener or App Store Server Notifications V2 forwards the signed
  transaction directly to the backend.
- Apple carries the original purchase's `appAccountToken` into subscription
  transaction and renewal information. A renewal must not generate a new token.
- The backend needs to process renewals idempotently using at least
  `transactionId`, `originalTransactionId`, `appAccountToken`, product ID, and
  `transactionReason=RENEWAL`.
- A renewal received by this client is sent to `applePay/verify` with no newly
  created `order_no`. The backend must not reject a valid renewal merely because
  there is no new preorder.
- The client verify payload now includes Apple's signed `transactionReason` so
  the backend can distinguish `PURCHASE` from `RENEWAL`.
