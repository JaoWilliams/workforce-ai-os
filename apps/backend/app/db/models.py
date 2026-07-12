import uuid
from sqlalchemy import text
from datetime import datetime, date, time
from typing import Optional

from sqlalchemy import DateTime, Date, Time, ForeignKey, String, Boolean, Numeric, Integer, UniqueConstraint, Text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Tenant(Base):
    __tablename__ = "tenants"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    slug: Mapped[str] = mapped_column(String(100), nullable=False, unique=True)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    email: Mapped[str] = mapped_column(String(255), nullable=False)
    hashed_password: Mapped[str] = mapped_column(String(255), nullable=False)
    active: Mapped[bool] = mapped_column(nullable=False, default=True, server_default=text("true"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))


class Branch(Base):
    __tablename__ = "branches"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    code: Mapped[str] = mapped_column(String(50), nullable=False)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    accounting_account: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    supervisor_user_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    active: Mapped[bool] = mapped_column(nullable=False, default=True, server_default=text("true"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))


class Role(Base):
    __tablename__ = "roles"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    permissions: Mapped[list] = mapped_column(JSONB, nullable=False, default=list)
    active: Mapped[bool] = mapped_column(nullable=False, default=True, server_default=text("true"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))


class UserRole(Base):
    __tablename__ = "user_roles"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    role_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("roles.id"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))


class UserBranch(Base):
    __tablename__ = "user_branches"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    branch_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("branches.id"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))


class ConsentRecord(Base):
    __tablename__ = "consent_records"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    # user_id: cuenta de login que consiente por sí misma (caso original).
    # employee_id: empleado sujeto del consentimiento (caso real de biometría, Ley 8968) —
    # el empleado normalmente NO tiene cuenta de login, un admin lo registra en su nombre.
    # Exactamente uno de los dos debe estar presente (validado en el endpoint).
    user_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    employee_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey("employees.id"), nullable=True)
    consent_type: Mapped[str] = mapped_column(String(50), nullable=False)
    granted: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    granted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))
    revoked_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)


class AuditLog(Base):
    __tablename__ = "audit_logs"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    actor_user_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    action: Mapped[str] = mapped_column(String(100), nullable=False)
    resource_type: Mapped[str] = mapped_column(String(100), nullable=False)
    resource_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), nullable=True)
    extra: Mapped[dict] = mapped_column(JSONB, nullable=False, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))


class PayrollPeriod(Base):
    """
    Período de planilla (calendario de nómina). Toda corrida de nómina real
    debe ejecutarse dentro de un período definido aquí — fechas de inicio/
    fin/pago cargadas explícitamente por el cliente, nunca calculadas por
    una fórmula asumida por el sistema (los feriados/fines de semana pueden
    correr la fecha de pago real, y eso lo decide el cliente).
    """
    __tablename__ = "payroll_periods"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    # semanal | quincenal | bisemanal | mensual
    pay_frequency: Mapped[str] = mapped_column(String(20), nullable=False)
    period_start: Mapped[date] = mapped_column(Date, nullable=False)
    period_end: Mapped[date] = mapped_column(Date, nullable=False)
    # Null hasta que el cliente confirme la fecha real (puede correrse por feriados/fines de semana)
    pay_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
    # draft | validado | calculado | aprobado | pagado | contabilizado | archivo_bancario
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="draft")
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))

    __table_args__ = (
        UniqueConstraint("tenant_id", "pay_frequency", "period_start", name="uq_payroll_period_tenant_freq_start"),
    )


class PayrollHoursConfig(Base):
    """
    Horas estándar por período de pago, PARAMETRIZABLE por tenant — nunca un
    valor por defecto inventado por el sistema. El cliente (vía su contador/
    asesor legal) debe cargar explícitamente cuántas horas representa cada
    frecuencia de pago (semanal | quincenal | bisemanal | mensual) según su
    jurisdicción y política interna real. Si una frecuencia no tiene fila
    aquí, core/payroll.py NO calcula el bruto para esos contratos — lo marca
    como "configuración pendiente" en vez de asumir un número.
    """
    __tablename__ = "payroll_hours_configs"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    # semanal | quincenal | bisemanal | mensual
    pay_frequency: Mapped[str] = mapped_column(String(20), nullable=False)
    standard_hours: Mapped[float] = mapped_column(Numeric(6, 2), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))

    __table_args__ = (
        UniqueConstraint("tenant_id", "pay_frequency", name="uq_payroll_hours_config_tenant_freq"),
    )


