"""
Generación del PDF bilingüe (ES/EN) de contrato de trabajo, con datos reales
del empleado y la empresa (nunca datos simulados).
AVISO IMPORTANTE: el texto de las cláusulas es un modelo de referencia
general basado en elementos comunes del Código de Trabajo de Costa Rica
(jornada, aguinaldo, vacaciones). NO reemplaza revisión legal antes de
usarse como contrato oficial — mismo tratamiento que el motor de renta
(ver WORKFORCE_AI_OS_PROYECTO.md sección 5.2, pendiente de validación
legal/contable antes de ser regla de negocio de producción). El aviso
también queda impreso al pie del documento generado.

Logos: el logo de TechSupport (proveedor) se imprime siempre en el
encabezado — es correcto para cualquier tenant, ya que TechSupport es el
mismo proveedor para todos los clientes.
El logo del EMPLEADOR (ej. Burger King) todavía NO es un dato real de
tenant: el mód. 26 "Sistema de temas / white-label por tenant" (que
agregaría un logo_url real por tenant, vive junto a catálogos del mód. 6)
no está construido todavía. Como shortcut EXPLÍCITO solo para este demo, se
muestra el logo de Burger King cuando el nombre del tenant contiene
"burger" — esto es temporal y debe reemplazarse por un campo real de
tenant (mód. 26) antes de soportar otros clientes con logo propio.
"""
import os

from PIL import Image as PILImage
from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.platypus import Image as RLImage
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

STORAGE_DIR = "/app/storage/contracts"
LOGOS_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "assets", "logos")
TECHSUPPORT_LOGO = os.path.join(LOGOS_DIR, "TechSupport_clean.png")
BURGERKING_LOGO = os.path.join(LOGOS_DIR, "bk_logo_clean.png")

CONTRACT_TYPE_LABELS = {
    "indefinido": ("Contrato por Tiempo Indefinido", "Indefinite-Term Employment Contract"),
    "plazo_fijo": ("Contrato a Plazo Fijo", "Fixed-Term Employment Contract"),
    "por_obra": ("Contrato por Obra Determinada", "Contract for a Specific Project"),
}
ID_TYPE_LABELS = {
    "cedula_fisica": "Cédula física",
    "cedula_juridica": "Cédula jurídica",
    "dimex": "DIMEX",
    "pasaporte": "Pasaporte",
}


def _scaled_image(path, target_height):
    img = PILImage.open(path)
    w, h = img.size
    ratio = w / h
    return RLImage(path, width=target_height * ratio, height=target_height)


def _build_header_logos(tenant_name: str):
    left_cell = _scaled_image(TECHSUPPORT_LOGO, 0.45 * inch)
    right_cell = ""
    if os.path.exists(BURGERKING_LOGO) and "burger" in tenant_name.lower():
        right_cell = _scaled_image(BURGERKING_LOGO, 0.55 * inch)
    header = Table([[left_cell, right_cell]], colWidths=[3.5 * inch, 2.5 * inch])
    header.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("ALIGN", (0, 0), (0, 0), "LEFT"),
        ("ALIGN", (1, 0), (1, 0), "RIGHT"),
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 0),
        ("TOPPADDING", (0, 0), (-1, -1), 0),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
    ]))
    return header


def generate_contract_pdf(*, tenant_name: str, employee, contract) -> str:
    os.makedirs(STORAGE_DIR, exist_ok=True)
    filepath = os.path.join(STORAGE_DIR, f"{contract.id}.pdf")
    doc = SimpleDocTemplate(filepath, pagesize=letter, topMargin=0.6 * inch, bottomMargin=0.75 * inch)
    styles = getSampleStyleSheet()
    title_style = ParagraphStyle("TitleBilingual", parent=styles["Title"], fontSize=14)
    normal = styles["Normal"]
    small = ParagraphStyle("Small", parent=styles["Normal"], fontSize=8, textColor=colors.grey)

    type_es, type_en = CONTRACT_TYPE_LABELS[contract.contract_type]

    story = [
        _build_header_logos(tenant_name),
        Spacer(1, 0.3 * inch),
        Paragraph(f"{type_es} / {type_en}", title_style),
        Spacer(1, 0.3 * inch),
        Paragraph(f"<b>Empleador / Employer:</b> {tenant_name}", normal),
        Paragraph(f"<b>Empleado/a / Employee:</b> {employee.first_name} {employee.last_name}", normal),
        Paragraph(
            f"<b>Identificación / ID:</b> {ID_TYPE_LABELS.get(employee.id_type, employee.id_type)} "
            f"{employee.id_number}",
            normal,
        ),
        Paragraph(f"<b>Puesto / Position:</b> {employee.position}", normal),
        Spacer(1, 0.2 * inch),
    ]
    data = [
        ["Fecha de inicio / Start date", contract.start_date.isoformat()],
        ["Fecha de fin / End date", contract.end_date.isoformat() if contract.end_date else "N/A"],
        ["Salario base / Base salary", f"{contract.currency} {float(contract.base_salary):,.2f}"],
        ["Tipo de contrato / Contract type", f"{type_es} / {type_en}"],
    ]
    table = Table(data, colWidths=[2.5 * inch, 3.5 * inch])
    table.setStyle(TableStyle([
        ("GRID", (0, 0), (-1, -1), 0.5, colors.grey),
        ("BACKGROUND", (0, 0), (0, -1), colors.whitesmoke),
        ("FONTSIZE", (0, 0), (-1, -1), 9),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
    ]))
    story.append(table)
    story.append(Spacer(1, 0.3 * inch))
    story.append(Paragraph(
        "Cláusulas generales (referencia, Código de Trabajo de Costa Rica): jornada ordinaria "
        "máxima según ley, derecho a aguinaldo (Ley de Aguinaldo, artículo 1), derecho a "
        "vacaciones anuales pagadas, y demás derechos laborales irrenunciables aplicables.",
        normal,
    ))
    story.append(Spacer(1, 0.1 * inch))
    story.append(Paragraph(
        "General clauses (reference, Costa Rica Labor Code): maximum ordinary working hours per "
        "law, right to a Christmas bonus (aguinaldo, per Ley de Aguinaldo article 1), right to "
        "paid annual vacation, and other applicable non-waivable labor rights.",
        normal,
    ))
    story.append(Spacer(1, 0.5 * inch))
    story.append(Paragraph(
        "_______________________ &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; _______________________",
        normal,
    ))
    story.append(Paragraph(
        "Firma Empleador / Employer signature &nbsp;&nbsp;&nbsp;&nbsp; "
        "Firma Empleado / Employee signature",
        small,
    ))
    story.append(Spacer(1, 0.4 * inch))
    story.append(Paragraph(
        "AVISO: Este documento es un modelo de referencia generado automáticamente. Requiere "
        "revisión legal antes de su uso oficial. / NOTICE: This document is an automatically "
        "generated reference template. Requires legal review before official use.",
        small,
    ))
    doc.build(story)
    return filepath
