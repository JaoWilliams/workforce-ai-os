"""
Agregaciones de Business Intelligence de mano de obra para el Centro de
Analisis Gerencial (nivel CEO/gerencial). Lee EXCLUSIVAMENTE de fuentes ya
congeladas/autoritativas:
  - PayrollSnapshotLine (costo, horas extra - mismo dato que la boleta de
    pago, nunca recalculado en vivo).
  - AuditLog (accion "employee.updated" con "active" en el detalle) para
    reconstruir CUANDO un empleado paso a inactivo, ya que Employee no
    guarda una fecha de baja explicita - solo el booleano actual.
No agrega logica de negocio nueva de nomina; solo lee y suma lo que ya
existe.
"""
from collections import defaultdict
from datetime import date
from typing import Optional
from uuid import UUID

from sqlalchemy import select

from app.db.models import AuditLog, Branch, Department, Employee, PayrollPeriod, PayrollSnapshotLine


def _dept_name(departments_by_id, dept_id):
    if dept_id is None:
        return "Sin departamento"
    d = departments_by_id.get(dept_id)
    return d.name if d else "Sin departamento"


def _branch_name(branches_by_id, br_id):
    if br_id is None:
        return "Sin sucursal"
    b = branches_by_id.get(br_id)
    return b.name if b else "Sin sucursal"