class PayrollConcept(Base):
    __tablename__ = "payroll_concepts"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    code: Mapped[str] = mapped_column(String(50), nullable=False)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    # monto_fijo | porcentaje | cantidad
    calculation_method: Mapped[str] = mapped_column(String(20), nullable=False)
    # ingreso | deduccion
    nature: Mapped[str] = mapped_column(String(20), nullable=False)
    # patronal | empleado
    origin: Mapped[str] = mapped_column(String(20), nullable=False)
    value: Mapped[float] = mapped_column(Numeric(12, 4), nullable=False)
    # % patronal (CCSS y similares) - nullable, sin valor por defecto: no todo concepto tiene componente patronal
    employer_value: Mapped[Optional[float]] = mapped_column(Numeric(12, 4), nullable=True)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))
    accounting_account_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey("chart_of_accounts.id"), nullable=True)


class OvertimeApproval(Base):
    """Horas extra candidatas por dia de trabajo, calculadas contra la duracion
    real del turno asignado (ShiftTemplate via ShiftAssignment, mod. 13) - no
    contra un umbral fijo de horas por dia, porque distintos turnos ya tienen
    horas extra implicitas segun su definicion. Requieren aprobacion explicita
    de un supervisor antes de contar en el bruto de nomina: mientras haya
    registros en estado pending para un empleado en el periodo, el bruto de
    ese empleado queda bloqueado (ver compute_payroll_rows en core/payroll.py,
    decision confirmada con el usuario 2026-07-10)."""
    __tablename__ = "overtime_approvals"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    employee_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("employees.id"), nullable=False)
    shift_template_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("shift_templates.id"), nullable=False
    )
    work_date: Mapped[date] = mapped_column(Date, nullable=False)
    ordinary_hours: Mapped[float] = mapped_column(Numeric(6, 2), nullable=False)
    extra_hours: Mapped[float] = mapped_column(Numeric(6, 2), nullable=False)
    # pending | approved | rejected
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="pending")
    reviewed_by: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    reviewed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))

    __table_args__ = (
        UniqueConstraint("tenant_id", "employee_id", "work_date", name="uq_overtime_tenant_employee_date"),
    )


class Holiday(Base):
    """Catalogo de feriados por tenant - fechas y tipo (obligatorio/no
    obligatorio) cargados por el cliente, cero fechas hardcodeadas (varian
    cada ano: Semana Santa, feriados trasladados por decreto, etc). Ajusta
    el bruto de nomina automaticamente via core/holidays.py: recargo si se
    trabaja un obligatorio, pago de la jornada si no se trabaja un
    obligatorio pero el turno lo tenia programado ese dia (decision
    confirmada con el usuario 2026-07-10 - sin aprobacion de supervisor,
    a diferencia de horas extra, porque es un hecho objetivo)."""
    __tablename__ = "holidays"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    date: Mapped[date] = mapped_column(Date, nullable=False)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    # obligatorio | no_obligatorio
    payment_type: Mapped[str] = mapped_column(String(20), nullable=False)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))

    __table_args__ = (
        UniqueConstraint("tenant_id", "date", name="uq_holiday_tenant_date"),
    )


class Dependent(Base):
    """Dependientes del empleado (conyuge/hijos) para el credito fiscal de
    renta (Ley del Impuesto sobre la Renta). Se guarda fecha de nacimiento,
    no una edad fija, para calcular "menor de 25 anos cumplidos" en el
    momento del calculo de planilla, no un valor que se vuelva obsoleto."""
    __tablename__ = "dependents"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    employee_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("employees.id"), nullable=False)
    # conyuge | hijo
    relationship_type: Mapped[str] = mapped_column(String(20), nullable=False)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    birth_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))


class TaxBracket(Base):
    """Tramos progresivos del Impuesto sobre la Renta - piso, techo, tasa,
    por ano fiscal. Cero valores quemados: se cargan como catalogo, cambian
    cada ano por decreto de Hacienda."""
    __tablename__ = "tax_brackets"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    year: Mapped[int] = mapped_column(nullable=False)
    bracket_order: Mapped[int] = mapped_column(nullable=False)
    lower_bound: Mapped[float] = mapped_column(Numeric(14, 2), nullable=False)
    upper_bound: Mapped[Optional[float]] = mapped_column(Numeric(14, 2), nullable=True)
    rate: Mapped[float] = mapped_column(Numeric(5, 2), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))

    __table_args__ = (
        UniqueConstraint("tenant_id", "year", "bracket_order", name="uq_taxbracket_tenant_year_order"),
    )


