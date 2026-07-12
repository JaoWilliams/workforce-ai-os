#!/bin/bash
# ============================================================
# Fase 9 (Asientos contables) - Parte 1: modelos
# ============================================================
# CAMBIOS en apps/backend/app/db/models.py:
#   - ChartOfAccount (chart_of_accounts): catalogo de cuentas contables,
#     tenant_id+code unico. No existia plan de cuentas cargado, se crea
#     desde cero (catalogos.manage/.view, mismo patron que los demas).
#   - JournalEntry (journal_entries): cabecera de asiento. entry_type
#     distingue: planilla | aguinaldo_provision | aguinaldo_pago |
#     vacaciones_provision | cesantia | ccss_patronal. Referencia
#     opcional a PayrollPeriod o Termination segun el tipo.
#   - JournalEntryLine (journal_entry_lines): lineas debe/haber de cada
#     asiento, con cuenta contable y sucursal opcional (para reporte por
#     centro de costo).
#   - PayrollConcept: + accounting_account_id (FK opcional a
#     ChartOfAccount) - cada concepto (RENTA, CCSS-EMPLEADO, etc.) se
#     puede mapear a su cuenta de pasivo/gasto individualmente. Antes
#     no existia este vinculo (la cuenta contable solo vivia en Branch).
#
# Decisiones de alcance confirmadas con el cliente:
#   - Cesantia: SOLO se genera asiento al aprobar una Termination con
#     responsabilidad patronal - NO hay provision mensual especulativa
#     (provisionar mensualmente requeriria asumir una tasa de rotacion
#     que no existe como dato real).
#   - Aguinaldo: provision mensual (8.33%, ya existente) + reconciliacion
#     en el pago real de diciembre, que CANCELA el pasivo acumulado
#     (decision confirmada) - la diferencia si la hay se ajusta como
#     gasto/ingreso del periodo.
#   - Vacaciones: provision mensual = delta de dias acumulados en el
#     periodo x tarifa Art.157 vigente del empleado.
#   - CCSS patronal: reutiliza PayrollConcept.employer_value (ya existe
#     desde #149) - se sembrara un concepto CCSS-PATRONAL con tasa de
#     PRUEBA flageada (mismo tratamiento que CCSS-EMPLEADO al 10.67%),
#     pendiente de validacion de tu contador.
#   - Exportacion: CSV generico (no se confirmo sistema contable
#     especifico) - una fila por linea de asiento.
#
# Ejecutar: cd /opt/workforce-ai-os && bash fase9_parte1_modelos.sh
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

python3 << 'PYEOF'
path = "apps/backend/app/db/models.py"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

anchor = "class Device(Base):"
assert anchor in src, "ANCHOR NOT FOUND: class Device(Base):"
assert src.count(anchor) == 1, "ANCHOR NOT UNIQUE: class Device(Base):"

new_models = '''class ChartOfAccount(Base):
    """Plan de cuentas contables del tenant. No existia previamente -
    se crea en fase 9 (asientos) porque ninguna fase anterior necesitaba
    modelar cuentas individuales (Branch.accounting_account cubria el
    caso de centro de costo, pero no cuenta contable por concepto)."""
    __tablename__ = "chart_of_accounts"
    __table_args__ = (UniqueConstraint("tenant_id", "code", name="uq_chart_of_account_tenant_code"),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    code: Mapped[str] = mapped_column(String(20), nullable=False)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    # activo | pasivo | patrimonio | ingreso | gasto
    account_type: Mapped[str] = mapped_column(String(20), nullable=False)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))


class JournalEntry(Base):
    """Cabecera de un asiento contable. entry_type distingue el origen:
    planilla (nomina ordinaria bruto/neto), aguinaldo_provision (8.33%
    mensual), aguinaldo_pago (pago real de diciembre, cancela el pasivo
    acumulado por las provisiones), vacaciones_provision (delta de dias
    acumulados x tarifa Art.157), cesantia (solo al aprobar una
    Termination con responsabilidad patronal - sin provision mensual
    especulativa, decision confirmada con el cliente), ccss_patronal
    (aporte patronal mensual, tasa de prueba flageada pendiente de
    contador)."""
    __tablename__ = "journal_entries"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    entry_date: Mapped[Date] = mapped_column(Date, nullable=False)
    entry_type: Mapped[str] = mapped_column(String(30), nullable=False)
    payroll_period_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey("payroll_periods.id"), nullable=True)
    termination_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey("terminations.id"), nullable=True)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    created_by: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))


class JournalEntryLine(Base):
    """Linea debe/haber de un asiento. branch_id opcional permite
    reportar por centro de costo (sucursal) ademas de por cuenta."""
    __tablename__ = "journal_entry_lines"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    journal_entry_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("journal_entries.id"), nullable=False)
    account_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("chart_of_accounts.id"), nullable=False)
    branch_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey("branches.id"), nullable=True)
    debit: Mapped[float] = mapped_column(Numeric(14, 2), nullable=False, default=0)
    credit: Mapped[float] = mapped_column(Numeric(14, 2), nullable=False, default=0)
    description: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))


'''

src = src.replace(anchor, new_models + anchor, 1)

# --- PayrollConcept: agregar accounting_account_id (FK opcional a ChartOfAccount) ---
anchor_concept = "class PayrollConcept(Base):"
assert anchor_concept in src, "ANCHOR NOT FOUND: class PayrollConcept(Base):"

# Insertamos el nuevo campo justo despues de la linea 'employer_value' si existe,
# si no, despues de la primera linea de columnas tras el __tablename__.
marker_employer_value = None
idx_concept = src.index(anchor_concept)
concept_block_end = src.index("\n\n\n", idx_concept)
concept_block = src[idx_concept:concept_block_end]

if "accounting_account_id" not in concept_block:
    # anchor de insercion: la ultima linea 'mapped_column' del bloque de PayrollConcept
    lines = concept_block.split("\n")
    last_column_idx = max(i for i, l in enumerate(lines) if "mapped_column" in l)
    new_field = '    accounting_account_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey("chart_of_accounts.id"), nullable=True)'
    lines.insert(last_column_idx + 1, new_field)
    new_concept_block = "\n".join(lines)
    src = src[:idx_concept] + new_concept_block + src[concept_block_end:]
    print("OK: accounting_account_id agregado a PayrollConcept")
else:
    print("SKIP: PayrollConcept ya tenia accounting_account_id")

with open(path, "w", encoding="utf-8") as f:
    f.write(src)

print("OK models.py: ChartOfAccount + JournalEntry + JournalEntryLine agregados")
PYEOF

echo "=== verificando sintaxis (host python3, sin docker) ==="
python3 -m py_compile apps/backend/app/db/models.py && echo "SYNTAX OK: models.py"

echo "=== bloque PayrollConcept resultante (revisar el campo nuevo) ==="
grep -n "class PayrollConcept" -A 25 apps/backend/app/db/models.py | head -30
