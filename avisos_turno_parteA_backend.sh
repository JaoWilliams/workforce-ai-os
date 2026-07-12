#!/bin/bash
# ============================================================
# #138 - Avisos de seguimiento al cierre/inicio de turno - PARTE A (backend)
#
# Diseno acordado: dos tipos de aviso, calculados EN VIVO (sin worker en
# background - mismo patron que onboarding_missing/has_pending_exceptions):
#   - no_show: el turno ya empezo (+ minutos de gracia) y el empleado no
#     tiene marcacion de entrada ese dia.
#   - not_closed: el turno ya termino (+ minutos de gracia), hay marcacion
#     de entrada pero no de salida.
# Minutos de gracia parametrizados via ShiftAlertConfig (nueva tabla,
# 1 fila por tenant, editable desde catalogos) - CERO valores quemados.
#
# NOTA DE TRANSPARENCIA: la tabla nueva se crea via SQL directo (mismo
# patron que Contract.language esta sesion), SIN politica RLS todavia
# (no tengo el SQL exacto de las politicas existentes para no arriesgar
# un error). Como red de seguridad, todas las queries sobre esta tabla
# filtran tenant_id explicitamente en el codigo Python. Pendiente:
# agregar RLS formal via Alembic en una pasada futura.
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

# ---------- 1. modelo ShiftAlertConfig ----------
python3 << 'PYEOF'
path = "apps/backend/app/db/models.py"
with open(path, encoding="utf-8") as f:
    src = f.read()

old = '''class ShiftAssignment(Base):
    """Asignación de un empleado a una plantilla de turno, por rango de fechas
    — permite rotación real: el mismo empleado puede tener asignaciones
    distintas en rangos de fecha distintos."""
    __tablename__ = "shift_assignments"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    employee_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("employees.id"), nullable=False)
    shift_template_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("shift_templates.id"), nullable=False
    )
    start_date: Mapped[date] = mapped_column(Date, nullable=False)
    end_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))'''

new = '''class ShiftAssignment(Base):
    """Asignación de un empleado a una plantilla de turno, por rango de fechas
    — permite rotación real: el mismo empleado puede tener asignaciones
    distintas en rangos de fecha distintos."""
    __tablename__ = "shift_assignments"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    employee_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("employees.id"), nullable=False)
    shift_template_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("shift_templates.id"), nullable=False
    )
    start_date: Mapped[date] = mapped_column(Date, nullable=False)
    end_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))


class ShiftAlertConfig(Base):
    """Config de avisos de seguimiento de turno (#138) - minutos de gracia
    antes de marcar un aviso de no-show (no marco entrada) o de turno sin
    cerrar (no marco salida). Un solo row por tenant, mismo patron que
    VacationConfig/AguinaldoConfig. Sin valor quemado en el calculo: si no
    existe el row, el endpoint de avisos usa 15 minutos por defecto pero
    queda visible/editable en catalogos igual que los demas."""
    __tablename__ = "shift_alert_configs"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    no_show_grace_minutes: Mapped[int] = mapped_column(nullable=False, default=15, server_default=text("15"))
    not_closed_grace_minutes: Mapped[int] = mapped_column(nullable=False, default=15, server_default=text("15"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))'''

assert old in src, "ANCHOR NOT FOUND: ShiftAssignment"
assert src.count(old) == 1, "ANCHOR NOT UNIQUE: ShiftAssignment"
src = src.replace(old, new, 1)
with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("OK: models.py - ShiftAlertConfig agregado")
PYEOF