class RentaCredits(Base):
    """Creditos fijos de renta por conyuge y por hijo menor de 25 anos
    cumplidos, por ano fiscal. Cero valores quemados."""
    __tablename__ = "renta_credits"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    year: Mapped[int] = mapped_column(nullable=False)
    spouse_credit: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    child_credit: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))

    __table_args__ = (
        UniqueConstraint("tenant_id", "year", name="uq_rentacredits_tenant_year"),
    )


class VacationConfig(Base):
    """Configuracion de vacaciones por tenant (Codigo de Trabajo CR, Art. 153
    y 157). cycle_weeks = largo del ciclo legal (2 semanas de derecho por
    cada cycle_weeks semanas trabajadas continuas) - 50 es el valor legal
    confirmado (no placeholder), pero se deja parametrizable por si cambia
    por reforma legal futura. Los DIAS de vacacion por ciclo NO se guardan
    aqui como numero fijo: se derivan del turno real de cada empleado
    (2 x dias_laborables_semana del ShiftTemplate asignado - ver
    core/vacations.py), porque un 6x1 acumula 12 dias/ciclo y un 5x2
    acumula 10, aunque el derecho legal (2 semanas) es el mismo."""
    __tablename__ = "vacation_configs"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    cycle_weeks: Mapped[float] = mapped_column(Numeric(5, 2), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))

    __table_args__ = (
        UniqueConstraint("tenant_id", name="uq_vacation_config_tenant"),
    )


class VacationRequest(Base):
    """Solicitud de vacaciones. days_count se calcula UNA vez al crear la
    solicitud (dias del rango que caen en dia laborable segun el turno del
    empleado en ese momento - Art. 153: la unidad legal es la semana, los
    dias son la conversion administrativa). Requiere aprobacion de un
    supervisor antes de contar en el pago de nomina (mismo patron que
    OvertimeApproval): mientras haya una solicitud pending que se traslape
    con el periodo de planilla, el bruto de ese empleado queda bloqueado
    en ese periodo. El monto a pagar (Art. 157: promedio de salario
    ordinario + extraordinario) se calcula en el momento del calculo de
    planilla, no se guarda aqui - ver core/vacations.py."""
    __tablename__ = "vacation_requests"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    employee_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("employees.id"), nullable=False)
    start_date: Mapped[date] = mapped_column(Date, nullable=False)
    end_date: Mapped[date] = mapped_column(Date, nullable=False)
    days_count: Mapped[float] = mapped_column(Numeric(6, 2), nullable=False)
    # pending | approved | rejected
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="pending")
    reviewed_by: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    reviewed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))


class AguinaldoConfig(Base):
    """Configuracion de aguinaldo por tenant (Ley de Aguinaldo CR, Art. 1).
    Ventana legal fija: 1 dic (ano anterior) a 30 nov (ano actual), monto =
    suma de todo lo devengado como salario en esa ventana (ordinario,
    extraordinario, comisiones y demas ingresos salariales que ya esten
    reflejados en gross_pay) dividido entre divisor (12). Se guarda como
    catalogo en vez de constante en codigo por consistencia con el resto
    del proyecto (cero valores quemados), aunque el usuario confirmo que
    son valores legales reales, no de prueba. Sin deducciones de CCSS/
    renta (confirmado con el usuario 2026-07-10) - planilla dedicada,
    separada de la planilla ordinaria."""
    __tablename__ = "aguinaldo_configs"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    period_start_month: Mapped[int] = mapped_column(nullable=False, default=12)
    period_start_day: Mapped[int] = mapped_column(nullable=False, default=1)
    period_end_month: Mapped[int] = mapped_column(nullable=False, default=11)
    period_end_day: Mapped[int] = mapped_column(nullable=False, default=30)
    divisor: Mapped[float] = mapped_column(Numeric(5, 2), nullable=False, default=12)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))

    __table_args__ = (
        UniqueConstraint("tenant_id", name="uq_aguinaldo_config_tenant"),
    )


