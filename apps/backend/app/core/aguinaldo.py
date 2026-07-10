"""
Aguinaldo (decimo tercer mes, Ley de Aguinaldo CR, Art. 1). Monto = suma de
todo lo devengado como salario (ordinario + extraordinario + cualquier otro
ingreso salarial ya reflejado en gross_pay via core/payroll.py: horas
extra, recargos de feriado, pago de vacaciones) durante la ventana legal
(AguinaldoConfig: 1 dic ano anterior a 30 nov ano actual, por defecto),
dividido entre el divisor configurado (12 por ley). Se paga en una planilla
dedicada, separada de la ordinaria - no se mezcla con gross_pay de ningun
PayrollPeriod existente. Sin deducciones de CCSS/renta (confirmado con el
usuario 2026-07-10).

Limitacion de alcance conocida: si el cliente tiene ingresos salariales
(comisiones, bonos) que NO pasan por este sistema de nomina, esos montos
NO se incluyen aqui - el sistema solo puede sumar lo que efectivamente
calcula via PayrollPeriod/compute_payroll_rows. No se asume ni se inventa
un monto adicional (usuario confirmo 2026-07-10 que el aguinaldo debe
incluir "comisiones y todo lo que se considere parte del salario" - eso
queda pendiente de que esos conceptos se carguen como PayrollConcept y
fluyan a gross_pay, o de un mecanismo de captura dedicado a futuro).

Nota (usuario 2026-07-10): el concepto de catalogo AGUINALDO (8.33%
patronal, modulo 6) es para la PROVISION contable mensual, no para este
calculo del pago real - se reconcilian en fase 9 (asientos contables).
"""
from datetime import date
from typing import Optional
from uuid import UUID

from sqlalchemy import select

from app.core.payroll import compute_payroll_rows
from app.db.models import AguinaldoConfig, Branch, Employee, PayrollPeriod


async def _get_aguinaldo_config(session) -> Optional[AguinaldoConfig]:
    result = await session.execute(select(AguinaldoConfig))
    return result.scalars().first()


def _window_for_year(config: AguinaldoConfig, year: int):
    start_year = year - 1 if config.period_start_month > config.period_end_month else year
    window_start = date(start_year, config.period_start_month, config.period_start_day)
    window_end = date(year, config.period_end_month, config.period_end_day)
    return window_start, window_end


async def compute_aguinaldo_rows(session, year: int, branch_id: Optional[UUID] = None) -> list:
    config = await _get_aguinaldo_config(session)

    query = select(Employee, Branch).join(Branch, Branch.id == Employee.branch_id).where(Employee.active.is_(True))
    if branch_id is not None:
        query = query.where(Employee.branch_id == branch_id)
    result = await session.execute(query)
    employees = result.all()

    rows = []
    if config is None:
        for emp, branch in employees:
            rows.append({
                "employee_id": emp.id, "employee_name": f"{emp.first_name} {emp.last_name}",
                "branch_id": branch.id, "branch_name": branch.name,
                "aguinaldo_base": None, "aguinaldo_amount": None,
                "periods_considered": 0, "partial_year": False, "config_missing": True,
            })
        return rows

    window_start, window_end = _window_for_year(config, year)
    divisor = float(config.divisor)

    period_result = await session.execute(
        select(PayrollPeriod).where(
            PayrollPeriod.period_start >= window_start,
            PayrollPeriod.period_end <= window_end,
        ).order_by(PayrollPeriod.period_start)
    )
    periods = period_result.scalars().all()

    gross_by_employee = {}
    days_by_employee = {}
    periods_by_employee = {}
    for period in periods:
        period_rows = await compute_payroll_rows(session, period.period_start, period.period_end, branch_id)
        for r in period_rows:
            if r.get("gross_pay") is None:
                continue
            emp_id = r["employee_id"]
            gross_by_employee[emp_id] = gross_by_employee.get(emp_id, 0.0) + r["gross_pay"]
            days_by_employee[emp_id] = days_by_employee.get(emp_id, 0) + (period.period_end - period.period_start).days + 1
            periods_by_employee[emp_id] = periods_by_employee.get(emp_id, 0) + 1

    window_days = (window_end - window_start).days + 1
    for emp, branch in employees:
        base = gross_by_employee.get(emp.id)
        days_covered = days_by_employee.get(emp.id, 0)
        n_periods = periods_by_employee.get(emp.id, 0)
        if base is None:
            rows.append({
                "employee_id": emp.id, "employee_name": f"{emp.first_name} {emp.last_name}",
                "branch_id": branch.id, "branch_name": branch.name,
                "aguinaldo_base": None, "aguinaldo_amount": None,
                "periods_considered": 0, "partial_year": False, "config_missing": False,
            })
            continue
        amount = round(base / divisor, 2)
        partial = days_covered < (window_days * 0.9)
        rows.append({
            "employee_id": emp.id, "employee_name": f"{emp.first_name} {emp.last_name}",
            "branch_id": branch.id, "branch_name": branch.name,
            "aguinaldo_base": round(base, 2), "aguinaldo_amount": amount,
            "periods_considered": n_periods, "partial_year": partial, "config_missing": False,
        })

    rows.sort(key=lambda x: x["employee_name"])
    return rows
