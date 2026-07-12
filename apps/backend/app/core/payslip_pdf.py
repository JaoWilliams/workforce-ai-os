"""
Generacion de la Boleta de Pago (payslip) individual por empleado y
periodo ya calculado. Usa el snapshot congelado en PayrollSnapshotLine
(fase 11) - nunca recalcula en vivo, para que la boleta coincida
exactamente con lo que se aprobo/pago, aunque un catalogo (TaxBracket,
CCSS, etc.) cambie despues.

Reutiliza el mismo encabezado con logos que el contrato de trabajo
(TechSupport siempre, Burger King condicionado al nombre del tenant -
ver aviso en contracts_pdf.py sobre el shortcut temporal de logo por
nombre, pendiente del modulo de white-label real, mod. 26).

PENDIENTE DOCUMENTADO (no construir todavia): el envio de esta boleta
por correo al empleado es un requerimiento futuro, confirmado
explicitamente por el cliente como fuera de alcance de esta entrega -
solo se genera para descarga manual desde Calendario de Nominas.
"""
import os

from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

from app.core.contracts_pdf import _build_header_logos

STORAGE_DIR = "/app/storage/payslips"

LABELS = {
    "es": {
        "title": "Boleta de Pago",
        "employer": "Empleador",
        "employee": "Empleado/a",
        "position": "Puesto",
        "period": "Periodo",
        "pay_date": "Fecha de pago",
        "pay_date_pending": "Pendiente de confirmar",
        "gross_pay": "Salario bruto",
        "ccss_deduction": "Deduccion CCSS",
        "renta_deduction": "Impuesto de renta",
        "renta_refund": "Devolucion de renta",
        "net_pay": "Salario neto a pagar",
        "notice": (
            "Este documento es un comprobante de pago generado a partir del calculo congelado "
            "de la planilla. Ante cualquier diferencia, contactar a Recursos Humanos."
        ),
    },
    "en": {
        "title": "Pay Slip",
        "employer": "Employer",
        "employee": "Employee",
        "position": "Position",
        "period": "Period",
        "pay_date": "Pay date",
        "pay_date_pending": "Pending confirmation",
        "gross_pay": "Gross pay",
        "ccss_deduction": "CCSS deduction",
        "renta_deduction": "Income tax",
        "renta_refund": "Income tax refund",
        "net_pay": "Net pay",
        "notice": (
            "This document is a payment receipt generated from the frozen payroll calculation. "
            "For any discrepancy, contact Human Resources."
        ),
    },
}


def generate_payslip_pdf(*, tenant_name: str, employee, period, line, language: str = "es") -> str:
    lang = language if language in LABELS else "es"
    L = LABELS[lang]
    os.makedirs(STORAGE_DIR, exist_ok=True)
    filepath = os.path.join(STORAGE_DIR, f"{period.id}_{employee.id}.pdf")
    doc = SimpleDocTemplate(filepath, pagesize=letter, topMargin=0.6 * inch, bottomMargin=0.75 * inch)
    styles = getSampleStyleSheet()
    title_style = ParagraphStyle("Title", parent=styles["Title"], fontSize=14)
    normal = styles["Normal"]
    small = ParagraphStyle("Small", parent=styles["Normal"], fontSize=8, textColor=colors.grey)

    pay_date_text = period.pay_date.isoformat() if period.pay_date else L["pay_date_pending"]
    renta_label = L["renta_refund"] if line.renta_is_refund else L["renta_deduction"]
    renta_amount = float(line.renta_amount) if line.renta_amount is not None else 0.0

    story = [
        _build_header_logos(tenant_name),
        Spacer(1, 0.3 * inch),
        Paragraph(L["title"], title_style),
        Spacer(1, 0.2 * inch),
        Paragraph(f"<b>{L['employer']}:</b> {tenant_name}", normal),
        Paragraph(f"<b>{L['employee']}:</b> {employee.first_name} {employee.last_name}", normal),
        Paragraph(f"<b>{L['position']}:</b> {employee.position}", normal),
        Paragraph(
            f"<b>{L['period']}:</b> {period.period_start.isoformat()} - {period.period_end.isoformat()}",
            normal,
        ),
        Paragraph(f"<b>{L['pay_date']}:</b> {pay_date_text}", normal),
        Spacer(1, 0.25 * inch),
    ]

    data = [
        [L["gross_pay"], f"{float(line.gross_pay):,.2f}" if line.gross_pay is not None else "-"],
        [L["ccss_deduction"], f"-{float(line.ccss_deduction):,.2f}" if line.ccss_deduction is not None else "-"],
        [renta_label, f"{'+' if line.renta_is_refund else '-'}{renta_amount:,.2f}"],
        [L["net_pay"], f"{float(line.net_pay):,.2f}" if line.net_pay is not None else "-"],
    ]
    table = Table(data, colWidths=[3 * inch, 3 * inch])
    table.setStyle(TableStyle([
        ("GRID", (0, 0), (-1, -1), 0.5, colors.grey),
        ("BACKGROUND", (0, 0), (0, -1), colors.whitesmoke),
        ("FONTSIZE", (0, 0), (-1, -1), 9),
        ("FONTNAME", (0, -1), (-1, -1), "Helvetica-Bold"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
    ]))
    story.append(table)
    story.append(Spacer(1, 0.4 * inch))
    story.append(Paragraph(L["notice"], small))
    doc.build(story)
    return filepath
