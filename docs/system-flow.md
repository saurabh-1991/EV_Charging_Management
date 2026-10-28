# Software and system flow

This document is the operational flow of Gloria Grand EV Charging Management 1.5.5. Boxes are screens or collections that exist in the running app.

## 1. System context

```mermaid
flowchart TB
  Resident[Resident phone]
  AdminUser[Admin phone]
  Auth[Firebase Auth]
  FS[(Cloud Firestore)]
  Drive[Google Drive]

  Resident -->|email/password| Auth
  AdminUser -->|email/password| Auth
  Resident -->|sessions, bills, payments| FS
  AdminUser -->|users, rates, reports, meters| FS
  AdminUser -->|optional Excel upload| Drive
```

The Flutter app is the only runtime for residents. Firestore holds all durable state. Google Drive is optional and only used from Admin.

## 2. App navigation

```mermaid
flowchart TD
  Start[App launch] --> Init{Firebase ready?}
  Init -->|no| Setup[Setup pending screen]
  Init -->|yes| AuthState{Signed in?}
  AuthState -->|no| Login[Login / Register]
  AuthState -->|yes| Profile[Load users/uid]
  Profile --> Status{status}
  Status -->|disabled| Blocked[Blocked screen]
  Status -->|active or missing doc| Dash[Dashboard]
  Dash --> Charge[Start/Stop Charging]
  Dash --> Bills[View Bills]
  Dash --> Admin{role is admin?}
  Admin -->|yes| Panel[Admin Panel]
  Admin -->|no| Dash
```

## 3. Register and login

```mermaid
sequenceDiagram
  actor User
  participant App
  participant Auth as Firebase Auth
  participant FS as Firestore users

  User->>App: Register name, wing, flat, vehicle, email, password
  App->>Auth: createUserWithEmailAndPassword
  Auth-->>App: uid
  App->>FS: set users/uid role=resident status=active
  App-->>User: Registered. Dashboard opens if still signed in

  User->>App: Login email/password
  App->>Auth: signInWithEmailAndPassword
  Auth-->>App: uid
  App->>FS: snapshot users/uid
  alt status is disabled
    App-->>User: Blocked until admin reactivates
  else
    App-->>User: Dashboard
  end
```

Self-register does **not** wait for admin approval. Admin disable is the only block.

## 4. Start charging

```mermaid
flowchart TD
  Open[Open Start/Stop] --> Pick[Select point in own wing]
  Pick --> ShowLast[Show lastEndMeter for that point]
  ShowLast --> Enter[Enter start meter, vehicle]
  Enter --> Guard{start greater than lastEndMeter?}
  Guard -->|no| Reject[Toast: start must be greater]
  Guard -->|yes| Txn[Transaction]
  Txn --> Occ{point occupied?}
  Occ -->|yes| Busy[slot-occupied]
  Occ -->|no| Write[Write chargingSessions active]
  Write --> Slot[Set chargingSlots occupied]
  Slot --> Book{hour booking exists?}
  Book -->|own booked| Used[status used]
  Book -->|other booked| Override[status overridden]
  Book -->|none| Done[Charging started]
  Used --> Done
  Override --> Done
```

Field split on the session document:

- `wing`, `pointKey` = charger location (`B1-P1` even if the resident lives in B2)
- `billingWing`, `billingFlatKey`, `flatNumber` = home flat for the bill

## 5. Stop charging

```mermaid
flowchart TD
  Stop[Stop Charging] --> End{endMeter greater than startMeter?}
  End -->|no| Bad[Reject]
  End -->|yes| Calc[units and amount]
  Calc --> Complete[status completed]
  Complete --> Free[chargingSlots occupied false]
  Free --> Meter[lastEndMeter = endMeter]
  Meter --> Done[Slot available]
```

`amount = (endMeter - startMeter) * ratePerUnit` using the rate stored on the session at start.

## 6. Shared flat bill

