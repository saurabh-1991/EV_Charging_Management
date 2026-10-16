# Deployment Runbook

## 1. Firebase Project Setup

- Create Firebase project for the society app.
- Enable Authentication (Email/Password).
- Enable Firestore and Storage.
- Deploy rules from `infra/firebase/firestore.rules`.
- Deploy indexes from `infra/firebase/firestore.indexes.json`.

## 2. Mobile App Setup

- Open `mobile/` in Flutter-supported IDE.
- Run dependency install (`flutter pub get`).
- Configure Firebase app IDs for Android and iOS.
- Build debug APK/IPA for pilot rollout.

## 3. Billing Service Setup

- Create Python 3.11 environment in `services/billing/`.
- Install dependencies from `requirements.txt`.
- Configure service account credentials for Firestore access.
- Schedule monthly run (Cloud Run Job / cron).

### Google Drive Backup Setup

- Create a Google Cloud service account with Drive API enabled.
- Download service account JSON key and store it securely.
- Create or choose a society-owned Google Drive folder.
- Share that folder with the service account email as Editor.
- Set environment variables before monthly billing run:
  - `GDRIVE_SERVICE_ACCOUNT_JSON=/secure/path/service-account.json`
  - `GDRIVE_FOLDER_ID=<drive-folder-id>`
- Billing run uploads generated invoice PDFs to that Drive folder automatically.

## 4. Operational Process

- Admin sets monthly rate per unit.
- New resident registers using email/password.
- Admin approves pending users from app approval queue.
- Residents log sessions and book slots in app.
- Month-end billing service generates invoices.
- Residents pay via UPI/bank transfer and submit transaction reference.
- Admin verifies references and closes dues.

## 5. Future Automation Toggle

- Complete KYC with selected payment gateway.
- Set `paymentSettings.gatewayEnabled=true`.
- Enable gateway webhook endpoint in billing backend.
- Turn on automatic payment status update and reconciliation.
