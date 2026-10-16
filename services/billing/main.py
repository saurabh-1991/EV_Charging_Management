from __future__ import annotations

from dataclasses import dataclass
from datetime import date
import os
from pathlib import Path
from typing import Iterable

from drive_backup import DriveBackupClient
from invoice_generator import InvoiceData, generate_invoice_pdf


@dataclass
class SessionRecord:
    user_id: str
    resident_name: str
    flat_number: str
    units: float


@dataclass
class BillRecord:
    bill_id: str
    user_id: str
    resident_name: str
    flat_number: str
    billing_month: str
    total_units: float
    rate_per_unit: float
    total_amount: float
    due_date: date


def compute_monthly_bills(
    sessions: Iterable[SessionRecord],
    billing_month: str,
    rate_per_unit: float,
) -> list[BillRecord]:
    aggregated: dict[str, BillRecord] = {}

    for session in sessions:
        if session.user_id not in aggregated:
            aggregated[session.user_id] = BillRecord(
                bill_id=f"{billing_month}-{session.user_id}",
                user_id=session.user_id,
                resident_name=session.resident_name,
                flat_number=session.flat_number,
                billing_month=billing_month,
                total_units=0.0,
                rate_per_unit=rate_per_unit,
                total_amount=0.0,
                due_date=date.today().replace(day=28),
            )

        bill = aggregated[session.user_id]
        bill.total_units += session.units
        bill.total_amount = bill.total_units * bill.rate_per_unit

    return list(aggregated.values())


def generate_invoices(bills: Iterable[BillRecord], output_dir: Path) -> list[Path]:
    output_files: list[Path] = []

    for bill in bills:
        invoice_data = InvoiceData(
            bill_id=bill.bill_id,
            resident_name=bill.resident_name,
            flat_number=bill.flat_number,
            billing_month=bill.billing_month,
            total_units=bill.total_units,
            rate_per_unit=bill.rate_per_unit,
            total_amount=bill.total_amount,
            due_date=bill.due_date,
        )
        output_files.append(generate_invoice_pdf(invoice_data, output_dir))

    return output_files


def backup_invoices_to_drive(invoice_files: Iterable[Path]) -> None:
    service_account_path = os.getenv("GDRIVE_SERVICE_ACCOUNT_JSON")
    folder_id = os.getenv("GDRIVE_FOLDER_ID")

    if not service_account_path or not folder_id:
        print(
            "Skipping Google Drive backup. Set GDRIVE_SERVICE_ACCOUNT_JSON and "
            "GDRIVE_FOLDER_ID to enable uploads."
        )
        return

    client = DriveBackupClient(
        service_account_path=service_account_path,
        folder_id=folder_id,
    )
    uploaded_ids = client.upload_files(invoice_files)
    print(f"Uploaded {len(uploaded_ids)} invoices to Google Drive.")


if __name__ == "__main__":
    sample_sessions = [
        SessionRecord("user_1", "Resident A", "A-101", 24.5),
        SessionRecord("user_1", "Resident A", "A-101", 18.2),
        SessionRecord("user_2", "Resident B", "B-302", 41.0),
    ]

    month = "2026-09"
    bills = compute_monthly_bills(sample_sessions, month, rate_per_unit=12.0)
    generated_files = generate_invoices(bills, Path("./output"))
    backup_invoices_to_drive(generated_files)

    for generated in generated_files:
        print(f"Generated invoice: {generated}")