class CesantiaConfig(Base):
    """Configuracion de cesantia por tenant (Art. 28/29/30 Codigo de
    Trabajo CR - ver documento "Cesantia Art 29.docx" cargado por el
    cliente 2026-07-10). Valores legales reales confirmados por el
    cliente, no placeholders:
    - max_years_cap = 8 (tope legal, nunca se paga mas de 8 anos aunque
      la antiguedad real sea mayor).
    - fraction_round_months = 6 (si el resto de meses tras los anos
      completos SUPERA este umbral, se redondea un anio adicional -
      redondeo hacia arriba solo si es estrictamente MAYOR, no >=;
      el documento del cliente se contradice entre su resumen ejecutivo
      ">=6" y su seccion detallada "> 6" - se adopto la seccion detallada
      por ser mas especifica, PENDIENTE de confirmar con el abogado
      laboral del cliente).
    - days_3to6_months = 7 (regla especial, menos de 1 anio de servicio).
    - days_6to12_months = 14 (regla especial, menos de 1 anio de servicio).
      Menos de 3 meses de servicio continuo = 0 dias, sin derecho.
    - daily_divisor = 30 (salario promedio mensual / 30 = salario diario,
      valido para pago mensual o quincenal - semanal usa otro divisor
      segun el documento, 30 o 26 segun actividad comercial/no comercial,
      NO soportado en esta fase por no haber contratos semanales reales
      todavia, ver core/cesantia.py).
    - months_for_average = 6 (ventana de meses hacia atras para el
      salario promedio, "hasta 6" si hay menos historial disponible)."""
    __tablename__ = "cesantia_configs"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    max_years_cap: Mapped[int] = mapped_column(nullable=False, default=8)
    fraction_round_months: Mapped[int] = mapped_column(nullable=False, default=6)
    days_3to6_months: Mapped[float] = mapped_column(Numeric(6, 2), nullable=False, default=7)
    days_6to12_months: Mapped[float] = mapped_column(Numeric(6, 2), nullable=False, default=14)
    daily_divisor: Mapped[float] = mapped_column(Numeric(5, 2), nullable=False, default=30)
    months_for_average: Mapped[int] = mapped_column(nullable=False, default=6)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))

    __table_args__ = (
        UniqueConstraint("tenant_id", name="uq_cesantia_config_tenant"),
    )


class CesantiaScaleRow(Base):
    """Tabla oficial del Art. 29: dias de salario por cada anio laborado
    (1 a 13+), tenant-scoped y editable como catalogo (cero valores
    quemados), aunque el cliente confirmo que son los valores legales
    reales del documento oficial (19.5, 20, 20.5, 21, 21.24, 21.5, 22,
    22, 22, 21.5, 21, 20.5, 20). Solo se usan las filas 1 a
    CesantiaConfig.max_years_cap (8) para el pago real; las filas 9-13
    se guardan por completitud/transparencia pero no afectan el calculo
    porque el tope las excluye."""
    __tablename__ = "cesantia_scale_rows"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    year_number: Mapped[int] = mapped_column(nullable=False)
    days: Mapped[float] = mapped_column(Numeric(6, 2), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))

    __table_args__ = (
        UniqueConstraint("tenant_id", "year_number", name="uq_cesantia_scale_tenant_year"),
    )


class Termination(Base):
    """Evento de terminacion de contrato. con_responsabilidad_patronal
    determina el derecho a cesantia (Art. 28: sin responsabilidad
    patronal - despido con causa justa - NO da derecho; con
    responsabilidad patronal - despido injustificado - SI da derecho).
    Requiere aprobacion antes de calcularse como definitivo (decision
    confirmada con el usuario 2026-07-10, mismo patron que
    OvertimeApproval/VacationRequest mas el peso legal/financiero real
    de una liquidacion). Al aprobarse, marca Employee.active=False."""
    __tablename__ = "terminations"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    employee_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("employees.id"), nullable=False)
    termination_date: Mapped[date] = mapped_column(Date, nullable=False)
    cause: Mapped[str] = mapped_column(String(255), nullable=False)
    con_responsabilidad_patronal: Mapped[bool] = mapped_column(Boolean, nullable=False)
    # pending | approved | rejected
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="pending")
    reviewed_by: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    reviewed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))

    __table_args__ = (
        UniqueConstraint("tenant_id", "employee_id", name="uq_termination_tenant_employee"),
    )


