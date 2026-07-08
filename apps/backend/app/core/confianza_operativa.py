"""
Motor de Confianza Operativa™ — versión heurística (mód. 17a).

Reglas SIN machine learning, evaluadas sobre AttendanceRecord real cada vez
que se registra una marcación nueva (no un rescan histórico completo, para
evitar reflaggear lo mismo una y otra vez). La versión con ML completo
(mód. 17/18) evoluciona esto más adelante, fuera del alcance del MVP.

Reglas implementadas:
- missing_biometric: la marcación nueva no tuvo verificación biométrica.
- consecutive_same_type: dos marcaciones seguidas del mismo tipo (entrada/
  entrada o salida/salida) sin su contraparte — típico de olvidar marcar
  salida o de un intento de marcación duplicada.
- impossible_travel: dos marcaciones en sucursales distintas con menos
  tiempo entre ellas del físicamente necesario para trasladarse (umbral
  configurable, ver Settings.confianza_impossible_travel_minutes).
"""
from datetime import timedelta
from typing import List
from uuid import UUID, uuid4

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.db.models import AttendanceRecord, Device, TrustFlag


def _build_flag(tenant_id: UUID, employee_id: UUID, rule_code: str, severity: str, details: dict) -> TrustFlag:
    return TrustFlag(
        id=uuid4(), tenant_id=tenant_id, employee_id=employee_id,
        rule_code=rule_code, severity=severity, details=details, resolved=False,
    )


async def evaluate_new_attendance_record(
    session: AsyncSession, tenant_id: UUID, employee_id: UUID,
    new_record: AttendanceRecord, new_branch_id: UUID,
) -> List[TrustFlag]:
    settings = get_settings()
    new_flags: List[TrustFlag] = []

    # Regla: ausencia de biometría en la marcación nueva
    if new_record.verification_method == "manual":
        new_flags.append(_build_flag(
            tenant_id, employee_id, "missing_biometric", "medium",
            {"attendance_record_id": str(new_record.id),
             "reason": "Marcación registrada sin verificación biométrica (método manual)"},
        ))

    # Buscar la marcación inmediatamente anterior (distinta de la nueva) para comparar
    prev_result = await session.execute(
        select(AttendanceRecord, Device.branch_id)
        .join(Device, Device.id == AttendanceRecord.device_id)
        .where(AttendanceRecord.employee_id == employee_id, AttendanceRecord.id != new_record.id)
        .order_by(AttendanceRecord.recorded_at.desc())
        .limit(1)
    )
    prev_row = prev_result.first()
    if prev_row is not None:
        prev_record, prev_branch_id = prev_row
        pair = sorted(
            [(prev_record, prev_branch_id), (new_record, new_branch_id)],
            key=lambda item: item[0].recorded_at,
        )
        (earlier_rec, earlier_branch), (later_rec, later_branch) = pair

        if earlier_rec.type == later_rec.type:
            new_flags.append(_build_flag(
                tenant_id, employee_id, "consecutive_same_type", "medium",
                {"attendance_record_ids": [str(earlier_rec.id), str(later_rec.id)],
                 "reason": f"Dos marcaciones de tipo '{later_rec.type}' seguidas, sin su contraparte entre medio"},
            ))

        if earlier_branch != later_branch:
            gap = later_rec.recorded_at - earlier_rec.recorded_at
            threshold = timedelta(minutes=settings.confianza_impossible_travel_minutes)
            if gap < threshold:
                gap_minutes = gap.total_seconds() / 60
                new_flags.append(_build_flag(
                    tenant_id, employee_id, "impossible_travel", "high",
                    {"attendance_record_ids": [str(earlier_rec.id), str(later_rec.id)],
                     "branch_ids": [str(earlier_branch), str(later_branch)],
                     "gap_minutes": round(gap_minutes, 1),
                     "threshold_minutes": settings.confianza_impossible_travel_minutes,
                     "reason": f"Marcó en dos sucursales distintas con solo {gap_minutes:.0f} min de diferencia"},
                ))

    for flag in new_flags:
        session.add(flag)
    return new_flags
