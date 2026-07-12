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
