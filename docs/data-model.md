# Data model

Live Firestore project: `gg-ev-charging-mgmt-1fc01`. There is one society in this deployment. There is no `societies` collection.

## Collections

### `users/{uid}`

| Field | Type | Notes |
| --- | --- | --- |
| `email` | string | Login email |
| `name` | string | Display name |
| `wing` | string | Home wing, `B1` or `B2` |
| `flatNumber` | string | Home flat, exact string used as bill key |
| `vehicleNumber` | string | Legacy single vehicle |
| `vehicles` | array of string | Per-login vehicles |
| `defaultVehicle` | string | Default for start charging |
| `role` | string | `resident` or `admin` |
| `status` | string | `active` or `disabled` |
| `createdAt`, `updatedAt` | timestamp | |

Reads: owner or admin. Creates: signed-in user writing own doc as resident. Deletes denied.

### `chargingSlots/{pointKey}`

Document ids: `B1-P1`, `B1-P2`, `B2-P1`, `B2-P2`.

| Field | Type | Notes |
| --- | --- | --- |
| `wing`, `chargingPoint`, `pointKey` | | Identity |
| `occupied` | bool | True while a session is active |
| `currentSessionId` | string or null | |
| `residentName`, `flatNumber`, `vehicleNumber` | string or null | Occupant while charging |
| `startedAt` | timestamp | |
| `lastEndMeter` | number | Last completed end reading |
| `lastEndedAt` | timestamp | |
| `lastMeterSetByAdmin` | bool | True after admin Set/Clear |
| `updatedAt` | timestamp | |

### `chargingSessions/{sessionId}`

| Field | Type | Notes |
| --- | --- | --- |
| `ownerUid` | string | Who started the session |
| `billingOwnerUid` | string | Same as owner at start |
| `residentName` | string | |
| `wing` | string | **Charging-point** wing |
| `billingWing` | string | **Home** wing for the bill |
| `billingFlatKey` | string | `homeWing\|flatNumber` |
| `floor` | number | Derived from flat |
| `flat`, `flatNumber`, `billingFlatNumber` | string | Home flat |
| `chargingPoint` | number | 1 or 2 |
| `pointKey` | string | `B1-P1` style |
| `vehicleNumber` | string | |
| `isGuestVehicle` | bool | Guest still bills the logged-in flat |
| `startMeter`, `endMeter` | number | `endMeter` null while active |
| `ratePerUnit` | number | Snapshot at start |
| `units`, `amount` | number | Set on stop |
| `status` | string | `active` or `completed` |
| `monthKey` | string | `yyyy-MM` |
| `startTime`, `endTime`, `createdAt`, `updatedAt` | timestamp | |

Reads: admin, owner, or same-flat by point wing or billing wing.

### `payments/{paymentId}`

| Field | Type | Notes |
| --- | --- | --- |
| `ownerUid` | string | Submitter |
| `txnRef` | string | UPI/bank reference, stored uppercased |
| `amount` | number | |
| `monthKey` | string | `yyyy-MM` |
| `status` | string | `submitted`, `paid`, `verified`, `rejected` |
| `wing`, `flatNumber`, `billingFlatKey` | string | Home flat tag |
| `requestedAt`, `createdAt` | timestamp | |
| `verifiedBy`, `verifiedAt`, `paidAt` | | Set by admin |

`paid` and `verified` both count as settled.

### `appConfig/rates`

| Field | Type |
| --- | --- |
| `ratePerUnit` | number |
| `updatedAt`, `updatedBy` | |

Fallback in code if missing: `AppConfig.ratePerUnitInr` = 15.

### `appConfig/appVersion`

| Field | Type |
| --- | --- |
| `currentVersion` | string | Shown on dashboard |
| `updatedAt`, `updatedBy` | |

### `vehicles/{vehicleDocId}`

Best-effort analytics: last charged, totals. Missing permission must not block start/stop.

### `slotBookings/{bookingId}`

Id pattern: `{yyyy-MM-dd}_{pointKey}_{hour}`. Status values: `booked`, `used`, `overridden`. The booking screen is not on the home menu; start charging still updates a matching hour booking if one exists.

## Billing key

`billingFlatKey` / profile key = `wing + '|' + flatNumber` with **no** extra trim or case change beyond what was stored on the profile.

Untagged legacy payments attach to the creator’s current flat only when that account opens the app or an admin opens Admin. A payment already tagged to another flat is never moved.

## Indexes used by the live queries

Defined in `infra/firebase/firestore.indexes.json`. The ones the 1.5.5 app depends on include:

- `chargingSessions`: `monthKey` + `status` + `createdAt`
- `chargingSessions`: `billingWing` + `flatNumber`
- `chargingSessions`: `wing` + `flatNumber` (+ optional `createdAt` / `vehicleNumber`)
- `payments`: `monthKey` + `createdAt` descending
- `payments`: `ownerUid` + `monthKey` + `createdAt` / `status`
