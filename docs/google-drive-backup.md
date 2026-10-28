# Google Drive Backup Guide

## Live path (1.5.5 app)

Admin Panel → **Upload Report to Google Drive**. The Flutter app signs in with Google (`drive.file` scope) and uploads the Excel all-users report to `EV Charging Reports/{yyyy-MM}`. No service account is required for this path.

## Optional Python path

`services/billing/` can still upload generated invoice PDFs if you run it by hand. That is not what residents or admins use in the app.

## Goal
Upload files into a society-owned Google Drive folder.

## One-Time Setup

1. Open Google Cloud Console for your Firebase project.
2. Enable **Google Drive API**.
3. Create a **Service Account** and download JSON credentials.
4. Create a dedicated Drive folder for invoice backups.
5. Share this Drive folder with the service account email as **Editor**.

## Runtime Configuration

Set these environment variables before running billing:

```bash
export GDRIVE_SERVICE_ACCOUNT_JSON="/absolute/path/service-account.json"
export GDRIVE_FOLDER_ID="your_drive_folder_id"
```

## Execute Billing + Backup

```bash
cd services/billing
python3 main.py
```

If credentials are present, invoice PDFs in `output/` are uploaded to Drive.
If variables are missing, billing still runs but Drive upload is skipped.