```mermaid
flowchart LR
  subgraph inputs [Queries]
    Own[ownerUid = me]
    Point[wing + flatNumber]
    Home[billingWing + flatNumber]
    PayOwn[payments ownerUid]
    PayFlat[payments billingFlatKey]
  end
  subgraph math [FlatBillMath]
    Merge[Dedupe by document id]
    Filter[Keep completed sessions and paid/verified payments]
    Sum[units, billed, paid, due max 0]
  end
  Own --> Merge
  Point --> Merge
  Home --> Merge
  PayOwn --> Merge
  PayFlat --> Merge
  Merge --> Filter --> Sum
  Sum --> UI[Dashboard rings and View Bills]
```

Example: Sahil lives in B2-1102 and charges at B1-P1. The session keeps `wing: B1` and `billingWing: B2`. The B2-1102 bill includes that B1 session. A B1-1102 resident does not see it.

## 7. Payment collection

```mermaid
sequenceDiagram
  actor Resident
  actor Admin
  participant Bills as View Bills
  participant FS as payments
  participant Panel as Admin Panel

  Resident->>Bills: Amount + UPI/bank txnRef
  Bills->>FS: create status submitted billingFlatKey
  FS-->>Bills: Pending verification
  Admin->>Panel: See pending request
  alt matches bank statement
    Admin->>FS: status paid
  else
    Admin->>FS: status rejected
  end
  FS-->>Bills: Due recalculated
```

Rules enforced in `FlatPaymentLinker.submitPaymentRequest`:

- Profile must have wing and flat
- One `submitted` request per flat per month
- Same `txnRef` cannot be reused for that flat+month
- Paid/verified reduce due; rejected does not

## 8. Admin report download

```mermaid
flowchart TD
  Tap[Download Excel or PDF] --> Load[Load dues, completed sessions, payments for month]
  Load --> PayQ[payments monthKey orderBy createdAt desc]
  PayQ --> Build{format}
  Build -->|Excel| Xls[Summary, Sessions, Payments sheets]
  Build -->|PDF| Pdf[Landscape tables]
  Xls --> Share[Share sheet]
  Pdf --> Share
```

The payments query uses descending `createdAt` because that composite index already exists. The Excel/PDF still lists payments oldest-first.

Drive upload is a separate button: generate Excel locally, then Google Sign-In and upload under `EV Charging Reports/{yyyy-MM}`.

## 9. Last meter correction

```mermaid
flowchart TD
  Admin[Admin Point meter readings] --> Point[Choose B1-P1 / B1-P2 / B2-P1 / B2-P2]
  Point --> Busy{occupied?}
  Busy -->|yes| Wait[Wait until stop]
  Busy -->|no| Edit[Set or Clear]
  Edit --> Flag[lastMeterSetByAdmin true]
  Flag --> Next[Next start must be greater than the saved reading]
```

## 10. Data movement

```mermaid
erDiagram
  USERS ||--o{ SESSIONS : owns
  USERS ||--o{ PAYMENTS : requests
  SLOTS ||--o{ SESSIONS : hosts
  USERS }o--|| FLAT : lives-on
  SESSIONS }o--|| FLAT : billed-to
  PAYMENTS }o--|| FLAT : tagged-to

  USERS {
    string uid
    string wing
    string flatNumber
    string role
    string status
  }
  FLAT {
    string key "wing|flatNumber"
  }
  SESSIONS {
    string ownerUid
    string wing
    string billingWing
    string pointKey
    number startMeter
    number endMeter
  }
  SLOTS {
    string pointKey
    bool occupied
    number lastEndMeter
  }
  PAYMENTS {
    string ownerUid
    string billingFlatKey
    string status
    number amount
  }
```

`FLAT` is not a Firestore collection. It is the derived key `wing|flatNumber`.

## 11. Rate and version

```mermaid
flowchart LR
  AdminRate[Admin saves rate] --> Rates[appConfig/rates]
  Rates --> Start[Copied onto new session as ratePerUnit]
  AdminVer[Admin publishes version] --> Ver[appConfig/appVersion]
  Ver --> Dash[Dashboard published version]
  Binary[APK/IPA version] --> Dash
```

Changing the rate does not rewrite completed sessions. Those keep the snapshot taken at start.
