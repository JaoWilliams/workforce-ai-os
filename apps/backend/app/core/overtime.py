"""
Horas extra: generacion de candidatas por dia contra la duracion real del
turno asignado (ShiftTemplate/ShiftAssignment, modulo 13) - no contra un
umbral fijo de horas por dia, porque cada turno puede tener su propia
duracion (algunos ya incluyen horas extra implicitas en su definicion).

Cada dia con horas trabajadas por encima de la duracion del turno asignado
queda como OvertimeApproval en estado "pending" hasta que un supervisor lo
aprueba o rechaza. compute_payroll_rows (core/payroll.py) bloquea el bruto
de un empleado mientras tenga horas extra pendientes de resolver en el
periodo (decision confirmada con el usuario 2026-07-10). Si un empleado no
tiene turno asignado ese dia, no se puede determinar si hubo horas extra:
ese dia queda en "skipped_unassigned", nunca se asume un umbral por defecto.
"""
from datetime import date, datetime, time, timezone
from typing import Optional
from uuid import UUID, uuid4

from sqlalchemy import select

from app.db.models import AttendanceRecord, Employee, OvertimeApproval, ShiftAssignment, ShiftTemplate


def _shift_duration_hours(start_time: time, end_time: time) -> float:
    start_seconds = start_time.hour * 3600 + start_time.minute * 60 + start_time.second
    end_seconds = end_time.hour * 3600 + end_time.minute * 60 + end_time.second
    if end_seconds <= start_seconds:
        end_seconds += 24 * 3600
    return (end_seconds - start_seconds) / 3600


async def _compute_daily_hours(session, start_date: date, end_date: date, branch_id: Optional[UUID] = None):
    start_dt = datetime.combine(start_date, time.min, tzinfo=timezone.utc)
    end_dt = datetime.combine(end_date, time.max, tzinfo=timezone.utc)
    query = (
        select(AttendanceRecord, Employee)
        .join(Employee, Employee.id == AttendanceRecord.employee_id)
        .where(AttendanceRecord.recorded_at >= start_dt, AttendanceRecord.recorded_at <= end_dt)
        .order_by(Employee.id, AttendanceRecord.recorded_at)
    )
    if branch_id is not None:
        query = query.where(Employee.branch_id == branch_id)
    result = await session.execute(query)
    rows = result.all()

    by_employee = {}
    for record, employee in rows:
        by_employee.setdefault(employee.id, []).append(record)

    daily_hours = {}
    for employee_id, records in by_employee.items():
        pending_entrada = None
        for r in records:
            if r.type == "entrada":
                pending_entrada = r
            elif r.type == "salida" and pending_entrada is not None:
                delta = (r.recorded_at - pending_entrada.recorded_at).total_seconds()
                if delta > 0:
                    work_date = pending_entrada.recorded_at.date()
                    key = (employee_id, work_date)
                    daily_hours[key] = daily_hours.get(key, 0.0) + delta / 3600
                pending_entrada = None
    return daily_hours


async def generate_overtime_candidates(
    session, tenant_id: UUID, start_date: date, end_date: date, branch_id: Optional[UUID] = None
):
    daily_hours = await _compute_daily_hours(session, start_date, end_date, branch_id)
    if not daily_hours:
        return {"created": 0, "updated": 0, "skipped_unassigned": []}

    employee_ids = list({eid for (eid, _) in daily_hours.keys()})

    assignments_result = await session.execute(
        select(ShiftAssignment).where(ShiftAssignment.employee_id.in_(employee_ids))
    )
    by_employee_assignments = {}
    for a in assignments_result.scalars().all():
        by_employee_assignments.setdefault(a.employee_id, []).append(a)

    templates_result = await session.execute(select(ShiftTemplate))
    templates_by_id = {t.id: t for t in templates_result.scalars().all()}

    existing_result = await session.execute(
        select(OvertimeApproval).where(
            OvertimeApproval.employee_id.in_(employee_ids),
            OvertimeApproval.work_date >= start_date,
            OvertimeApproval.work_date <= end_date,
        )
    )
    existing_by_key = {(o.employee_id, o.work_date): o for o in existing_result.scalars().all()}

    created = 0
    updated = 0
    skipped_unassigned = []

    for (employee_id, work_date), worked_hours in daily_hours.items():
        candidates = [
            a for a in by_employee_assignments.get(employee_id, [])
            if a.start_date <= work_date and (a.end_date is None or a.end_date >= work_date)
        ]
        if not candidates:
            skipped_unassigned.append({"employee_id": str(employee_id), "work_date": work_date.isoformat()})
            continue
        candidates.sort(key=lambda a: a.start_date, reverse=True)
        template = templates_by_id.get(candidates[0].shift_template_id)
        if template is None:
            skipped_unassigned.append({"employee_id": str(employee_id), "work_date": work_date.isoformat()})
            continue

        shift_duration = _shift_duration_hours(template.start_time, template.end_time)
        if worked_hours <= shift_duration:
            continue

        ordinary_hours = round(shift_duration, 2)
        extra_hours = round(worked_hours - shift_duration, 2)

        key = (employee_id, work_date)
        existing = existing_by_key.get(key)
        if existing is None:
            record = OvertimeApproval(
                id=uuid4(), tenant_id=tenant_id, employee_id=employee_id,
                shift_template_id=template.id, work_date=work_date,
                ordinary_hours=ordinary_hours, extra_hours=extra_hours, status="pending",
            )
            session.add(record)
            created += 1
        elif existing.status == "pending":
            existing.shift_template_id = template.id
            existing.ordinary_hours = ordinary_hours
            existing.extra_hours = extra_hours
            updated += 1
        # si ya esta approved/rejected, no se toca - decision ya tomada por un supervisor

    await session.commit()
    return {"created": created, "updated": updated, "skipped_unassigned": skipped_unassigned}