class ChartOfAccount(Base):
    """Plan de cuentas contables del tenant. No existia previamente -
    se crea en fase 9 (asientos) porque ninguna fase anterior necesitaba
    modelar cuentas individuales (Branch.accounting_account cubria el
    caso de centro de costo, pero no cuenta contable por concepto)."""
    __tablename__ = "chart_of_accounts"
    __table_args__ = (UniqueConstraint("tenant_id", "code", name="uq_chart_of_account_tenant_code"),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    code: Mapped[str] = mapped_column(String(50), nullable=False)
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


class BankFileConfig(Base):
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


class PayrollAnomalyConfig(Base):
    """
    Umbrales del motor de anomalias de nomina (fase 11), reusando el
    Motor de Confianza Operativa (mod 17a). 1 fila por tenant. Valores
    de PRUEBA flageados -- son parametros heuristicos de sensibilidad,
    no valores legales, pero igual quedan como catalogo editable en vez
    de constantes en el codigo.
    """
    __tablename__ = "payroll_anomaly_configs"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    net_deviation_pct_threshold: Mapped[float] = mapped_column(Numeric(6, 2), nullable=False)
    overtime_hours_multiplier_threshold: Mapped[float] = mapped_column(Numeric(6, 2), nullable=False)
    bank_account_change_window_days: Mapped[int] = mapped_column(Integer, nullable=False)
    branch_net_deviation_pct_threshold: Mapped[float] = mapped_column(Numeric(6, 2), nullable=False)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))
    __table_args__ = (
        UniqueConstraint("tenant_id", name="uq_payroll_anomaly_config_tenant"),
    )


class PayrollSnapshotLine(Base):
    """
    Congelado inmutable del resultado de nomina neta por empleado, al
    momento en que un PayrollPeriod pasa a 'calculado' (fase 11). Una
    vez congelado, los consumidores downstream (asientos contables,
    archivo bancario) leen de aqui en vez de recalcular en vivo -- asi
    un cambio posterior en TaxBracket/CCSS/etc. no altera un periodo
    ya calculado/pagado. 'detail' guarda la fila completa devuelta por
    compute_net_payroll_rows (todos los ajustes: horas extra, feriado,
    vacaciones, etc.) para trazabilidad completa.
    """
    __tablename__ = "payroll_snapshot_lines"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    payroll_period_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("payroll_periods.id"), nullable=False)
    employee_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("employees.id"), nullable=False)
    branch_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey("branches.id"), nullable=True)
    gross_pay: Mapped[Optional[float]] = mapped_column(Numeric(12, 2), nullable=True)
    ccss_deduction: Mapped[Optional[float]] = mapped_column(Numeric(12, 2), nullable=True)
    renta_amount: Mapped[Optional[float]] = mapped_column(Numeric(12, 2), nullable=True)
    renta_is_refund: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    net_pay: Mapped[Optional[float]] = mapped_column(Numeric(12, 2), nullable=True)
    detail: Mapped[dict] = mapped_column(JSONB, nullable=False, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))
    __table_args__ = (
        UniqueConstraint("payroll_period_id", "employee_id", name="uq_payroll_snapshot_period_employee"),
    )


class Device(Base):
    __tablename__ = "devices"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    branch_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("branches.id"), nullable=False)
    # tiandy | hikvision | zkteco
    brand: Mapped[str] = mapped_column(String(20), nullable=False)
    model: Mapped[str] = mapped_column(String(100), nullable=False)
    serial_number: Mapped[str] = mapped_column(String(100), nullable=False)
    # IP dentro de la red interna del cliente — el dispositivo nunca se expone a internet,
    # el backend le habla vía esta IP solo cuando exista el adaptador real (ver módulo 8/24).
    ip_address: Mapped[Optional[str]] = mapped_column(String(45), nullable=True)
    # not_provisioned | online | offline (heartbeat real pendiente de adaptador de marca)
    status: Mapped[str] = mapped_column(String(30), nullable=False, default="not_provisioned")
    # Capacidades reales del datasheet del dispositivo (ej. ZKTeco SenseFace 4A: 6000/8000/8000/200000).
    # Se cargan al dar de alta el dispositivo, no son constantes de código — varían por marca/modelo.
    max_faces: Mapped[Optional[int]] = mapped_column(nullable=True)
    max_fingerprints: Mapped[Optional[int]] = mapped_column(nullable=True)
    max_cards: Mapped[Optional[int]] = mapped_column(nullable=True)
    max_events: Mapped[Optional[int]] = mapped_column(nullable=True)
    # ej. ["facial", "fingerprint", "card", "password"] — según lo que soporte el modelo real
    verification_methods: Mapped[Optional[list]] = mapped_column(JSONB, nullable=True)
    active: Mapped[bool] = mapped_column(nullable=False, default=True, server_default=text("true"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))


