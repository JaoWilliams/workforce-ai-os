"""
Feriados: catalogo parametrizable (Holiday) - fechas y tipo (obligatorio/no
obligatorio) cargadas por el cliente, cero fechas hardcodeadas. Ajusta el
bruto de nomina automaticamente (sin aprobacion de supervisor, a diferencia
de horas extra, porque es un hecho objetivo verificable contra el
catalogo - decision confirmada con el usuario 2026-07-10):

- Trabajado + obligatorio: recargo (factor del concepto
  FERIADO_OBLIGATORIO_TRABAJADO en PayrollConcept, parametrizable).
- Trabajado + no obligatorio: sin ajuste, ya se paga via horas normales.
- No trabajado + obligatorio + turno programado ese dia (el dia de la
  semana del feriado esta en ShiftTemplate.days_of_week del turno vigente):
  se paga como si hubiera trabajado (horas ordinarias del turno x tarifa
  normal, SIN recargo - el recargo es solo para cuando si se trabaja).
- No trabajado + no obligatorio, o sin turno programado ese dia: sin ajuste.
"""
from datetime import date
from typing import Optional
from uuid import UUID

from sqlalchemy import select

from app.core.overtime import _compute_daily_hours, _shift_duration_hours
from app.db.models import Holiday, ShiftAssignment, ShiftTemplate


async def compute_holiday_adjustments(
    session, employee_ids: list, start_date: date, end_date: date, branch_id: Optional[UUID] = None
):
    holidays_result = await session.execute(
        select(Holiday).where(
            Holiday.date >= start_date, Holiday.date <= end_date, Holiday.active.is_(True)
        )
    )
    holidays = holidays_result.scalars().all()
    if not holidays:
        return {}

    daily_hours = await _compute_daily_hours(session, start_date, end_date, branch_id)

    assignments_result = await session.execute(
        select(ShiftAssignment).where(ShiftAssignment.employee_id.in_(employee_ids))
    )
    by_employee_assignments = {}
    for a in assignments_result.scalars().all():
        by_employee_assignments.setdefault(a.employee_id, []).append(a)

    templates_result = await session.execute(select(ShiftTemplate))
    templates_by_id = {t.id: t for t in templates_result.scalars().all()}

    adjustments = {}
    for holiday in holidays:
        weekday = holiday.date.weekday()
        for employee_id in employee_ids:
            worked_hours = daily_hours.get((employee_id, holiday.date))

            candidates = [
                a for a in by_employee_assignments.get(employee_id, [])
                if a.start_date <= holiday.date and (a.end_date is None or a.end_date >= holiday.date)
            ]
            template = None
            if candidates:
                candidates.sort(key=lambda a: a.start_date, reverse=True)
                template = templates_by_id.get(candidates[0].shift_template_id)

            entry = adjustments.setdefault(employee_id, {
                "worked_surcharge_hours": 0.0, "unworked_paid_hours": 0.0, "details": [],
            })

            if worked_hours:
                if holiday.payment_type == "obligatorio":
                    entry["worked_surcharge_hours"] += worked_hours
                    entry["details"].append(
                        f"{holiday.date.isoformat()}: trabajado, feriado obligatorio ({holiday.name}), {worked_hours}h con recargo"
                    )
            else:
                if holiday.payment_type == "obligatorio" and template is not None and weekday in (template.days_of_week or []):
                    ordinary_hours = round(_shift_duration_hours(template.start_time, template.end_time), 2)
                    entry["unworked_paid_hours"] += ordinary_hours
                    entry["details"].append(
                        f"{holiday.date.isoformat()}: no trabajado, feriado obligatorio programado ({holiday.name}), {ordinary_hours}h pagadas"
                    )

    return adjustments
