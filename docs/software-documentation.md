# Software documentation

Gloria Grand EV Charging Management is a Flutter client against Firebase Auth and Cloud Firestore. Version **1.5.5** is the current Android release.

## 1. Purpose

The society previously wrote meter readings on paper. The app records start/stop sessions, calculates kWh and INR, groups every login on the same flat into one bill, and lets admin collect and verify UPI/bank references.

Society layout used by the software:

- Wing **B1**: 18 floors × 6 flats
- Wing **B2**: 23 floors × 6 flats
- Charging points: `B1-P1`, `B1-P2`, `B2-P1`, `B2-P2`

## 2. Tech stack

| Layer | Choice |
| --- | --- |
| Client | Flutter 3 / Dart, Material 3, teal theme |
| Auth | Firebase Auth email/password |
| Database | Cloud Firestore |
| Config | `appConfig/rates`, `appConfig/appVersion` |
| Reports | `excel` + `pdf` + `share_plus` |
| Drive backup | Google Sign-In (`drive.file` scope) from Admin |
| Version display | `package_info_plus` (installed) + Firestore (published) |

There is no application server. Security is in Firestore rules. Monthly bills are computed on the device from live queries.

## 3. Application modules

```
mobile/lib/
  main.dart                         bootstrap
  app.dart                          routes
  config/app_config.dart            fallback rate INR 15
  firebase/firebase_bootstrap.dart  Firebase init
  core/flat_billing.dart            flat key and due math
  core/flat_session_merge.dart      merge session streams
  core/flat_payment_linker.dart     tag payments/sessions; submit UPI ref
  features/auth/                    login, gate, disabled screen
  features/dashboard/               home snapshot
  features/sessions/                start/stop and last meter
  features/billing/                 monthly bill + PDF + payment
  features/admin/                   reports, meters, users, rates
  features/payments/                unused standalone pay page
  features/booking/                 unused slot booking page
```

Wired routes in `app.dart`: Dashboard, Start/Stop Charging, View Bills, Admin. `PaymentPage` and `SlotBookingPage` exist on disk but are not on the home menu. Residents pay from **View Bills**. Booking is not in the live navigation.

## 4. Identity and profiles

A user document is `users/{uid}`.

| Field | Meaning |
| --- | --- |
| `email`, `name` | Display and login identity |
| `wing` | Home wing (`B1` or `B2`) |
| `flatNumber` | Home flat string, stored as typed (for example `B2-805` or `1102`) |
| `vehicles[]`, `defaultVehicle`, `vehicleNumber` | Per-login vehicles |
| `role` | `resident` or `admin` |
| `status` | `active` (default on register) or `disabled` |

Self-register creates `role: resident` and `status: active`. Admin can create a user, change role, or disable. A disabled account still authenticates, then `AuthGate` shows the blocked screen.

Flat grouping uses **exact** `wing` + `flatNumber` strings. `B1-805` and `B2-805` stay separate. Blank wing or flat is not grouped.

## 5. Charging sessions

`SessionRepository.startChargingSession` / `stopChargingSession` run Firestore transactions.

On start:

1. Point must not be occupied.
2. Start meter ≥ 0.
3. Start meter must be **greater than** `chargingSlots/{pointKey}.lastEndMeter` when that field exists.
4. Session `wing` / `pointKey` are the **charging point**.
5. `billingWing` / `billingFlatKey` are the resident’s **home** wing and flat.
6. Occupied slot is written. A same-hour booking for another resident is marked `overridden`; the owner’s own booking is marked `used`.

On stop:

1. End meter must be greater than that session’s start meter.
2. `units = endMeter - startMeter`, `amount = units * ratePerUnit`.
3. Status becomes `completed`.
4. Slot is freed and `lastEndMeter` is stored on the point.

Vehicles collection writes happen after the transaction and are best-effort so a vehicles permission error cannot block charging.

## 6. Meter continuity

Each point document stores `lastEndMeter`. The Start/Stop screen shows it. A lower or equal start is rejected in the UI and again in the transaction.

Admin **Point meter readings** can Set or Clear that value. An admin-set value is flagged `lastMeterSetByAdmin` so automatic backfill from old sessions does not overwrite it. A later completed session at that point writes a new last meter and clears the admin flag.

A point that is currently charging cannot be corrected until it stops.

## 7. Shared flat billing

Multiple emails can share one wing + flat. Vehicles stay per login. Dues, units, and payments are per flat.

Sessions count on a bill when:

- status is `completed`, and
- `billingWing` + `flatNumber` match the viewer’s home, or
- the viewer owns the session and `flatNumber` matches (covers older B1-point sessions before `billingWing` existed), or
- charging-point `wing` + `flatNumber` match.

Payments count when `billingFlatKey` (or wing+flat fields) match. `paid` and `verified` reduce due. `submitted` and `rejected` do not. Due never goes below 0.

`FlatSessionMerge` queries:

- `ownerUid == me`
- `wing == homeWing AND flatNumber == homeFlat`
- `billingWing == homeWing AND flatNumber == homeFlat`

The billing-wing query is ignored if its index is still building so own charges still appear.

## 8. Payments

Launch model is UPI/bank transfer outside the app.

1. Resident opens View Bills for a month and submits amount + transaction reference.
2. The payment is stored as `status: submitted` with `billingFlatKey`.
3. One pending request per flat per month. Duplicate `txnRef` for that flat+month is rejected.
4. Admin marks `paid` or `rejected`.
5. Dashboard and bills subtract only paid/verified amounts.

## 9. Admin reports

For the selected `yyyy-MM` month, Admin builds:

- **Summary**: one row per flat (names/emails joined)
- **Sessions**: each completed session
- **Payments**: each payment

Download Excel uses the existing payments index (`monthKey` + `createdAt` descending) and still writes the sheet oldest-first. Download PDF is a landscape statement of the same three tables. Upload to Drive uses the signed-in Google account and folders `EV Charging Reports/{month}`.

## 10. Configuration

| Document | Fields | Who writes |
| --- | --- | --- |
| `appConfig/rates` | `ratePerUnit` | Admin |
| `appConfig/appVersion` | `currentVersion` | Admin Publish |

The home screen shows installed version from the binary and published version from Firestore. After installing 1.5.5, publish `1.5.5` in Admin so they match.

## 11. Security (Firestore)

High-level rules:

- Users: own document, or admin. Residents cannot list other UIDs.
- Sessions: admin, owner, or same home flat (point wing **or** billing wing).
- Payments: admin, owner, or same `billingFlatKey`.
- Create payment may omit `billingFlatKey` so older APKs still work; if present it must equal the caller’s profile key.
- Resident payment update may only add wing/flat/billingFlatKey and cannot move a key already set to another flat.
- Session update: admin or owner (so the owner can stamp `billingWing`).
- Deletes are denied.

Full rules: `infra/firebase/firestore.rules`. Indexes: `infra/firebase/firestore.indexes.json`.

## 12. Known unused code

- `features/payments/payment_page.dart` — payment is on View Bills.
- `features/booking/slot_booking_page.dart` — start charging still reconciles `slotBookings` if a booking exists for that hour.
- `services/billing/` — Python PDF helper. Live invoices are generated in Flutter.

## 13. Version history (recent)

| Version | What changed |
| --- | --- |
| 1.5.2 | Dashboard dues/consumption snapshot and DB version |
| 1.5.3 | Shared flat bills |
| 1.5.4 | B1-point charges kept on the home-wing bill (`billingWing`) |
| 1.5.5 | Admin Excel/PDF reports, last-meter enforcement, admin meter reset |