class Employee(Base):
    __tablename__ = "employees"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    branch_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("branches.id"), nullable=False)
    first_name: Mapped[str] = mapped_column(String(150), nullable=False)
    last_name: Mapped[str] = mapped_column(String(150), nullable=False)
    # cedula_fisica | cedula_juridica | dimex | pasaporte
    id_type: Mapped[str] = mapped_column(String(20), nullable=False)
    id_number: Mapped[str] = mapped_column(String(50), nullable=False)
    email: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    phone: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    position: Mapped[str] = mapped_column(String(150), nullable=False)
    hire_date: Mapped[Date] = mapped_column(Date, nullable=False)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    # Cuenta de Ahorro | Cuenta Corriente - para el archivo de transferencia
    # bancaria (fase 10). Nullable: se completa despues via PATCH, no es
    # obligatorio al crear el empleado.
    bank_account_type: Mapped[Optional[str]] = mapped_column(String(30), nullable=True)
    bank_account_number: Mapped[Optional[str]] = mapped_column(String(30), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))


class Contract(Base):
    __tablename__ = "contracts"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    employee_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("employees.id"), nullable=False)
    # indefinido | plazo_fijo | por_obra
    contract_type: Mapped[str] = mapped_column(String(20), nullable=False)
    start_date: Mapped[Date] = mapped_column(Date, nullable=False)
    end_date: Mapped[Optional[Date]] = mapped_column(Date, nullable=True)
    base_salary: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    # CRC | USD | GTQ | HNL | NIO | PAB (multimoneda, ver sección 4 del doc maestro)
    currency: Mapped[str] = mapped_column(String(3), nullable=False, default="CRC")
    # semanal | quincenal | bisemanal | mensual — define qué representa base_salary
    # (el monto de UN período de pago, no necesariamente mensual) y el divisor de
    # horas usado para derivar la tarifa por hora en la nómina bruta (core/payroll.py).
    pay_frequency: Mapped[str] = mapped_column(String(20), nullable=False, server_default=text("'mensual'"))
    # es | en - idioma unico en que se genera el PDF del contrato (#98: se elimino
    # el PDF bilingue, ahora se elige un idioma segun quien crea el contrato)
    language: Mapped[str] = mapped_column(String(2), nullable=False, server_default=text("'es'"))
    pdf_path: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))


class BiometricEnrollment(Base):
    __tablename__ = "biometric_enrollments"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    employee_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("employees.id"), nullable=False)
    device_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("devices.id"), nullable=False)
    consent_record_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("consent_records.id"), nullable=False)
    # facial | fingerprint | card
    biometric_type: Mapped[str] = mapped_column(String(20), nullable=False)
    # Referencia/placeholder — NUNCA datos biométricos reales, ver is_simulated abajo.
    template_reference: Mapped[str] = mapped_column(String(200), nullable=False)
    # Mock EXPLÍCITAMENTE autorizado por el usuario (2026-07-08) ante ausencia de
    # hardware real, solo para demo del MVP. Debe ser true hasta que exista un
    # DeviceAdapter real implementado y probado — ver adapters/base.py y CLAUDE.md.
    is_simulated: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    enrolled_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))


class FeatureFlag(Base):
    """Catálogo global de funcionalidades activables por plan (sin RLS,
    igual que Tenant — es catálogo público de la plataforma, no dato
    de una empresa en particular)."""
    __tablename__ = "feature_flags"

    code: Mapped[str] = mapped_column(String(50), primary_key=True)
    name: Mapped[str] = mapped_column(String(150), nullable=False)
    description: Mapped[str] = mapped_column(String(500), nullable=False)
    # core | addon | premium (mismo criterio de categorías de la tabla de módulos, sección 6.1)
    category: Mapped[str] = mapped_column(String(20), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))


class TenantFeatureFlag(Base):
    """Override de habilitación por tenant, opcionalmente por sucursal.
    Si no existe fila para un (tenant, flag[, branch]), el default es:
    category='core' -> habilitado, cualquier otra categoría -> deshabilitado
    (ver core/feature_flags.py: is_feature_enabled)."""
    __tablename__ = "tenant_feature_flags"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    feature_flag_code: Mapped[str] = mapped_column(String(50), ForeignKey("feature_flags.code"), nullable=False)
    # NULL = override a nivel de todo el tenant. Con valor = override solo para esa sucursal.
    branch_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey("branches.id"), nullable=True)
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))


