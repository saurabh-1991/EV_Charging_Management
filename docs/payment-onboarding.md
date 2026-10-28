# Payment Onboarding

Residents submit the UPI/bank reference from **View Bills**. Admins verify it on **Admin Panel**. There is no in-app payment gateway.

## Launch Mode (No Gateway)

1. Society provides:
   - UPI ID
   - UPI QR image
   - Bank account details
2. Admin enters these in app settings.
3. Residents pay externally via UPI app or bank transfer.
4. Resident submits transaction reference in app.
5. Admin verifies against bank statement and marks payment paid.

## Required Admin Controls

- View pending payment references
- Approve/reject references
- Add remarks for rejected references
- Track verified-by and verification timestamp

## Audit Requirements

- Store immutable transaction reference log.
- Prevent deleting successful payment entries.
- Record who updated payment status and when.
