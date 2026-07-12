#!/bin/bash
# ============================================================
# #98 - Contrato PDF: idioma unico (no bilingue), elegido al crear
# el contrato. Nueva columna Contract.language (default 'es').
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

# ---------- 1. models.py: columna language en Contract ----------
python3 << 'PYEOF'
path = "apps/backend/app/db/models.py"
with open(path, encoding="utf-8") as f:
    src = f.read()

old = '''    pay_frequency: Mapped[str] = mapped_column(String(20), nullable=False, server_default=text("'mensual'"))
    pdf_path: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)'''
new = '''    pay_frequency: Mapped[str] = mapped_column(String(20), nullable=False, server_default=text("'mensual'"))
    # es | en - idioma unico en que se genera el PDF del contrato (#98: se elimino
    # el PDF bilingue, ahora se elige un idioma segun quien crea el contrato)
    language: Mapped[str] = mapped_column(String(2), nullable=False, server_default=text("'es'"))
    pdf_path: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)'''

assert old in src, "ANCHOR NOT FOUND: Contract.pay_frequency/pdf_path"
assert src.count(old) == 1, "ANCHOR NOT UNIQUE: Contract.pay_frequency/pdf_path"
src = src.replace(old, new, 1)
with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("OK: models.py - Contract.language agregado")
PYEOF

# ---------- 2. schemas.py: language en ContractCreate + ContractResponse ----------
python3 << 'PYEOF'
path = "apps/backend/app/modules/employees/schemas.py"
with open(path, encoding="utf-8") as f:
    src = f.read()

edits = []

edits.append(("ContractCreate.language", '''class ContractCreate(BaseModel):
    contract_type: Literal["indefinido", "plazo_fijo", "por_obra"]
    start_date: date
    end_date: Optional[date] = None
    base_salary: float
    currency: Literal["CRC", "USD", "GTQ", "HNL", "NIO", "PAB"] = "CRC"
    pay_frequency: Literal["semanal", "quincenal", "bisemanal", "mensual"] = "mensual"''',
'''class ContractCreate(BaseModel):
    contract_type: Literal["indefinido", "plazo_fijo", "por_obra"]
    start_date: date
    end_date: Optional[date] = None
    base_salary: float
    currency: Literal["CRC", "USD", "GTQ", "HNL", "NIO", "PAB"] = "CRC"
    pay_frequency: Literal["semanal", "quincenal", "bisemanal", "mensual"] = "mensual"
    language: Literal["es", "en"] = "es"'''))

edits.append(("ContractResponse.language", '''class ContractResponse(BaseModel):
    id: UUID
    employee_id: UUID
    contract_type: str
    start_date: date
    end_date: Optional[date] = None
    base_salary: float
    currency: str
    pay_frequency: str
    pdf_path: Optional[str] = None''',
'''class ContractResponse(BaseModel):
    id: UUID
    employee_id: UUID
    contract_type: str
    start_date: date
    end_date: Optional[date] = None
    base_salary: float
    currency: str
    pay_frequency: str
    language: str = "es"
    pdf_path: Optional[str] = None'''))

for label, old, new in edits:
    assert old in src, f"ANCHOR NOT FOUND ({label})"
    assert src.count(old) == 1, f"ANCHOR NOT UNIQUE ({label})"
    src = src.replace(old, new, 1)
    print(f"OK edicion aplicada: {label}")

with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("OK: schemas.py escrito")
PYEOF

# ---------- 3. router.py: pasar/leer language en los 3 puntos que aplican ----------
python3 << 'PYEOF'
path = "apps/backend/app/modules/employees/router.py"
with open(path, encoding="utf-8") as f:
    src = f.read()

edits = []

edits.append(("_contract_response con language", '''def _contract_response(c: Contract) -> ContractResponse:
    return ContractResponse(
        id=c.id, employee_id=c.employee_id, contract_type=c.contract_type,
        start_date=c.start_date, end_date=c.end_date, base_salary=float(c.base_salary),
        currency=c.currency, pay_frequency=c.pay_frequency, pdf_path=c.pdf_path,
    )''',
'''def _contract_response(c: Contract) -> ContractResponse:
    return ContractResponse(
        id=c.id, employee_id=c.employee_id, contract_type=c.contract_type,
        start_date=c.start_date, end_date=c.end_date, base_salary=float(c.base_salary),
        currency=c.currency, pay_frequency=c.pay_frequency, language=c.language, pdf_path=c.pdf_path,
    )'''))