class AttendanceRecord(Base):
    """Marcación de entrada/salida. Implementa la estrategia offline decidida
    en la sección 4 del doc maestro: clave única dispositivo+timestamp+empleado
    para evitar duplicados durante la reconciliación del buffer del dispositivo."""
    __tablename__ = "attendance_records"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    employee_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("employees.id"), nullable=False)
    device_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("devices.id"), nullable=False)
    # entrada | salida
    type: Mapped[str] = mapped_column(String(20), nullable=False)
    # facial | fingerprint | card | manual
    verification_method: Mapped[str] = mapped_column(String(20), nullable=False)
    biometric_enrollment_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("biometric_enrollments.id"), nullable=True
    )
    # Hora real del evento (puede diferir de created_at si viene de reconciliación offline).
    recorded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    # Mismo patrón de mód. 10: no hay captura real por dispositivo (mód. 8 sin adaptador
    # implementado), así que toda marcación hoy se registra manualmente/vía API de prueba.
    is_simulated: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))

    __table_args__ = (
        UniqueConstraint("device_id", "employee_id", "recorded_at",
                          name="uq_attendance_device_employee_recorded_at"),
    )


class TrustFlag(Base):
    """Señal detectada por el Motor de Confianza Operativa™ (versión
    heurística, mód. 17a) — reglas sin ML sobre AttendanceRecord real."""
    __tablename__ = "trust_flags"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    employee_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey("employees.id"), nullable=True)
    payroll_period_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey("payroll_periods.id"), nullable=True)
    branch_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey("branches.id"), nullable=True)
    # consecutive_same_type | impossible_travel | missing_biometric |
    # payroll_net_deviation | payroll_net_zero_or_negative |
    # payroll_overtime_outlier | payroll_bank_account_changed_before_payment |
    # payroll_paid_after_termination | payroll_branch_net_outlier
    rule_code: Mapped[str] = mapped_column(String(50), nullable=False)
    # low | medium | high
    severity: Mapped[str] = mapped_column(String(20), nullable=False)
    # ids de AttendanceRecord involucrados + descripción legible de por qué se marcó
    details: Mapped[dict] = mapped_column(JSONB, nullable=False, default=dict)
    resolved: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    detected_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))


class TimeException(Base):
    """Mód. 14 (parte) — excepciones básicas: justificación de una anomalía de
    marcación (con evidencia opcional) y aprobación/rechazo por un supervisor.
    Referencia opcional a un AttendanceRecord puntual y/o a un TrustFlag del
    mód. 17a que esta excepción busca resolver."""
    __tablename__ = "time_exceptions"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    employee_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("employees.id"), nullable=False)
    attendance_record_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("attendance_records.id"), nullable=True
    )
    trust_flag_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("trust_flags.id"), nullable=True
    )
    # missing_checkin | missing_checkout | late_arrival | early_departure | absence | manual_correction | other
    exception_type: Mapped[str] = mapped_column(String(30), nullable=False)
    justification: Mapped[str] = mapped_column(Text, nullable=False)
    # Referencia de texto a evidencia (URL/ruta ya alojada en otro lado) — el MVP no
    # construye subsistema de carga de archivos propio para este módulo.
    evidence_reference: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    # pending | approved | rejected
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="pending")
    reviewed_by_user_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id"), nullable=True
    )
    reviewed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    review_notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))


class ShiftTemplate(Base):
    """Plantilla de turno recurrente por sucursal (mód. 13). El supervisor se
    hereda de Branch.supervisor_user_id (mód. 6) — no se duplica acá."""
    __tablename__ = "shift_templates"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    branch_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("branches.id"), nullable=False)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    start_time: Mapped[time] = mapped_column(Time, nullable=False)
    end_time: Mapped[time] = mapped_column(Time, nullable=False)
    # 0=lunes ... 6=domingo
    days_of_week: Mapped[list] = mapped_column(JSONB, nullable=False, default=list)
    min_coverage: Mapped[int] = mapped_column(nullable=False, default=1)
    active: Mapped[bool] = mapped_column(nullable=False, default=True, server_default=text("true"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))


class ShiftAssignment(Base):
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
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))