# ---------- 2. tabla nueva via SQL directo (sin Alembic, mismo patron de la sesion) ----------
echo "=== creando tabla shift_alert_configs ==="
docker compose exec -T postgres psql -U workforce -d workforce_ai_os -c "
CREATE TABLE IF NOT EXISTS shift_alert_configs (
    id UUID PRIMARY KEY,
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    no_show_grace_minutes INTEGER NOT NULL DEFAULT 15,
    not_closed_grace_minutes INTEGER NOT NULL DEFAULT 15,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
"
echo "=== verificacion ==="
docker compose exec -T postgres psql -U workforce -d workforce_ai_os -c "\d shift_alert_configs"

# ---------- 3. core/shift_alerts.py (nuevo archivo) ----------
cat > apps/backend/app/core/shift_alerts.py << 'PYEOF'
"""
Avisos de seguimiento al cierre/inicio de turno (#138). Calculado en vivo
(sin worker en background - mismo patron que onboarding_missing y
has_pending_exceptions) cada vez que se pide la lista - no se persiste
como TrustFlag porque un aviso se resuelve solo apenas existe la
marcacion correspondiente, no requiere flujo de aprobacion.

Dos tipos de aviso, parametrizados via ShiftAlertConfig (sin datos
quemados - ver modelo en db/models.py):
- no_show: el turno ya empezo (+ minutos de gracia) y no hay marcacion de
  entrada de ese empleado ese dia.
- not_closed: el turno ya termino (+ minutos de gracia) y hay marcacion
  de entrada pero no de salida ese dia.

Simplificacion conocida (demo): las horas de turno se comparan contra
"now" usando la misma zona horaria que el resto del sistema de marcacion
(sin conversion explicita de zona horaria adicional) - igual tratamiento
que el calculo de horas extra (fase 3 de nomina), que ya compara turno
vs. marcaciones reales sin ese ajuste.
"""
from datetime import date, datetime, timedelta
from uuid import UUID

from sqlalchemy import select

from app.db.models import AttendanceRecord, Employee, ShiftAssignment, ShiftTemplate


async def get_shift_alerts(session, tenant_id: UUID, config, target_date: date, now: datetime) -> list[dict]:
    """config = fila de ShiftAlertConfig (o None -> usa 15 min por defecto)."""
    no_show_grace = config.no_show_grace_minutes if config else 15
    not_closed_grace = config.not_closed_grace_minutes if config else 15

    weekday = target_date.weekday()  # 0=lunes...6=domingo, coincide con days_of_week

    assignments_result = await session.execute(
        select(ShiftAssignment, ShiftTemplate, Employee)
        .join(ShiftTemplate, ShiftAssignment.shift_template_id == ShiftTemplate.id)
        .join(Employee, ShiftAssignment.employee_id == Employee.id)
        .where(
            ShiftAssignment.tenant_id == tenant_id,
            ShiftAssignment.start_date <= target_date,
            ShiftTemplate.active.is_(True),
            Employee.active.is_(True),
        )
    )
    rows = assignments_result.all()

    alerts = []
    for assignment, template, employee in rows:
        if assignment.end_date is not None and assignment.end_date < target_date:
            continue
        if weekday not in (template.days_of_week or []):
            continue

        shift_start = datetime.combine(target_date, template.start_time, tzinfo=now.tzinfo)
        shift_end = datetime.combine(target_date, template.end_time, tzinfo=now.tzinfo)
        if template.end_time <= template.start_time:
            shift_end += timedelta(days=1)  # turno nocturno cruza medianoche

        att_result = await session.execute(
            select(AttendanceRecord).where(
                AttendanceRecord.tenant_id == tenant_id,
                AttendanceRecord.employee_id == employee.id,
                AttendanceRecord.recorded_at >= shift_start - timedelta(hours=2),
                AttendanceRecord.recorded_at <= shift_end + timedelta(hours=2),
            )
        )
        records = att_result.scalars().all()
        has_entrada = any(r.type == "entrada" for r in records)
        has_salida = any(r.type == "salida" for r in records)

        if now >= shift_start + timedelta(minutes=no_show_grace) and not has_entrada:
            alerts.append({
                "type": "no_show",
                "employee_id": employee.id,
                "employee_name": f"{employee.first_name} {employee.last_name}",
                "branch_id": template.branch_id,
                "shift_template_id": template.id,
                "shift_name": template.name,
                "scheduled_at": shift_start,
                "minutes_late": int((now - shift_start).total_seconds() // 60),
            })
        elif has_entrada and not has_salida and now >= shift_end + timedelta(minutes=not_closed_grace):
            alerts.append({
                "type": "not_closed",
                "employee_id": employee.id,
                "employee_name": f"{employee.first_name} {employee.last_name}",
                "branch_id": template.branch_id,
                "shift_template_id": template.id,
                "shift_name": template.name,
                "scheduled_at": shift_end,
                "minutes_late": int((now - shift_end).total_seconds() // 60),
            })
    return alerts
PYEOF
python3 -m py_compile apps/backend/app/core/shift_alerts.py && echo "OK: shift_alerts.py SYNTAX OK"

# ---------- 4. shifts/schemas.py: ShiftAlertResponse ----------
python3 << 'PYEOF'
path = "apps/backend/app/modules/shifts/schemas.py"
with open(path, encoding="utf-8") as f:
    src = f.read()

old = '''class ShiftCoverageResponse(BaseModel):
    shift_template_id: UUID
    date: date
    min_coverage: int
    assigned_count: int
    covered: bool'''
new = '''class ShiftCoverageResponse(BaseModel):
    shift_template_id: UUID
    date: date
    min_coverage: int
    assigned_count: int
    covered: bool


class ShiftAlertResponse(BaseModel):
    type: str
    employee_id: UUID
    employee_name: str
    branch_id: UUID
    shift_template_id: UUID
    shift_name: str
    scheduled_at: datetime
    minutes_late: int'''

assert old in src, "ANCHOR NOT FOUND: ShiftCoverageResponse"
assert src.count(old) == 1, "ANCHOR NOT UNIQUE: ShiftCoverageResponse"
src = src.replace(old, new, 1)
with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("OK: shifts/schemas.py - ShiftAlertResponse agregado")
PYEOF

# ---------- 5. shifts/router.py: endpoint /alerts ----------
python3 << 'PYEOF'
path = "apps/backend/app/modules/shifts/router.py"
with open(path, encoding="utf-8") as f:
    src = f.read()

edits = []

edits.append(("import datetime completo", '''from datetime import date as date_type''',
'''from datetime import date as date_type, datetime, timezone'''))

edits.append(("import modelos nuevos", '''from app.db.models import Branch, Employee, ShiftAssignment, ShiftTemplate, User''',
'''from app.core.shift_alerts import get_shift_alerts
from app.db.models import AttendanceRecord, Branch, Employee, ShiftAlertConfig, ShiftAssignment, ShiftTemplate, User'''))

edits.append(("import ShiftAlertResponse", '''from app.modules.shifts.schemas import (
    ShiftAssignmentCreate,
    ShiftAssignmentResponse,
    ShiftCoverageResponse,
    ShiftTemplateCreate,
    ShiftTemplateResponse,
    ShiftTemplateUpdate,
)''',
'''from app.modules.shifts.schemas import (
    ShiftAlertResponse,
    ShiftAssignmentCreate,
    ShiftAssignmentResponse,
    ShiftCoverageResponse,
    ShiftTemplateCreate,
    ShiftTemplateResponse,
    ShiftTemplateUpdate,
)'''))

edits.append(("endpoint GET /alerts", '''@router.get("/{shift_template_id}/coverage", response_model=ShiftCoverageResponse)''',
'''@router.get("/alerts", response_model=list[ShiftAlertResponse])
async def list_shift_alerts(
    branch_id: UUID | None = None,
    on_date: date_type | None = None,
    current_user: User = Depends(require_permission("shifts.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        config_result = await session.execute(
            select(ShiftAlertConfig).where(ShiftAlertConfig.tenant_id == current_user.tenant_id)
        )
        config = config_result.scalars().first()
        target_date = on_date or date_type.today()
        now = datetime.now(timezone.utc)
        alerts = await get_shift_alerts(session, current_user.tenant_id, config, target_date, now)
        if branch_id is not None:
            alerts = [a for a in alerts if a["branch_id"] == branch_id]
    return [ShiftAlertResponse(**a) for a in alerts]


@router.get("/{shift_template_id}/coverage", response_model=ShiftCoverageResponse)'''))

for label, old, new in edits:
    assert old in src, f"ANCHOR NOT FOUND ({label})"
    assert src.count(old) == 1, f"ANCHOR NOT UNIQUE ({label})"
    src = src.replace(old, new, 1)
    print(f"OK edicion aplicada: {label}")

with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("OK: shifts/router.py escrito")
PYEOF
python3 -m py_compile apps/backend/app/modules/shifts/router.py && echo "shifts/router.py SYNTAX OK"
python3 -m py_compile apps/backend/app/modules/shifts/schemas.py && echo "shifts/schemas.py SYNTAX OK"
python3 -m py_compile apps/backend/app/db/models.py && echo "models.py SYNTAX OK"

# ---------- 6. catalogs/schemas.py: ShiftAlertConfigUpsert/Response ----------
python3 << 'PYEOF'
path = "apps/backend/app/modules/catalogs/schemas.py"
with open(path, encoding="utf-8") as f:
    src = f.read()

old = '''class VacationConfigUpsert(BaseModel):
    cycle_weeks: float


class VacationConfigResponse(BaseModel):
    cycle_weeks: float'''
new = '''class VacationConfigUpsert(BaseModel):
    cycle_weeks: float


class VacationConfigResponse(BaseModel):
    cycle_weeks: float


class ShiftAlertConfigUpsert(BaseModel):
    no_show_grace_minutes: int = 15
    not_closed_grace_minutes: int = 15


class ShiftAlertConfigResponse(BaseModel):
    no_show_grace_minutes: int
    not_closed_grace_minutes: int'''

assert old in src, "ANCHOR NOT FOUND: VacationConfig schemas"
assert src.count(old) == 1, "ANCHOR NOT UNIQUE: VacationConfig schemas"
src = src.replace(old, new, 1)
with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("OK: catalogs/schemas.py - ShiftAlertConfig schemas agregados")
PYEOF
python3 -m py_compile apps/backend/app/modules/catalogs/schemas.py && echo "catalogs/schemas.py SYNTAX OK"

# ---------- 7. catalogs/router.py: import + endpoints GET/PUT shift-alert-config ----------
python3 << 'PYEOF'
path = "apps/backend/app/modules/catalogs/router.py"
with open(path, encoding="utf-8") as f:
    src = f.read()

edits = []

edits.append(("import ShiftAlertConfig modelo", '''from app.db.models import AguinaldoConfig, BankFileConfig, CesantiaConfig, CesantiaScaleRow, ChartOfAccount, Holiday, PayrollConcept, PayrollHoursConfig, RentaCredits, TaxBracket, User, VacationConfig''',
'''from app.db.models import AguinaldoConfig, BankFileConfig, CesantiaConfig, CesantiaScaleRow, ChartOfAccount, Holiday, PayrollConcept, PayrollHoursConfig, RentaCredits, ShiftAlertConfig, TaxBracket, User, VacationConfig'''))

edits.append(("import ShiftAlertConfig schemas", '''    BankFileConfigUpsert,
    BankFileConfigResponse,
)''',
'''    BankFileConfigUpsert,
    BankFileConfigResponse,
    ShiftAlertConfigUpsert,
    ShiftAlertConfigResponse,
)'''))

edits.append(("endpoints GET/PUT shift-alert-config", '''@hours_router.get("/vacation-config", response_model=Optional[VacationConfigResponse])
async def get_vacation_config(
    current_user: User = Depends(require_permission("catalogs.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(VacationConfig))
        config = result.scalars().first()
    if config is None:
        return None
    return VacationConfigResponse(cycle_weeks=float(config.cycle_weeks))''',
'''@hours_router.get("/vacation-config", response_model=Optional[VacationConfigResponse])
async def get_vacation_config(
    current_user: User = Depends(require_permission("catalogs.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(VacationConfig))
        config = result.scalars().first()
    if config is None:
        return None
    return VacationConfigResponse(cycle_weeks=float(config.cycle_weeks))


@hours_router.put("/shift-alert-config", response_model=ShiftAlertConfigResponse)
async def upsert_shift_alert_config(
    payload: ShiftAlertConfigUpsert,
    current_user: User = Depends(require_permission("catalogs.manage")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(
            select(ShiftAlertConfig).where(ShiftAlertConfig.tenant_id == current_user.tenant_id)
        )
        config = result.scalars().first()
        if config is None:
            config = ShiftAlertConfig(
                id=uuid4(), tenant_id=current_user.tenant_id,
                no_show_grace_minutes=payload.no_show_grace_minutes,
                not_closed_grace_minutes=payload.not_closed_grace_minutes,
            )
            session.add(config)
            action = "shift_alert_config.created"
        else:
            config.no_show_grace_minutes = payload.no_show_grace_minutes
            config.not_closed_grace_minutes = payload.not_closed_grace_minutes
            action = "shift_alert_config.updated"
        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action=action, resource_type="shift_alert_config", resource_id=config.id,
            extra={
                "no_show_grace_minutes": payload.no_show_grace_minutes,
                "not_closed_grace_minutes": payload.not_closed_grace_minutes,
            },
        )
        await session.commit()
        await session.refresh(config)
    return ShiftAlertConfigResponse(
        no_show_grace_minutes=config.no_show_grace_minutes,
        not_closed_grace_minutes=config.not_closed_grace_minutes,
    )


@hours_router.get("/shift-alert-config", response_model=Optional[ShiftAlertConfigResponse])
async def get_shift_alert_config(
    current_user: User = Depends(require_permission("catalogs.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(
            select(ShiftAlertConfig).where(ShiftAlertConfig.tenant_id == current_user.tenant_id)
        )
        config = result.scalars().first()
    if config is None:
        return None
    return ShiftAlertConfigResponse(
        no_show_grace_minutes=config.no_show_grace_minutes,
        not_closed_grace_minutes=config.not_closed_grace_minutes,
    )'''))

for label, old, new in edits:
    assert old in src, f"ANCHOR NOT FOUND ({label})"
    assert src.count(old) == 1, f"ANCHOR NOT UNIQUE ({label})"
    src = src.replace(old, new, 1)
    print(f"OK edicion aplicada: {label}")

with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("OK: catalogs/router.py escrito")
PYEOF
python3 -m py_compile apps/backend/app/modules/catalogs/router.py && echo "catalogs/router.py SYNTAX OK"

# ---------- 8. rebuild api ----------
echo "=== rebuild api ==="
docker compose build --no-cache api
docker compose up -d api
sleep 6
docker compose logs api --tail 40

echo "=== FIN avisos de turno - parte A backend ==="