async def compute_labor_analytics(
    session,
    tenant_id: UUID,
    start_date: date,
    end_date: date,
    branch_id: Optional[UUID] = None,
    department_id: Optional[UUID] = None,
) -> dict:
    employees_result = await session.execute(select(Employee).where(Employee.tenant_id == tenant_id))
    employees = employees_result.scalars().all()
    employees_by_id = {e.id: e for e in employees}

    departments_result = await session.execute(select(Department).where(Department.tenant_id == tenant_id))
    departments_by_id = {d.id: d for d in departments_result.scalars().all()}

    branches_result = await session.execute(select(Branch).where(Branch.tenant_id == tenant_id))
    branches_by_id = {b.id: b for b in branches_result.scalars().all()}

    periods_result = await session.execute(
        select(PayrollPeriod).where(
            PayrollPeriod.tenant_id == tenant_id,
            PayrollPeriod.period_start <= end_date,
            PayrollPeriod.period_end >= start_date,
        )
    )
    period_ids = [p.id for p in periods_result.scalars().all()]

    lines = []
    if period_ids:
        lines_result = await session.execute(
            select(PayrollSnapshotLine).where(PayrollSnapshotLine.payroll_period_id.in_(period_ids))
        )
        lines = lines_result.scalars().all()

    def line_matches_filters(line):
        emp = employees_by_id.get(line.employee_id)
        if branch_id is not None and line.branch_id != branch_id:
            return False
        if department_id is not None and (emp is None or emp.department_id != department_id):
            return False
        return True

    filtered_lines = [l for l in lines if line_matches_filters(l)]

    totals = {
        "total_gross_pay": 0.0,
        "total_net_pay": 0.0,
        "total_overtime_pay": 0.0,
        "total_overtime_hours": 0.0,
        "headcount": 0,
    }
    employees_seen = set()
    by_department = defaultdict(lambda: {
        "gross_pay": 0.0, "net_pay": 0.0, "overtime_pay": 0.0, "overtime_hours": 0.0,
        "employee_ids": set(),
    })
    by_branch = defaultdict(lambda: {
        "gross_pay": 0.0, "net_pay": 0.0, "overtime_pay": 0.0, "overtime_hours": 0.0,
        "employee_ids": set(),
    })
    by_employee_overtime = defaultdict(lambda: {"overtime_pay": 0.0, "overtime_hours": 0.0})

    for line in filtered_lines:
        emp = employees_by_id.get(line.employee_id)
        dept_id = emp.department_id if emp else None
        gross = float(line.gross_pay or 0)
        net = float(line.net_pay or 0)
        detail = line.detail or {}
        overtime_pay = float(detail.get("overtime_surcharge") or 0)
        overtime_hours = float(detail.get("overtime_extra_hours") or 0)

        totals["total_gross_pay"] += gross
        totals["total_net_pay"] += net
        totals["total_overtime_pay"] += overtime_pay
        totals["total_overtime_hours"] += overtime_hours
        employees_seen.add(line.employee_id)

        dep_bucket = by_department[dept_id]
        dep_bucket["gross_pay"] += gross
        dep_bucket["net_pay"] += net
        dep_bucket["overtime_pay"] += overtime_pay
        dep_bucket["overtime_hours"] += overtime_hours
        dep_bucket["employee_ids"].add(line.employee_id)

        br_bucket = by_branch[line.branch_id]
        br_bucket["gross_pay"] += gross
        br_bucket["net_pay"] += net
        br_bucket["overtime_pay"] += overtime_pay
        br_bucket["overtime_hours"] += overtime_hours
        br_bucket["employee_ids"].add(line.employee_id)

        emp_bucket = by_employee_overtime[line.employee_id]
        emp_bucket["overtime_pay"] += overtime_pay
        emp_bucket["overtime_hours"] += overtime_hours

    totals["headcount"] = len(employees_seen)
    totals["avg_cost_per_employee"] = (
        round(totals["total_gross_pay"] / totals["headcount"], 2) if totals["headcount"] else 0.0
    )

    department_rows = []
    for dept_id, bucket in by_department.items():
        headcount = len(bucket["employee_ids"])
        department_rows.append({
            "department_id": str(dept_id) if dept_id else None,
            "department_name": _dept_name(departments_by_id, dept_id),
            "gross_pay": round(bucket["gross_pay"], 2),
            "net_pay": round(bucket["net_pay"], 2),
            "overtime_pay": round(bucket["overtime_pay"], 2),
            "overtime_hours": round(bucket["overtime_hours"], 1),
            "headcount": headcount,
            "avg_cost_per_employee": round(bucket["gross_pay"] / headcount, 2) if headcount else 0.0,
        })

    branch_rows = []
    for br_id, bucket in by_branch.items():
        headcount = len(bucket["employee_ids"])
        branch_rows.append({
            "branch_id": str(br_id) if br_id else None,
            "branch_name": _branch_name(branches_by_id, br_id),
            "gross_pay": round(bucket["gross_pay"], 2),
            "net_pay": round(bucket["net_pay"], 2),
            "overtime_pay": round(bucket["overtime_pay"], 2),
            "overtime_hours": round(bucket["overtime_hours"], 1),
            "headcount": headcount,
            "avg_cost_per_employee": round(bucket["gross_pay"] / headcount, 2) if headcount else 0.0,
        })

    department_rows_by_cost = sorted(department_rows, key=lambda r: r["gross_pay"], reverse=True)
    top_departments_by_cost = department_rows_by_cost[:10]

    top_overtime_employees = []
    for emp_id, bucket in sorted(
        by_employee_overtime.items(), key=lambda kv: kv[1]["overtime_pay"], reverse=True
    )[:10]:
        emp = employees_by_id.get(emp_id)
        top_overtime_employees.append({
            "employee_id": str(emp_id),
            "employee_name": (emp.first_name + " " + emp.last_name) if emp else str(emp_id),
            "department_name": _dept_name(departments_by_id, emp.department_id if emp else None),
            "overtime_pay": round(bucket["overtime_pay"], 2),
            "overtime_hours": round(bucket["overtime_hours"], 1),
        })

    highest_cost_department = department_rows_by_cost[0] if department_rows_by_cost else None
    lowest_cost_department = department_rows_by_cost[-1] if department_rows_by_cost else None
    department_rows_by_overtime = sorted(department_rows, key=lambda r: r["overtime_hours"], reverse=True)
    most_overtime_department = department_rows_by_overtime[0] if department_rows_by_overtime else None
    least_overtime_department = department_rows_by_overtime[-1] if department_rows_by_overtime else None

    # ---------- rotacion de personal ----------
    audit_result = await session.execute(
        select(AuditLog).where(
            AuditLog.tenant_id == tenant_id,
            AuditLog.resource_type == "employee",
            AuditLog.action == "employee.updated",
        )
    )
    events_by_employee = defaultdict(list)
    for entry in audit_result.scalars().all():
        if entry.extra and "active" in entry.extra:
            events_by_employee[entry.resource_id].append((entry.created_at.date(), bool(entry.extra["active"])))
    for emp_id in events_by_employee:
        events_by_employee[emp_id].sort(key=lambda x: x[0])

    def active_as_of(emp, as_of_date):
        if emp.hire_date > as_of_date:
            return False
        events = events_by_employee.get(emp.id, [])
        if not events:
            return emp.active
        state = True
        for event_date, active_value in events:
            if event_date <= as_of_date:
                state = active_value
            else:
                break
        return state

    def employee_matches_scope(emp):
        if branch_id is not None and emp.branch_id != branch_id:
            return False
        if department_id is not None and emp.department_id != department_id:
            return False
        return True

    scoped_employees = [e for e in employees if employee_matches_scope(e)]

    def departed_in_range(emp):
        for event_date, active_value in events_by_employee.get(emp.id, []):
            if active_value is False and start_date <= event_date <= end_date:
                return True
        return False

    headcount_start = sum(1 for e in scoped_employees if active_as_of(e, start_date))
    headcount_end = sum(1 for e in scoped_employees if active_as_of(e, end_date))
    avg_headcount = (headcount_start + headcount_end) / 2

    hires = [e for e in scoped_employees if e.hire_date is not None and start_date <= e.hire_date <= end_date]
    departures = [e for e in scoped_employees if departed_in_range(e)]
    turnover_rate = round(len(departures) / avg_headcount * 100, 1) if avg_headcount else 0.0

    turnover_by_department = []
    dept_ids_in_scope = set(e.department_id for e in scoped_employees)
    for dept_id in dept_ids_in_scope:
        dept_employees = [e for e in scoped_employees if e.department_id == dept_id]
        d_start = sum(1 for e in dept_employees if active_as_of(e, start_date))
        d_end = sum(1 for e in dept_employees if active_as_of(e, end_date))
        d_avg = (d_start + d_end) / 2
        d_departures = sum(1 for e in dept_employees if departed_in_range(e))
        turnover_by_department.append({
            "department_id": str(dept_id) if dept_id else None,
            "department_name": _dept_name(departments_by_id, dept_id),
            "departures": d_departures,
            "avg_headcount": round(d_avg, 1),
            "turnover_rate": round(d_departures / d_avg * 100, 1) if d_avg else 0.0,
        })
    turnover_by_department.sort(key=lambda r: r["turnover_rate"], reverse=True)

    return {
        "range": {"start_date": start_date.isoformat(), "end_date": end_date.isoformat()},
        "totals": totals,
        "by_department": department_rows_by_cost,
        "by_branch": sorted(branch_rows, key=lambda r: r["gross_pay"], reverse=True),
        "top_departments_by_cost": top_departments_by_cost,
        "top_overtime_employees": top_overtime_employees,
        "highest_cost_department": highest_cost_department,
        "lowest_cost_department": lowest_cost_department,
        "most_overtime_department": most_overtime_department,
        "least_overtime_department": least_overtime_department,
        "turnover": {
            "hires": len(hires),
            "departures": len(departures),
            "avg_headcount": round(avg_headcount, 1),
            "turnover_rate_pct": turnover_rate,
            "by_department": turnover_by_department,
        },
    }
