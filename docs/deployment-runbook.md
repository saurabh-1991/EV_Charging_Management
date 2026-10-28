# Deployment runbook

## 1. Firebase

- Project: `gg-ev-charging-mgmt-1fc01`
- Auth: Email/Password
- Firestore rules: `infra/firebase/firestore.rules`
- Indexes: `infra/firebase/firestore.indexes.json`

From the repo root:

```bash
firebase deploy --project gg-ev-charging-mgmt-1fc01 --only firestore:rules,firestore:indexes --config firebase.firestore.json
```

Do not use `--force` on indexes. The project may already have extra indexes; `--force` would delete them.

## 2. Mobile app

```bash
cd mobile
flutter pub get
flutter run
```

Android application id: `com.gloriagrand.evchargingmanagement`.

Release APK:

```bash
cd mobile
flutter build apk --release --build-name 1.5.5 --build-number 10
```

Shareable file: `mobile/dist/EV_Charging_Management-android-release-v1.5.5.apk`.

iOS device install needs a current Xcode that launches on this Mac plus a Development Team on the Runner target. Xcode 16.4 is incompatible with macOS 26 and will not open the Runner workspace until Xcode is updated from the App Store.

## 3. After installing a new APK

1. Install over the previous version (same application id).
2. Sign in as admin.
3. Admin → Published App Version → enter `1.5.5` → Publish.
4. Dashboard then shows matching installed and published versions.

## 4. Day-to-day operations

1. Admin sets `ratePerUnit` if MSEB/society rate changes.
2. Residents register and start charging. Start meter must exceed the point’s last end meter.
3. If a last reading is wrong, Admin → Point meter readings → Set or Clear. Not while the point is charging.
4. Residents open View Bills, download the flat PDF if needed, and submit a UPI/bank txn reference.
5. Admin marks the payment paid or rejected.
6. Month-end: Admin selects the month, Download Excel and/or Download PDF. Optionally Upload Report to Google Drive (Google account with Drive access).

## 5. Google Drive from the app

Admin taps **Upload Report to Google Drive**, signs in with Google, and grants Drive file access. The app creates/uses folder `EV Charging Reports/{yyyy-MM}`. This path does not use the Python service account in `services/billing/`.

The older service-account steps in [google-drive-backup.md](google-drive-backup.md) apply only if someone still runs `services/billing/main.py`.

## 6. Future payment gateway

Keep the current `payments` documents. Add gateway fields later (`provider`, `gatewayOrderId`, `webhookEventId`) without renaming `status` or `billingFlatKey`. See [payment-strategy-lowcost-to-automation.md](payment-strategy-lowcost-to-automation.md).
