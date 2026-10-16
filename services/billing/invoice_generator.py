from dataclasses import dataclass
from datetime import date
from pathlib import Path

from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas


@dataclass
class InvoiceData:
    bill_id: str
    resident_name: str
    flat_number: str
    billing_month: str
    total_units: float
    rate_per_unit: float
    total_amount: float
    due_date: date


def generate_invoice_pdf(invoice: InvoiceData, output_dir: Path) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / f"invoice_{invoice.bill_id}.pdf"

    pdf = canvas.Canvas(str(output_path), pagesize=A4)
    width, height = A4

    pdf.setTitle(f"EV Charging Invoice {invoice.bill_id}")
    pdf.setFont("Helvetica-Bold", 16)
    pdf.drawString(50, height - 60, "Society EV Charging Invoice")

    pdf.setFont("Helvetica", 11)
    lines = [
        f"Invoice ID: {invoice.bill_id}",
        f"Resident: {invoice.resident_name}",
        f"Flat Number: {invoice.flat_number}",
        f"Billing Month: {invoice.billing_month}",
        f"Units Consumed: {invoice.total_units:.2f} kWh",
        f"Rate per Unit: INR {invoice.rate_per_unit:.2f}",
        f"Total Amount: INR {invoice.total_amount:.2f}",
        f"Due Date: {invoice.due_date.isoformat()}",
    ]

    y = height - 100
    for line in lines:
        pdf.drawString(50, y, line)
        y -= 18

    pdf.drawString(
        50,
        y - 10,
        "Payment: UPI/Bank transfer to society account and submit transaction reference.",
    )

    pdf.save()
    return output_path
