#!/bin/bash
# ============================================================
# Fase 10 (Archivo bancario) - Parte 2: modelos
# ============================================================
# Agrega:
#  - Employee.bank_account_type / bank_account_number (nullable, se
#    completan despues via PATCH, no obligatorios al crear empleado).
#  - BankFileConfig: 1 fila por tenant, guarda la glosa real de
#    transferencia (ej. "PLANILLA EMPRESARIAL BURGER KING COSTA RICA").
#    Catalogo, no hardcode.
#  - BankTransferFile + BankTransferFileLine: cabecera + lineas de
#    cada generacion real del archivo, para auditoria (que se genero,
#    cuando, por cuanto, cuantos empleados quedaron fuera por falta
#    de cuenta bancaria).
# Ejecutar: cd /opt/workforce-ai-os && bash fase10_parte2_models.sh
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

python3 << 'PYEOF'
path = "apps/backend/app/db/models.py"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

# ---------- 1. Agregar Integer al import (no estaba importado) ----------
anchor_import = "from sqlalchemy import DateTime, Date, Time, ForeignKey, String, Boolean, Numeric, UniqueConstraint, Text"
assert anchor_import in src, "ANCHOR NOT FOUND: import sqlalchemy"
assert src.count(anchor_import) == 1, "ANCHOR NOT UNIQUE: import sqlalchemy"
src = src.replace(
    anchor_import,
    "from sqlalchemy import DateTime, Date, Time, ForeignKey, String, Boolean, Numeric, Integer, UniqueConstraint, Text",
)

# ---------- 2. Employee: agregar bank_account_type / bank_account_number ----------
anchor_employee = '''    position: Mapped[str] = mapped_column(String(150), nullable=False)
    hire_date: Mapped[Date] = mapped_column(Date, nullable=False)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))'''
assert anchor_employee in src, "ANCHOR NOT FOUND: Employee fields"
assert src.count(anchor_employee) == 1, "ANCHOR NOT UNIQUE: Employee fields"
new_employee = '''    position: Mapped[str] = mapped_column(String(150), nullable=False)
    hire_date: Mapped[Date] = mapped_column(Date, nullable=False)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    # Cuenta de Ahorro | Cuenta Corriente - para el archivo de transferencia
    # bancaria (fase 10). Nullable: se completa despues via PATCH, no es
    # obligatorio al crear el empleado.
    bank_account_type: Mapped[Optional[str]] = mapped_column(String(30), nullable=True)
    bank_account_number: Mapped[Optional[str]] = mapped_column(String(30), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))'''
src = src.replace(anchor_employee, new_employee)

# ---------- 3. Modelos nuevos, insertados antes de class Device(Base): ----------
anchor_device = "class Device(Base):"
assert anchor_device in src, "ANCHOR NOT FOUND: class Device"
assert src.count(anchor_device) == 1, "ANCHOR NOT UNIQUE: class Device"

new_models = '''class BankFileConfig(Base):
    """
    Configuracion del archivo de transferencia bancaria por tenant (fase 10).
    La glosa (texto que aparece en la transferencia, ej. "PLANILLA
    EMPRESARIAL BURGER KING COSTA RICA") es un valor real confirmado por el
    cliente, cargado aqui como catalogo -- nunca hardcodeado en el codigo.
    """
    __tablename__ = "bank_file_configs"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    glosa: Mapped[str] = mapped_column(String(255), nullable=False)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))
    __table_args__ = (
        UniqueConstraint("tenant_id", name="uq_bank_file_config_tenant"),
    )


class BankTransferFile(Base):
    """
    Cabecera de cada generacion real del archivo de transferencia bancaria
    (fase 10). Queda como registro de auditoria: que se genero, cuando,
    por cuanto, y cuantos empleados quedaron fuera por falta de cuenta
    bancaria cargada.
    """
    __tablename__ = "bank_transfer_files"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    payroll_period_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("payroll_periods.id"), nullable=False)
    branch_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey("branches.id"), nullable=True)
    generated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))
    row_count: Mapped[int] = mapped_column(Integer, nullable=False)
    total_amount: Mapped[float] = mapped_column(Numeric(14, 2), nullable=False)
    missing_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    created_by: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)


class BankTransferFileLine(Base):
    """
    Una linea = un empleado con su cuenta bancaria y el monto neto a
    transferir. Guarda la glosa "congelada" al momento de generar (si la
    config cambia despues, esta linea historica no se altera).
    """
    __tablename__ = "bank_transfer_file_lines"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    bank_transfer_file_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("bank_transfer_files.id"), nullable=False)
    employee_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("employees.id"), nullable=False)
    account_type: Mapped[str] = mapped_column(String(30), nullable=False)
    account_number: Mapped[str] = mapped_column(String(30), nullable=False)
    amount: Mapped[float] = mapped_column(Numeric(14, 2), nullable=False)
    glosa: Mapped[str] = mapped_column(String(255), nullable=False)


'''
src = src.replace(anchor_device, new_models + anchor_device)

with open(path, "w", encoding="utf-8") as f:
    f.write(src)

print("OK: models.py actualizado (Employee + BankFileConfig + BankTransferFile + BankTransferFileLine)")
PYEOF

python3 -m py_compile apps/backend/app/db/models.py && echo "SYNTAX OK: models.py"

echo "=== FIN Parte 2 (modelos) ==="
