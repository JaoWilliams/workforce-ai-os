"""
Generacion del PDF de contrato de trabajo en UN SOLO IDIOMA (ES o EN,
elegido al crear el contrato - ver Contract.language), con datos reales
del empleado y la empresa (nunca datos simulados). Antes era bilingue;
se cambio a idioma unico (#98) porque el documento debe leerse como un
contrato normal, no como una plantilla con doble texto.

AVISO IMPORTANTE: el texto de las clausulas es un modelo de referencia
general basado en elementos comunes del Codigo de Trabajo de Costa Rica
(jornada, aguinaldo, vacaciones). NO reemplaza revision legal antes de
usarse como contrato oficial - mismo tratamiento que el motor de renta
(ver WORKFORCE_AI_OS_PROYECTO.md seccion 5.2, pendiente de validacion
legal/contable antes de ser regla de negocio de produccion). El aviso
tambien queda impreso al pie del documento generado.

Logos: el logo de TechSupport (proveedor) se imprime siempre en el
encabezado - es correcto para cualquier tenant, ya que TechSupport es el
mismo proveedor para todos los clientes.
El logo del EMPLEADOR (ej. Burger King) todavia NO es un dato real de
tenant: el mod. 26 "Sistema de temas / white-label por tenant" (que
agregaria un logo_url real por tenant, vive junto a catalogos del mod. 6)
no esta construido todavia. Como shortcut EXPLICITO solo para este demo, se
muestra el logo de Burger King cuando el nombre del tenant contiene
"burger" - esto es temporal y debe reemplazarse por un campo real de
tenant (mod. 26) antes de soportar otros clientes con logo propio.
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
    "es": {
        "indefinido": "Contrato por Tiempo Indefinido",
        "plazo_fijo": "Contrato a Plazo Fijo",
        "por_obra": "Contrato por Obra Determinada",
    },
    "en": {
        "indefinido": "Indefinite-Term Employment Contract",
        "plazo_fijo": "Fixed-Term Employment Contract",
        "por_obra": "Contract for a Specific Project",
    },
}

ID_TYPE_LABELS = {
    "es": {
        "cedula_fisica": "Cedula fisica",
        "cedula_juridica": "Cedula juridica",
        "dimex": "DIMEX",
        "pasaporte": "Pasaporte",
    },
    "en": {
        "cedula_fisica": "National ID",
        "cedula_juridica": "Corporate ID",
        "dimex": "DIMEX",
        "pasaporte": "Passport",
    },
}

LABELS = {
    "es": {
        "employer": "Empleador",
        "employee": "Empleado/a",
        "id": "Identificacion",
        "position": "Puesto",
        "start_date": "Fecha de inicio",
        "end_date": "Fecha de fin",
        "base_salary": "Salario base",
        "contract_type": "Tipo de contrato",
        "na": "N/A",
        "clauses": (
            "Clausulas generales (referencia, Codigo de Trabajo de Costa Rica): jornada ordinaria "
            "maxima segun ley, derecho a aguinaldo (Ley de Aguinaldo, articulo 1), derecho a "
            "vacaciones anuales pagadas, y demas derechos laborales irrenunciables aplicables."
        ),
        "signature_employer": "Firma Empleador",
        "signature_employee": "Firma Empleado",
        "notice": (
            "AVISO: Este documento es un modelo de referencia generado automaticamente. Requiere "
            "revision legal antes de su uso oficial."
        ),
    },
    "en": {
        "employer": "Employer",
        "employee": "Employee",
        "id": "ID",
        "position": "Position",
        "start_date": "Start date",
        "end_date": "End date",
        "base_salary": "Base salary",
        "contract_type": "Contract type",
        "na": "N/A",
        "clauses": (
            "General clauses (reference, Costa Rica Labor Code): maximum ordinary working hours per "
            "law, right to a Christmas bonus (aguinaldo, per Ley de Aguinaldo article 1), right to "
            "paid annual vacation, and other applicable non-waivable labor rights."
        ),
        "signature_employer": "Employer signature",
        "signature_employee": "Employee signature",
        "notice": (
            "NOTICE: This document is an automatically generated reference template. Requires "
            "legal review before official use."
        ),
    },
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


def generate_contract_pdf(*, tenant_name: str, employee, contract, language: str = "es") -> str:
    lang = language if language in LABELS else "es"
    L = LABELS[lang]
    os.makedirs(STORAGE_DIR, exist_ok=True)
    filepath = os.path.join(STORAGE_DIR, f"{contract.id}.pdf")
    doc = SimpleDocTemplate(filepath, pagesize=letter, topMargin=0.6 * inch, bottomMargin=0.75 * inch)
    styles = getSampleStyleSheet()
    title_style = ParagraphStyle("Title", parent=styles["Title"], fontSize=14)
    normal = styles["Normal"]
    small = ParagraphStyle("Small", parent=styles["Normal"], fontSize=8, textColor=colors.grey)

    contract_type_label = CONTRACT_TYPE_LABELS[lang][contract.contract_type]
    id_type_label = ID_TYPE_LABELS[lang].get(employee.id_type, employee.id_type)

    story = [
        _build_header_logos(tenant_name),
        Spacer(1, 0.3 * inch),
        Paragraph(contract_type_label, title_style),
        Spacer(1, 0.3 * inch),
        Paragraph(f"<b>{L['employer']}:</b> {tenant_name}", normal),
        Paragraph(f"<b>{L['employee']}:</b> {employee.first_name} {employee.last_name}", normal),
        Paragraph(f"<b>{L['id']}:</b> {id_type_label} {employee.id_number}", normal),
        Paragraph(f"<b>{L['position']}:</b> {employee.position}", normal),
        Spacer(1, 0.2 * inch),
    ]
    data = [
        [L["start_date"], contract.start_date.isoformat()],
        [L["end_date"], contract.end_date.isoformat() if contract.end_date else L["na"]],
        [L["base_salary"], f"{contract.currency} {float(contract.base_salary):,.2f}"],
        [L["contract_type"], contract_type_label],
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
    story.append(Paragraph(L["clauses"], normal))
    story.append(Spacer(1, 0.5 * inch))
    story.append(Paragraph(
        "_______________________ &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; _______________________",
        normal,
    ))
    story.append(Paragraph(
        f"{L['signature_employer']} &nbsp;&nbsp;&nbsp;&nbsp; {L['signature_employee']}",
        small,
    ))
    story.append(Spacer(1, 0.4 * inch))
    story.append(Paragraph(L["notice"], small))
    doc.build(story)
    return filepath
