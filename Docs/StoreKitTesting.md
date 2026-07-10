# StoreKit testing for GirokIQ Pro

GirokIQ now uses StoreKit 2 product identifiers for the pricing screen:

- `com.girokiq.pro.monthly`
- `com.girokiq.pro.annual`

## Fast local test flow

1. In Xcode, create a new `StoreKit Configuration File`.
2. Add one subscription group named `GirokIQ Pro`.
3. Add these auto-renewable subscriptions to that group:
   - `com.girokiq.pro.monthly`
   - `com.girokiq.pro.annual`
4. Use the same prices shown in the pricing screen:
   - Monthly: `4.99`
   - Annual: `39.99`
5. Attach the StoreKit file to the `GirokIQ-ios` run scheme:
   - `Product` -> `Scheme` -> `Edit Scheme...` -> `Run` -> `Options` -> `StoreKit Configuration`
6. Run the app and open:
   - Sidebar profile card -> `Settings`
   - `Account` -> `Upgrade to GirokIQ Pro`

## What to verify

1. Free account starts with:
   - `Student` plan in pricing
   - free AI tier
   - `10` AI requests/day
2. Buy `Monthly`:
   - pricing screen should show Pro as active
   - `app_state.subscription_tier` should become `pro`
   - AI should move to the Pro tier
3. Restore purchases:
   - tap `Restore Purchases`
   - Pro should become active again if the StoreKit entitlement exists
4. Expire or revoke in StoreKit Test:
   - entitlement should disappear
   - `subscription_tier` should sync back to `free`

## Sandbox test flow

You can also test without a real card by using an App Store sandbox tester:

1. Create the same products in App Store Connect.
2. Create a sandbox tester account.
3. Sign into the test device with the sandbox account when prompted by the purchase sheet.
4. Run the same free -> buy -> restore -> expire checks.

No real credit card or Apple Pay is required for either StoreKit local testing or App Store sandbox testing.
