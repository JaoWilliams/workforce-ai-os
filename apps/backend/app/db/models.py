import uuid
from sqlalchemy import text
from datetime import datetime, date, time
from typing import Optional

from sqlalchemy import DateTime, Date, Time, ForeignKey, String, Boolean, Numeric, UniqueConstraint, Text
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
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("now()"))


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
    employee_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("employees.id"), nullable=False)
    # consecutive_same_type | impossible_travel | missing_biometric
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
