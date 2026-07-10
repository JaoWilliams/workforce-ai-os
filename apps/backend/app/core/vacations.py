"""
Vacaciones (Codigo de Trabajo CR, Art. 153, 155, 156, 157, 159 - ver
"Calculo de Vacaciones.docx" cargado por el cliente 2026-07-10).

Regla legal: 2 semanas de derecho por cada `cycle_weeks` (config, valor
legal confirmado = 50) semanas de trabajo continuo. La conversion a DIAS
administrativos depende de la jornada real del empleado (turno asignado,
ShiftTemplate.days_of_week) - un 6x1 acumula 12 dias/ciclo, un 5x2 acumula
10, un 4x3 acumula 8 (siempre 2 x dias_laborables_semana). Cero valores
quemados: no se asume "12 dias para todos", se deriva del turno real
(decision confirmada con el usuario 2026-07-10).

Pago (Art. 157): promedio de salario ordinario + extraordinario (incluye
horas extra y recargos de feriado, ya que estan sumados en gross_pay por
core/payroll.py) sobre el historial disponible, con ventana objetivo de
`cycle_weeks` semanas. Si el empleado tiene menos historial que eso, se
promedia lo disponible y se marca `partial_history=True` (decision
confirmada con el usuario: no bloquear, pero avisar). Salario diario
promedio = suma de gross_pay de los periodos considerados / suma de dias
calendario de esos periodos - generaliza el divisor/30 del documento a
frecuencias de pago mixtas (mensual + quincenal conviviendo).

Solicitudes de vacaciones requieren aprobacion de supervisor antes de
contar en el pago de nomina (mismo patron que OvertimeApproval): una
solicitud "pending" que se traslape con el periodo bloquea el bruto de
ese empleado en ese periodo.

Nota: al igual que core/holidays.py, estas funciones NO reciben tenant_id
- la sesion ya viene scopeada por RLS via tenant_session(), asi que
select(VacationConfig) etc. ya devuelve solo las filas del tenant correcto.
"""
from datetime import date, timedelta
from typing import Optional
from uuid import UUID

from sqlalchemy import select

from app.db.models import Contract, PayrollPeriod, ShiftAssignment, ShiftTemplate, VacationConfig, VacationRequest


async def _get_shift_days_of_week(session, employee_id: UUID, as_of_date: date) -> Optional[list]:
    result = await session.execute(
        select(ShiftTemplate.days_of_week)
        .join(ShiftAssignment, ShiftAssignment.shift_template_id == ShiftTemplate.id)
        .where(
            ShiftAssignment.employee_id == employee_id,
            ShiftAssignment.start_date <= as_of_date,
            (ShiftAssignment.end_date.is_(None)) | (ShiftAssignment.end_date >= as_of_date),
        )
        .order_by(ShiftAssignment.start_date.desc())
        .limit(1)
    )
    return result.scalar_one_or_none()


def count_business_days(start_date: date, end_date: date, days_of_week: list) -> int:
    """Cuenta cuantos dias del rango [start_date, end_date] caen en un dia
    laborable segun days_of_week (0=lunes...6=domingo, igual convencion que
    ShiftTemplate y date.weekday())."""
    days_set = set(int(d) for d in days_of_week)
    count = 0
    d = start_date
    while d <= end_date:
        if d.weekday() in days_set:
            count += 1
        d += timedelta(days=1)
    return count


async def compute_request_days_count(session, employee_id: UUID, start_date: date, end_date: date) -> Optional[float]:
    """Dias laborables (segun el turno del empleado a la fecha de inicio)
    dentro del rango solicitado - usado al crear una VacationRequest."""
    shift_days = await _get_shift_days_of_week(session, employee_id, start_date)
    if not shift_days:
        return None
    return float(count_business_days(start_date, end_date, shift_days))


async def _get_vacation_config(session) -> Optional[VacationConfig]:
    result = await session.execute(select(VacationConfig))
    return result.scalars().first()


