"""
Fase 11 (Orquestacion y auto-validacion) - Test end-to-end.
Corre DENTRO del contenedor api. Copiar con:
    docker compose cp test_payroll_run_e2e.py api:/app/test_payroll_run_e2e.py
    docker compose exec -T api python3 test_payroll_run_e2e.py

Ver docstring de la v1 (mismas 14 stages). v2 corrige el manejo de
persist_journal_entry (tupla (entry, error), no dict; no comitea
solo) y agrega limpieza previa idempotente al arranque.
"""
import asyncio
from datetime import date
from uuid import UUID, uuid4

from fastapi import HTTPException
from sqlalchemy import delete, select

from app.core.tenant import tenant_session
from app.db.models import (
    BankTransferFile,
    BankTransferFileLine,
    Branch,
    ChartOfAccount,
    Employee,
    JournalEntry,
    JournalEntryLine,
    PayrollAnomalyConfig,
    PayrollPeriod,
    PayrollSnapshotLine,
    Termination,
    TrustFlag,
    User,
)
import app.core.renta as renta_mod
from app.core.accounting import generate_payroll_journal_entry, persist_journal_entry
from app.core.payroll_run import get_net_payroll_rows_for_period
from app.modules.catalogs.router import (
    create_chart_of_account,
    list_chart_of_accounts,
    upsert_payroll_anomaly_config,
    get_payroll_anomaly_config,
)
from app.modules.catalogs.schemas import ChartOfAccountCreate, PayrollAnomalyConfigUpsert
from app.modules.employees.router import create_employee, update_employee
from app.modules.employees.schemas import EmployeeCreate, EmployeeUpdate
from app.modules.payroll.router import update_period_status, get_period_snapshot
from app.modules.payroll.schemas import PayrollPeriodStatusUpdate
from app.modules.bank_file.router import generate_bank_transfer_file
from app.modules.confianza_operativa.router import list_flags, resolve_flag
from app.modules.confianza_operativa.schemas import TrustFlagResolve

TENANT_ID = UUID("a7bacc80-f8d9-471f-bb96-b546581184a8")
ADMIN_USER_ID = UUID("b3aa36ab-fa6c-4374-b17d-c5d55b93a789")
BRANCH_CARTAGO = UUID("8819bfff-cb86-418b-8d61-50e92ff01579")
BRANCH_HEREDIA = UUID("59d9595d-31c3-4939-8d12-2eff71ad434d")
MARKER = "TEST_PAYROLLRUN_DELETE_ME"

PASS = []
FAIL = []


def check(label, condition, detail=""):
    if condition:
        PASS.append(label)
        print(f"  OK   {label}")
    else:
        FAIL.append(label)
        print(f"  FAIL {label}  {detail}")


async def get_admin_user():
    async with tenant_session(TENANT_ID) as session:
        user = await session.get(User, ADMIN_USER_ID)
        _ = user.id, user.tenant_id
        return user


async def cleanup_test_data():
    """Borra todo lo transaccional marcado. Idempotente - se puede
    llamar tanto antes (por si quedo basura de una corrida cortada)
    como despues del test."""
    async with tenant_session(TENANT_ID) as session:
        period_ids_result = await session.execute(select(PayrollPeriod.id).where(PayrollPeriod.notes == MARKER))
        period_ids = [row[0] for row in period_ids_result.all()]
        emp_ids_result = await session.execute(select(Employee.id).where(Employee.position == MARKER))
        emp_ids = [row[0] for row in emp_ids_result.all()]

        if period_ids:
            await session.execute(delete(TrustFlag).where(TrustFlag.payroll_period_id.in_(period_ids)))
            await session.execute(delete(PayrollSnapshotLine).where(PayrollSnapshotLine.payroll_period_id.in_(period_ids)))
            await session.execute(delete(BankTransferFileLine).where(BankTransferFileLine.tenant_id == TENANT_ID, BankTransferFileLine.bank_transfer_file_id.in_(
                select(BankTransferFile.id).where(BankTransferFile.payroll_period_id.in_(period_ids))
            )))
            await session.execute(delete(BankTransferFile).where(BankTransferFile.payroll_period_id.in_(period_ids)))
            await session.execute(delete(JournalEntryLine).where(JournalEntryLine.tenant_id == TENANT_ID, JournalEntryLine.journal_entry_id.in_(
                select(JournalEntry.id).where(JournalEntry.payroll_period_id.in_(period_ids))
            )))
            await session.execute(delete(JournalEntry).where(JournalEntry.payroll_period_id.in_(period_ids)))
        if emp_ids:
            await session.execute(delete(Termination).where(Termination.employee_id.in_(emp_ids)))
        await session.execute(delete(Employee).where(Employee.position == MARKER))
        await session.execute(delete(PayrollPeriod).where(PayrollPeriod.notes == MARKER))
        await session.commit()


