# Product requirements

## Objective

Replace Gloria Grand’s paper EV meter log with a mobile app for residents and society admins.

## Personas

- **Resident**: charges at a wing point, sees the flat bill, submits a UPI/bank reference.
- **Admin**: manages users, rate, published app version, pending payments, Excel/PDF reports, Drive backup, and last-meter corrections.

## In production (1.5.5)

- Email/password login. New accounts are active immediately.
- Admin can disable an account; disabled users cannot use the app.
- Vehicle list per login; guest vehicle bills the logged-in flat.
- Start/stop charging with start/end meter, units, and amount.
- Residents only see their wing’s points. Admins see all four.
- Immediate occupancy: starting on a point takes it even if someone else had booked the hour.
- Shared dues and consumption for every email on the same wing + flat.
- A B2 resident charging at a B1 point still bills B2.
- Monthly bill PDF for the flat.
- Admin Excel and PDF of all users for a month.
- Optional Google Drive upload of the Excel report.
- Last end meter stored per point; next start must be higher. Admin can set or clear it.
- Dashboard rings for total dues and total consumption, plus installed vs published app version.

## Out of scope

- Direct hardware meter integration
- Payment gateway / UPI collect in-app
- Card or netbanking
- Automatic monthly Python invoice job (bills are generated in the app)

## Constraints

- Default rate INR 15/kWh, admin-only change.
- B1-805 and B2-805 stay separate.
- Blank wing/flat is not merged into a shared bill.
- Overpay floors due at 0 and does not spill to other months or flats.