async def compute_vacation_balance(session, employee_id: UUID, as_of_date: date) -> dict:
    config = await _get_vacation_config(session)
    if config is None:
        return {"blocked": True, "reason": "vacation_config_missing"}

    contract_result = await session.execute(
        select(Contract).where(Contract.employee_id == employee_id).order_by(Contract.start_date.desc())
    )
    contract = contract_result.scalars().first()
    if contract is None:
        return {"blocked": True, "reason": "no_contract"}

    shift_days = await _get_shift_days_of_week(session, employee_id, as_of_date)
    if not shift_days:
        return {"blocked": True, "reason": "no_shift_assigned"}

    cycle_weeks = float(config.cycle_weeks)
    accrual_days_per_cycle = 2 * len(shift_days)
    weeks_worked = max(0.0, (as_of_date - contract.start_date).days / 7)
    accrued_days = round(weeks_worked * (accrual_days_per_cycle / cycle_weeks), 2)

    taken_result = await session.execute(
        select(VacationRequest).where(VacationRequest.employee_id == employee_id, VacationRequest.status == "approved")
    )
    taken_days = round(sum(float(r.days_count) for r in taken_result.scalars().all()), 2)

    pending_result = await session.execute(
        select(VacationRequest).where(VacationRequest.employee_id == employee_id, VacationRequest.status == "pending")
    )
    pending_days = round(sum(float(r.days_count) for r in pending_result.scalars().all()), 2)

    return {
        "blocked": False,
        "accrued_days": accrued_days,
        "taken_days": taken_days,
        "pending_days": pending_days,
        "available_days": round(accrued_days - taken_days, 2),
        "days_per_week_worked": len(shift_days),
        "cycle_weeks": cycle_weeks,
    }


async def compute_vacation_daily_rate(session, employee_id: UUID, as_of_date: date, cycle_weeks: float, branch_id: Optional[UUID] = None):
    """Salario diario promedio (Art. 157) sobre los periodos de planilla ya
    cerrados/calculados antes de as_of_date, ventana objetivo cycle_weeks
    semanas. Devuelve (daily_rate, partial_history, days_covered).
    Import local de compute_payroll_rows para evitar ciclo de imports
    (core/payroll.py importa compute_vacation_adjustments de este archivo)."""
    from app.core.payroll import compute_payroll_rows
    window_start = as_of_date - timedelta(days=int(cycle_weeks * 7))
    result = await session.execute(
        select(PayrollPeriod)
        .where(PayrollPeriod.period_end < as_of_date, PayrollPeriod.period_end >= window_start)
        .order_by(PayrollPeriod.period_start)
    )
    periods = result.scalars().all()

    total_gross = 0.0
    total_days = 0
    for period in periods:
        rows = await compute_payroll_rows(session, period.period_start, period.period_end, branch_id)
        row = next((r for r in rows if r["employee_id"] == employee_id), None)
        if row is None or row.get("gross_pay") is None:
            continue
        total_gross += row["gross_pay"]
        total_days += (period.period_end - period.period_start).days + 1

    if total_days == 0:
        return None, True, 0

    daily_rate = round(total_gross / total_days, 2)
    partial_history = total_days < int(cycle_weeks * 7)
    return daily_rate, partial_history, total_days


async def compute_vacation_adjustments(session, employee_ids: list, start_date: date, end_date: date, branch_id: Optional[UUID] = None) -> dict:
    """Para cada employee_id: revisa VacationRequest que se traslapen con
    [start_date, end_date]. pending -> bloquea (vacation_pending=True).
    approved -> suma vacation_pay usando el promedio de salario (Art. 157)."""
    config = await _get_vacation_config(session)
    cycle_weeks = float(config.cycle_weeks) if config is not None else None

    result = await session.execute(
        select(VacationRequest).where(
            VacationRequest.employee_id.in_(employee_ids),
            VacationRequest.start_date <= end_date,
            VacationRequest.end_date >= start_date,
        )
    )
    requests = result.scalars().all()

    adjustments = {}
    for req in requests:
        adj = adjustments.setdefault(req.employee_id, {
            "vacation_pay": 0.0, "vacation_pending": False,
            "vacation_no_history": False, "vacation_partial_history": False,
        })
        if req.status == "pending":
            adj["vacation_pending"] = True
            continue
        if req.status != "approved":
            continue

        overlap_start = max(req.start_date, start_date)
        overlap_end = min(req.end_date, end_date)
        shift_days = await _get_shift_days_of_week(session, req.employee_id, req.start_date)
        days_in_period = count_business_days(overlap_start, overlap_end, shift_days) if shift_days else 0
        if days_in_period == 0:
            continue

        if cycle_weeks is None:
            adj["vacation_no_history"] = True
            continue
        daily_rate, partial, _covered = await compute_vacation_daily_rate(
            session, req.employee_id, req.start_date, cycle_weeks, branch_id
        )
        if daily_rate is None:
            adj["vacation_no_history"] = True
            continue
        adj["vacation_pay"] = round(adj["vacation_pay"] + days_in_period * daily_rate, 2)
        adj["vacation_partial_history"] = adj["vacation_partial_history"] or partial

    return adjustments