async def main():
    admin = await get_admin_user()

    print("=== LIMPIEZA PREVIA (por si quedo basura de una corrida anterior cortada) ===")
    await cleanup_test_data()
    print("OK")

    print("\n=== STAGE A: setup (empleados, terminacion, cuenta Heredia, config de anomalias) ===")
    emp1 = await create_employee(
        EmployeeCreate(branch_id=BRANCH_CARTAGO, first_name="Test", last_name="RunUno",
                        id_type="cedula_fisica", id_number="TEST-PAYRUN-001",
                        position=MARKER, hire_date=date(2024, 1, 1)),
        current_user=admin, locale="es",
    )
    emp2 = await create_employee(
        EmployeeCreate(branch_id=BRANCH_HEREDIA, first_name="Test", last_name="RunDos",
                        id_type="cedula_fisica", id_number="TEST-PAYRUN-002",
                        position=MARKER, hire_date=date(2024, 1, 1)),
        current_user=admin, locale="es",
    )
    emp3 = await create_employee(
        EmployeeCreate(branch_id=BRANCH_CARTAGO, first_name="Test", last_name="RunTres",
                        id_type="cedula_fisica", id_number="TEST-PAYRUN-003",
                        position=MARKER, hire_date=date(2024, 1, 1)),
        current_user=admin, locale="es",
    )
    emp4 = await create_employee(
        EmployeeCreate(branch_id=BRANCH_HEREDIA, first_name="Test", last_name="RunCuatro",
                        id_type="cedula_fisica", id_number="TEST-PAYRUN-004",
                        position=MARKER, hire_date=date(2024, 1, 1)),
        current_user=admin, locale="es",
    )
    for emp, acc_num in ((emp1, "16001590001"), (emp2, "16001590002"), (emp3, "16001590003"), (emp4, "16001590004")):
        await update_employee(emp.id, EmployeeUpdate(bank_account_type="Cuenta de Ahorro", bank_account_number=acc_num), current_user=admin, locale="es")

    async with tenant_session(TENANT_ID) as session:
        term = Termination(
            id=uuid4(), tenant_id=TENANT_ID, employee_id=emp4.id, termination_date=date(2026, 6, 15),
            cause=MARKER, con_responsabilidad_patronal=False, status="approved",
            reviewed_by=admin.id, notes=MARKER,
        )
        session.add(term)
        await session.commit()
    check("Termination aprobada creada para emp4", True)

    try:
        heredia_account = await create_chart_of_account(
            ChartOfAccountCreate(code="GASTO-PLANILLA-HEREDIA", name="Gasto de planilla - BK Heredia", account_type="gasto"),
            current_user=admin, locale="es",
        )
    except HTTPException as e:
        if e.status_code == 400:
            existing = await list_chart_of_accounts(current_user=admin)
            heredia_account = next(a for a in existing if a.code == "GASTO-PLANILLA-HEREDIA")
        else:
            raise
    async with tenant_session(TENANT_ID) as session:
        branch = await session.get(Branch, BRANCH_HEREDIA)
        branch.accounting_account = "GASTO-PLANILLA-HEREDIA"
        await session.commit()
    check("Branch BK-Heredia.accounting_account configurado", True)

    anomaly_config = await upsert_payroll_anomaly_config(
        PayrollAnomalyConfigUpsert(
            net_deviation_pct_threshold=30.0, overtime_hours_multiplier_threshold=2.0,
            bank_account_change_window_days=5, branch_net_deviation_pct_threshold=30.0,
        ),
        current_user=admin,
    )
    check("PayrollAnomalyConfig guardado", anomaly_config.net_deviation_pct_threshold == 30.0)
    fetched_config = await get_payroll_anomaly_config(current_user=admin)
    check("GET payroll-anomaly-config devuelve lo guardado", fetched_config is not None and fetched_config.bank_account_change_window_days == 5)

    print("\n=== STAGE B: crear periodos de prueba ===")
    async with tenant_session(TENANT_ID) as session:
        period_prev = PayrollPeriod(id=uuid4(), tenant_id=TENANT_ID, pay_frequency="mensual", period_start=date(2026, 5, 1), period_end=date(2026, 5, 31), status="draft", notes=MARKER)
        period_curr = PayrollPeriod(id=uuid4(), tenant_id=TENANT_ID, pay_frequency="mensual", period_start=date(2026, 6, 1), period_end=date(2026, 6, 30), status="draft", notes=MARKER)
        period_blocked = PayrollPeriod(id=uuid4(), tenant_id=TENANT_ID, pay_frequency="mensual", period_start=date(2026, 4, 1), period_end=date(2026, 4, 30), status="draft", notes=MARKER)
        period_novalidate = PayrollPeriod(id=uuid4(), tenant_id=TENANT_ID, pay_frequency="mensual", period_start=date(2099, 1, 1), period_end=date(2099, 1, 31), status="draft", notes=MARKER)
        period_skip = PayrollPeriod(id=uuid4(), tenant_id=TENANT_ID, pay_frequency="mensual", period_start=date(2026, 3, 1), period_end=date(2026, 3, 31), status="draft", notes=MARKER)
        for p in (period_prev, period_curr, period_blocked, period_novalidate, period_skip):
            session.add(p)
        await session.commit()
        for p in (period_prev, period_curr, period_blocked, period_novalidate, period_skip):
            await session.refresh(p)

    print("\n=== STAGE C: periodo baseline (mayo) -> calculado ===")
    fake_rows_prev = [
        {"employee_id": emp1.id, "net_pay": 500000.00, "gross_pay": 550000.00, "branch_id": BRANCH_CARTAGO, "ccss_deduction": 30000.00, "renta_amount": 20000.00, "renta_is_refund": False, "overtime_extra_hours": 2},
        {"employee_id": emp2.id, "net_pay": 500000.00, "gross_pay": 550000.00, "branch_id": BRANCH_HEREDIA, "ccss_deduction": 30000.00, "renta_amount": 20000.00, "renta_is_refund": False, "overtime_extra_hours": 2},
    ]

    async def fake_prev(session, tenant_id, period, branch_id=None):
        return fake_rows_prev

    renta_mod.compute_net_payroll_rows = fake_prev

    r1 = await update_period_status(period_prev.id, PayrollPeriodStatusUpdate(status="validado"), current_user=admin, locale="es")
    check("periodo baseline -> validado", r1.status == "validado", f"got={r1.status}")
    r2 = await update_period_status(period_prev.id, PayrollPeriodStatusUpdate(status="calculado"), current_user=admin, locale="es")
    check("periodo baseline -> calculado", r2.status == "calculado", f"got={r2.status}")

    async with tenant_session(TENANT_ID) as session:
        prev_lines = (await session.execute(select(PayrollSnapshotLine).where(PayrollSnapshotLine.payroll_period_id == period_prev.id))).scalars().all()
    check("snapshot baseline tiene 2 lineas", len(prev_lines) == 2, f"got={len(prev_lines)}")

    print("\n=== STAGE D-E: periodo actual (junio) -> validado -> calculado ===")
    fake_rows_curr = [
        {"employee_id": emp1.id, "net_pay": 900000.00, "gross_pay": 1000000.00, "branch_id": BRANCH_CARTAGO, "ccss_deduction": 60000.00, "renta_amount": 40000.00, "renta_is_refund": False, "overtime_extra_hours": 2},
        {"employee_id": emp2.id, "net_pay": 300000.00, "gross_pay": 350000.00, "branch_id": BRANCH_HEREDIA, "ccss_deduction": 30000.00, "renta_amount": 20000.00, "renta_is_refund": False, "overtime_extra_hours": 20},
        {"employee_id": emp3.id, "net_pay": 0.00, "gross_pay": 100000.00, "branch_id": BRANCH_CARTAGO, "ccss_deduction": 100000.00, "renta_amount": 0.00, "renta_is_refund": False, "overtime_extra_hours": 0},
        {"employee_id": emp4.id, "net_pay": 250000.00, "gross_pay": 280000.00, "branch_id": BRANCH_HEREDIA, "ccss_deduction": 20000.00, "renta_amount": 10000.00, "renta_is_refund": False, "overtime_extra_hours": 0},
    ]

    async def fake_curr(session, tenant_id, period, branch_id=None):
        return fake_rows_curr

    renta_mod.compute_net_payroll_rows = fake_curr

    try:
        await update_period_status(period_curr.id, PayrollPeriodStatusUpdate(status="calculado"), current_user=admin, locale="es")
        check("saltar validado -> debe fallar", False, "no lanzo excepcion")
    except HTTPException as e:
        check("draft -> calculado directo (sin pasar por validado) bloqueado", e.status_code == 400 and e.detail.get("error") == "invalid_transition", f"detail={e.detail}")

    r3 = await update_period_status(period_curr.id, PayrollPeriodStatusUpdate(status="validado"), current_user=admin, locale="es")
    check("periodo actual -> validado", r3.status == "validado", f"got={r3.status}")
    r4 = await update_period_status(period_curr.id, PayrollPeriodStatusUpdate(status="calculado"), current_user=admin, locale="es")
    check("periodo actual -> calculado", r4.status == "calculado", f"got={r4.status}")

    async with tenant_session(TENANT_ID) as session:
        curr_lines = (await session.execute(select(PayrollSnapshotLine).where(PayrollSnapshotLine.payroll_period_id == period_curr.id))).scalars().all()
    check("snapshot actual tiene 4 lineas", len(curr_lines) == 4, f"got={len(curr_lines)}")

    async with tenant_session(TENANT_ID) as session:
        flags_result = await session.execute(select(TrustFlag).where(TrustFlag.payroll_period_id == period_curr.id))
        flags = flags_result.scalars().all()
    rule_codes = {f.rule_code for f in flags}
    check("regla payroll_net_deviation disparo", "payroll_net_deviation" in rule_codes, f"reglas={rule_codes}")
    check("regla payroll_net_zero_or_negative disparo", "payroll_net_zero_or_negative" in rule_codes, f"reglas={rule_codes}")
    check("regla payroll_overtime_outlier disparo", "payroll_overtime_outlier" in rule_codes, f"reglas={rule_codes}")
    check("regla payroll_paid_after_termination disparo", "payroll_paid_after_termination" in rule_codes, f"reglas={rule_codes}")
    check("regla payroll_branch_net_outlier disparo", "payroll_branch_net_outlier" in rule_codes, f"reglas={rule_codes}")

    print("\n=== STAGE F: bloqueo 'aprobado' hasta resolver flags ===")
    try:
        await update_period_status(period_curr.id, PayrollPeriodStatusUpdate(status="aprobado"), current_user=admin, locale="es")
        check("aprobado con flags sin resolver -> debe fallar", False, "no lanzo excepcion")
    except HTTPException as e:
        check("aprobado bloqueado por flags sin resolver", e.status_code == 400 and e.detail.get("error") == "unresolved_flags", f"detail={e.detail}")

    open_flags = await list_flags(payroll_period_id=period_curr.id, resolved=False, current_user=admin)
    for f in open_flags:
        await resolve_flag(f.id, TrustFlagResolve(resolved=True), current_user=admin, locale="es")
    check(f"{len(open_flags)} flags resueltos", len(open_flags) >= 5, f"got={len(open_flags)}")

    r5 = await update_period_status(period_curr.id, PayrollPeriodStatusUpdate(status="aprobado"), current_user=admin, locale="es")
    check("periodo actual -> aprobado (tras resolver flags)", r5.status == "aprobado", f"got={r5.status}")

    print("\n=== STAGE G: 'pagado' ===")
    r6 = await update_period_status(period_curr.id, PayrollPeriodStatusUpdate(status="pagado"), current_user=admin, locale="es")
    check("periodo actual -> pagado", r6.status == "pagado", f"got={r6.status}")

    print("\n=== STAGE H: inmutabilidad + bloqueo 'contabilizado' ===")
    async def fake_curr_CHANGED(session, tenant_id, period, branch_id=None):
        return [{"employee_id": emp1.id, "net_pay": 1.00, "gross_pay": 1.00, "branch_id": BRANCH_CARTAGO, "ccss_deduction": 0.0, "renta_amount": 0.0, "renta_is_refund": False, "overtime_extra_hours": 0}]

    renta_mod.compute_net_payroll_rows = fake_curr_CHANGED

    async with tenant_session(TENANT_ID) as session:
        rows_after_change = await get_net_payroll_rows_for_period(session, TENANT_ID, period_curr, None)
    total_net_after_change = sum(r["net_pay"] for r in rows_after_change if r.get("net_pay") is not None)
    check("snapshot inmutable: el neto total sigue siendo el original (1,450,000) pese al monkeypatch cambiado",
          abs(total_net_after_change - 1450000.00) < 0.01, f"got={total_net_after_change}")

    try:
        await update_period_status(period_curr.id, PayrollPeriodStatusUpdate(status="contabilizado"), current_user=admin, locale="es")
        check("contabilizado sin asiento -> debe fallar", False, "no lanzo excepcion")
    except HTTPException as e:
        check("contabilizado bloqueado sin asiento contable", e.status_code == 400 and e.detail.get("error") == "accounting_entry_missing", f"detail={e.detail}")

    async with tenant_session(TENANT_ID) as session:
        entry_result = await generate_payroll_journal_entry(session, TENANT_ID, period_curr.id, None)
        check("generate_payroll_journal_entry usa el snapshot original (sin error)", entry_result.get("error") is None, f"got={entry_result}")
        total_debit = sum(l["debit"] for l in entry_result.get("lines", []))
        check("asiento contable usa el bruto ORIGINAL (1,730,000), no el monkeypatch cambiado",
              abs(total_debit - 1730000.00) < 0.01, f"got={total_debit}")
        entry_obj, persist_error = await persist_journal_entry(session, TENANT_ID, entry_result, admin.id)
        check("asiento de planilla persistido", entry_obj is not None and persist_error is None, f"error={persist_error}")
        await session.commit()

    r7 = await update_period_status(period_curr.id, PayrollPeriodStatusUpdate(status="contabilizado"), current_user=admin, locale="es")
    check("periodo actual -> contabilizado (tras generar asiento)", r7.status == "contabilizado", f"got={r7.status}")

    print("\n=== STAGE I: cuenta bancaria cambiada + archivo bancario ===")
    await update_employee(emp1.id, EmployeeUpdate(bank_account_number="16001599999"), current_user=admin, locale="es")

    try:
        await update_period_status(period_curr.id, PayrollPeriodStatusUpdate(status="archivo_bancario"), current_user=admin, locale="es")
        check("archivo_bancario sin archivo -> debe fallar", False, "no lanzo excepcion")
    except HTTPException as e:
        check("archivo_bancario bloqueado sin BankTransferFile", e.status_code == 400 and e.detail.get("error") == "bank_file_missing", f"detail={e.detail}")

    bank_file_resp = await generate_bank_transfer_file(period_curr.id, None, current_user=admin, locale="es")
    # emp3 tiene neto=0 en el snapshot -> bank_file.py lo excluye a proposito
    # (regla zero_or_negative_net_pay, fase 10) -> quedan 3 filas validas, no 4.
    check("archivo bancario generado usando el snapshot (3 filas, emp3 excluido por neto=0)", bank_file_resp.row_count == 3, f"got={bank_file_resp.row_count}")
    check("archivo bancario: total correcto (neto original 1,450,000)", abs(bank_file_resp.total_amount - 1450000.00) < 0.01, f"got={bank_file_resp.total_amount}")

    r8 = await update_period_status(period_curr.id, PayrollPeriodStatusUpdate(status="archivo_bancario"), current_user=admin, locale="es")
    check("periodo actual -> archivo_bancario", r8.status == "archivo_bancario", f"got={r8.status}")

    async with tenant_session(TENANT_ID) as session:
        bank_flags_result = await session.execute(select(TrustFlag).where(
            TrustFlag.payroll_period_id == period_curr.id, TrustFlag.rule_code == "payroll_bank_account_changed_before_payment",
        ))
        bank_flags = bank_flags_result.scalars().all()
    check("regla 'cuenta cambiada antes del pago' detecto el cambio de emp1", any(f.employee_id == emp1.id for f in bank_flags), f"flags={[f.employee_id for f in bank_flags]}")

    print("\n=== STAGE J: endpoint de snapshot ===")
    snapshot_resp = await get_period_snapshot(period_curr.id, current_user=admin, locale="es")
    check("endpoint snapshot devuelve 4 lineas", len(snapshot_resp) == 4, f"got={len(snapshot_resp)}")
    check("endpoint snapshot resuelve nombre de empleado", any(l.employee_name == "Test RunUno" for l in snapshot_resp))

    print("\n=== STAGE K: filtro de flags por periodo ===")
    period_flags = await list_flags(payroll_period_id=period_curr.id, current_user=admin)
    check("GET flags?payroll_period_id filtra correctamente", len(period_flags) >= 6, f"got={len(period_flags)}")

    print("\n=== STAGE L: bloqueo blocked_rows ===")
    fake_rows_blocked = [
        {"employee_id": emp1.id, "net_pay": None, "gross_pay": None, "branch_id": BRANCH_CARTAGO, "ccss_deduction": None, "renta_amount": None, "renta_is_refund": False, "overtime_extra_hours": 0},
    ]

    async def fake_blocked(session, tenant_id, period, branch_id=None):
        return fake_rows_blocked

    renta_mod.compute_net_payroll_rows = fake_blocked
    await update_period_status(period_blocked.id, PayrollPeriodStatusUpdate(status="validado"), current_user=admin, locale="es")
    try:
        await update_period_status(period_blocked.id, PayrollPeriodStatusUpdate(status="calculado"), current_user=admin, locale="es")
        check("calculado con filas bloqueadas -> debe fallar", False, "no lanzo excepcion")
    except HTTPException as e:
        check("calculado bloqueado por blocked_rows", e.status_code == 400 and e.detail.get("error") == "blocked_rows", f"detail={e.detail}")

    print("\n=== STAGE M: bloqueo missing_catalogs (periodo 2099) ===")
    try:
        await update_period_status(period_novalidate.id, PayrollPeriodStatusUpdate(status="validado"), current_user=admin, locale="es")
        check("validado sin catalogos 2099 -> debe fallar", False, "no lanzo excepcion")
    except HTTPException as e:
        missing = e.detail.get("missing", []) if isinstance(e.detail, dict) else []
        check("validado bloqueado por catalogos faltantes de 2099", e.status_code == 400 and e.detail.get("error") == "missing_catalogs" and any("2099" in m for m in missing), f"detail={e.detail}")

    print("\n=== STAGE N: bloqueo invalid_transition (saltar paso) ===")
    await update_period_status(period_skip.id, PayrollPeriodStatusUpdate(status="validado"), current_user=admin, locale="es")
    try:
        await update_period_status(period_skip.id, PayrollPeriodStatusUpdate(status="aprobado"), current_user=admin, locale="es")
        check("saltar de validado a aprobado -> debe fallar", False, "no lanzo excepcion")
    except HTTPException as e:
        check("transicion invalida bloqueada (validado -> aprobado, se salta calculado)", e.status_code == 400 and e.detail.get("error") == "invalid_transition" and e.detail.get("expected_next") == "calculado", f"detail={e.detail}")

    print("\n=== CLEANUP ===")
    await cleanup_test_data()
    print("Cleanup OK (PayrollAnomalyConfig, cuenta contable de Heredia y BankFileConfig quedan como catalogo real)")

    print("\n" + "=" * 60)
    print(f"RESULTADOS: {len(PASS)} PASS, {len(FAIL)} FAIL")
    if FAIL:
        print("FALLAS:")
        for f in FAIL:
            print(f"  - {f}")
    print("=" * 60)


if __name__ == "__main__":
    asyncio.run(main())