edits.append(("Contract() con language", '''        contract = Contract(
            id=uuid4(),
            tenant_id=current_user.tenant_id,
            employee_id=employee_id,
            contract_type=payload.contract_type,
            start_date=payload.start_date,
            end_date=payload.end_date,
            base_salary=payload.base_salary,
            currency=payload.currency,
            pay_frequency=payload.pay_frequency,
            pdf_path=None,
        )''',
'''        contract = Contract(
            id=uuid4(),
            tenant_id=current_user.tenant_id,
            employee_id=employee_id,
            contract_type=payload.contract_type,
            start_date=payload.start_date,
            end_date=payload.end_date,
            base_salary=payload.base_salary,
            currency=payload.currency,
            pay_frequency=payload.pay_frequency,
            language=payload.language,
            pdf_path=None,
        )'''))

edits.append(("generate_contract_pdf con language", '''        pdf_path = generate_contract_pdf(tenant_name=tenant.name, employee=employee, contract=contract)''',
'''        pdf_path = generate_contract_pdf(
            tenant_name=tenant.name, employee=employee, contract=contract, language=payload.language
        )'''))

for label, old, new in edits:
    assert old in src, f"ANCHOR NOT FOUND ({label})"
    assert src.count(old) == 1, f"ANCHOR NOT UNIQUE ({label})"
    src = src.replace(old, new, 1)
    print(f"OK edicion aplicada: {label}")

with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("OK: router.py escrito")
PYEOF

# ---------- 4. contracts_pdf.py: reescritura completa (idioma unico) ----------
cat > apps/backend/app/core/contracts_pdf.py << 'PDFEOF'
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
PDFEOF
echo "OK: contracts_pdf.py reescrito (idioma unico)"

echo "=== verificacion de sintaxis backend ==="
python3 -m py_compile apps/backend/app/db/models.py && echo "models.py SYNTAX OK"
python3 -m py_compile apps/backend/app/modules/employees/schemas.py && echo "schemas.py SYNTAX OK"
python3 -m py_compile apps/backend/app/modules/employees/router.py && echo "router.py SYNTAX OK"
python3 -m py_compile apps/backend/app/core/contracts_pdf.py && echo "contracts_pdf.py SYNTAX OK"

# ---------- 5. ALTER TABLE ----------
set -a
source .env 2>/dev/null || true
set +a
PGUSER="${POSTGRES_USER:-postgres}"
PGDB="${POSTGRES_DB:-workforce_ai_os}"
docker compose exec -T postgres psql -U "$PGUSER" -d "$PGDB" -c \
  "ALTER TABLE contracts ADD COLUMN IF NOT EXISTS language VARCHAR(2) NOT NULL DEFAULT 'es';"
docker compose exec -T postgres psql -U "$PGUSER" -d "$PGDB" -c \
  "SELECT column_name, data_type, column_default FROM information_schema.columns WHERE table_name = 'contracts' AND column_name = 'language';"

# ---------- 6. frontend: dropdown de idioma en Nuevo contrato ----------
python3 << 'PYEOF'
path = "apps/frontend/app/[locale]/dashboard/empleados/page.js"
with open(path, encoding="utf-8") as f:
    src = f.read()

edits = []

edits.append(("CONTRACT_LANGUAGES const", '''const BANK_ACCOUNT_TYPES = ["Cuenta de Ahorro", "Cuenta Corriente"];''',
'''const BANK_ACCOUNT_TYPES = ["Cuenta de Ahorro", "Cuenta Corriente"];
const CONTRACT_LANGUAGES = ["es", "en"];'''))

edits.append(("language en emptyContractForm", '''const emptyContractForm = {
  contract_type: "indefinido",
  start_date: "",
  end_date: "",
  base_salary: "",
  currency: "CRC",
  pay_frequency: "mensual",
};''',
'''const emptyContractForm = {
  contract_type: "indefinido",
  start_date: "",
  end_date: "",
  base_salary: "",
  currency: "CRC",
  pay_frequency: "mensual",
  language: "es",
};'''))

