from __future__ import annotations

from pathlib import Path
from typing import Iterable

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload


class DriveBackupClient:
    """Uploads billing artifacts to a society-owned Google Drive folder."""

    _SCOPES = ("https://www.googleapis.com/auth/drive.file",)

    def __init__(self, service_account_path: str, folder_id: str) -> None:
        self._folder_id = folder_id
        credentials = service_account.Credentials.from_service_account_file(
            service_account_path,
            scopes=self._SCOPES,
        )
        self._service = build("drive", "v3", credentials=credentials)

    def upload_file(self, file_path: Path, remote_name: str | None = None) -> str:
        metadata = {
            "name": remote_name or file_path.name,
            "parents": [self._folder_id],
        }
        media = MediaFileUpload(str(file_path), resumable=True)
        created = (
            self._service.files()
            .create(body=metadata, media_body=media, fields="id,name")
            .execute()
        )
        return str(created["id"])

    def upload_files(self, files: Iterable[Path]) -> list[str]:
        return [self.upload_file(file_path) for file_path in files]