edits.append(("language en payload de contrato", '''      const payload = {
        contract_type: contractForm.contract_type,
        start_date: contractForm.start_date,
        end_date: contractForm.end_date || null,
        base_salary: parseFloat(contractForm.base_salary),
        currency: contractForm.currency,
        pay_frequency: contractForm.pay_frequency,
      };''',
'''      const payload = {
        contract_type: contractForm.contract_type,
        start_date: contractForm.start_date,
        end_date: contractForm.end_date || null,
        base_salary: parseFloat(contractForm.base_salary),
        currency: contractForm.currency,
        pay_frequency: contractForm.pay_frequency,
        language: contractForm.language,
      };'''))

edits.append(("dropdown idioma en form", '''                      <p className="text-[11px] text-bk-brown/50 mt-1">{t("pay_frequency_hint")}</p>
                    </div>
                    <button
                      type="submit"
                      disabled={creatingContract}''',
'''                      <p className="text-[11px] text-bk-brown/50 mt-1">{t("pay_frequency_hint")}</p>
                    </div>
                    <div>
                      <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("contract_language")}</label>
                      <select
                        value={contractForm.language}
                        onChange={(e) => setContractForm({ ...contractForm, language: e.target.value })}
                        className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                      >
                        {CONTRACT_LANGUAGES.map((l) => (
                          <option key={l} value={l}>
                            {t("contract_language_" + l)}
                          </option>
                        ))}
                      </select>
                      <p className="text-[11px] text-bk-brown/50 mt-1">{t("contract_language_hint")}</p>
                    </div>
                    <button
                      type="submit"
                      disabled={creatingContract}'''))

for label, old, new in edits:
    assert old in src, f"ANCHOR NOT FOUND ({label})"
    assert src.count(old) == 1, f"ANCHOR NOT UNIQUE ({label})"
    src = src.replace(old, new, 1)
    print(f"OK edicion aplicada: {label}")

with open(path, "w", encoding="utf-8") as f:
    f.write(src)

with open(path, encoding="utf-8") as f:
    check = f.read()
problemas = []
if check.count("{") != check.count("}"):
    problemas.append(f"llaves desbalanceadas: {{ {check.count('{')} vs }} {check.count('}')}")
if check.count("(") != check.count(")"):
    problemas.append(f"parentesis desbalanceados: ( {check.count('(')} vs ) {check.count(')')}")
for marker in ["CONTRACT_LANGUAGES", "contract_language"]:
    if marker not in check:
        problemas.append(f"falta: {marker}")
if problemas:
    print("XXX VERIFICACION FALLO XXX")
    for p in problemas:
        print(" -", p)
    raise SystemExit(1)
print("OK: empleados/page.js verificado correctamente")
PYEOF

# ---------- 7. i18n: employees.contract_language* ----------
python3 << 'PYEOF'
import json

nuevas_es = {
    "contract_language": "Idioma del contrato",
    "contract_language_es": "Español",
    "contract_language_en": "Inglés",
    "contract_language_hint": "El PDF se genera en un solo idioma.",
}
nuevas_en = {
    "contract_language": "Contract language",
    "contract_language_es": "Spanish",
    "contract_language_en": "English",
    "contract_language_hint": "The PDF is generated in a single language.",
}

for path, nuevas in [
    ("apps/frontend/messages/es.json", nuevas_es),
    ("apps/frontend/messages/en.json", nuevas_en),
]:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    data.setdefault("employees", {})
    added = 0
    for k, v in nuevas.items():
        if k not in data["employees"]:
            data["employees"][k] = v
            added += 1
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"OK: {path} - employees +{added}")
PYEOF

# ---------- 8. rebuild api + frontend ----------
echo "=== rebuild api ==="
docker compose build --no-cache api
docker compose up -d api
sleep 5
docker compose logs api --tail 30

echo "=== rebuild frontend ==="
docker compose build --no-cache frontend
docker compose up -d frontend
sleep 5
docker compose logs frontend --tail 30

echo "=== FIN contrato PDF idioma unico ==="
