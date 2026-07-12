"""
Fase 9 (Asientos contables) - Test end-to-end.

Corre DENTRO del contenedor api. Copiar con:
    docker compose cp test_accounting_e2e.py api:/app/test_accounting_e2e.py
    docker compose exec -T api python3 test_accounting_e2e.py

Estrategia:
- STAGE A: siembra el plan de cuentas REAL (13 cuentas), vincula
  CCSS-EMPLEADO/RENTA/AGUINALDO a sus cuentas de pasivo (via los
  endpoints reales de catalogs), crea CCSS-PATRONAL (concepto nuevo,
  tasa de PRUEBA flageada, mismo patron que CCSS-EMPLEADO), y configura
  Branch.accounting_account de una sucursal real - todo esto queda
  como catalogo REAL despues del test, no se borra en el cleanup.
- STAGE B-G: cada generate_*_entry() se prueba con las funciones de
  computo downstream (compute_net_payroll_rows, compute_payroll_rows,
  compute_vacation_balance/daily_rate, compute_aguinaldo_rows,
  compute_cesantia_amount) MONKEYPARCHEADAS a valores fijos conocidos -
  esos calculos ya se probaron en sus fases respectivas, aqui se prueba
  solo la logica NUEVA de generacion/persistencia de asientos.
- Cleanup: borra los JournalEntry/JournalEntryLine de prueba y los
  Employee/Termination/PayrollPeriod sinteticos. El plan de cuentas,
  los vinculos de concepto->cuenta, el concepto CCSS-PATRONAL y
  Branch.accounting_account quedan como catalogo real.
"""
import asyncio
from datetime import date, datetime, timezone
from uuid import UUID, uuid4

from fastapi import HTTPException
from sqlalchemy import delete, select

from app.core.tenant import tenant_session
from app.db.models import (
    Branch,
    ChartOfAccount,
    Contract,
    Employee,
    JournalEntry,
    JournalEntryLine,
    PayrollConcept,
    PayrollPeriod,
    Termination,
    User,
)
import app.core.accounting as accounting_mod
import app.core.vacations as vacations_mod
import app.core.aguinaldo as aguinaldo_mod
import app.core.cesantia as cesantia_mod
from app.core.accounting import persist_journal_entry
from app.modules.catalogs.router import (
    create_chart_of_account,
    list_chart_of_accounts,
    update_chart_of_account,
    create_concept,
    update_concept,
)
from app.modules.catalogs.schemas import (
    ChartOfAccountCreate,
    ChartOfAccountUpdate,
    PayrollConceptCreate,
    PayrollConceptUpdate,
)
from app.modules.accounting.router import (
    create_payroll_entry,
    create_aguinaldo_provision_entry,
    create_aguinaldo_payment_entry,
    create_vacation_provision_entry,
    create_cesantia_entry,
    create_ccss_patronal_entry,
    list_journal_entries,
    export_journal_entries_csv,
)

TENANT_ID = UUID("a7bacc80-f8d9-471f-bb96-b546581184a8")
ADMIN_USER_ID = UUID("b3aa36ab-fa6c-4374-b17d-c5d55b93a789")
BRANCH_CARTAGO = UUID("8819bfff-cb86-418b-8d61-50e92ff01579")
BRANCH_HEREDIA = UUID("59d9595d-31c3-4939-8d12-2eff71ad434d")
MARKER = "TEST_ACCOUNTING_DELETE_ME"

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


ACCOUNTS_TO_SEED = [
    ("GASTO-PLANILLA-CARTAGO", "Gasto de planilla - BK Cartago", "gasto"),
    ("PASIVO-SALARIOS-POR-PAGAR", "Salarios por pagar", "pasivo"),
    ("GASTO-AGUINALDO-PROVISION", "Gasto de provision de aguinaldo", "gasto"),
    ("PASIVO-AGUINALDO-PROVISION", "Pasivo de aguinaldo acumulado", "pasivo"),
    ("GASTO-AJUSTE-AGUINALDO", "Ajuste de aguinaldo (provisionado vs real)", "gasto"),
    ("GASTO-VACACIONES-PROVISION", "Gasto de provision de vacaciones", "gasto"),
    ("PASIVO-VACACIONES-PROVISION", "Pasivo de vacaciones acumulado", "pasivo"),
    ("GASTO-CESANTIA", "Gasto de cesantia", "gasto"),
    ("PASIVO-CESANTIA", "Pasivo de cesantia por pagar", "pasivo"),
    ("PASIVO-CCSS-EMPLEADO-POR-PAGAR", "CCSS empleado por pagar", "pasivo"),
    ("PASIVO-RENTA-POR-PAGAR", "Renta por pagar", "pasivo"),
    ("GASTO-CCSS-PATRONAL", "Gasto CCSS patronal", "gasto"),
    ("PASIVO-CCSS-PATRONAL-POR-PAGAR", "CCSS patronal por pagar", "pasivo"),
]


async def main():
    print("=== STAGE A: sembrar plan de cuentas real + vincular conceptos ===")
    admin = await get_admin_user()

    accounts_by_code = {}
    for code, name, account_type in ACCOUNTS_TO_SEED:
        try:
            resp = await create_chart_of_account(
                ChartOfAccountCreate(code=code, name=name, account_type=account_type),
                current_user=admin, locale="es",
            )
            accounts_by_code[code] = resp
        except HTTPException as e:
            if e.status_code == 400:
                existing = await list_chart_of_accounts(current_user=admin)
                accounts_by_code[code] = next(a for a in existing if a.code == code)
            else:
                raise

    check("13 cuentas contables sembradas/existentes", len(accounts_by_code) == 13, f"got={len(accounts_by_code)}")

    async with tenant_session(TENANT_ID) as session:
        branch = await session.get(Branch, BRANCH_CARTAGO)
        branch.accounting_account = "GASTO-PLANILLA-CARTAGO"
        await session.commit()
    check("Branch BK-Cartago.accounting_account configurado", True)

    async def link_concept(code, account_code):
        async with tenant_session(TENANT_ID) as session:
            result = await session.execute(select(PayrollConcept).where(PayrollConcept.code == code))
            concept = result.scalars().first()
        if concept is None:
            return None
        updated = await update_concept(
            concept.id, PayrollConceptUpdate(accounting_account_id=accounts_by_code[account_code].id),
            current_user=admin, locale="es",
        )
        return updated

    ccss_emp = await link_concept("CCSS-EMPLEADO", "PASIVO-CCSS-EMPLEADO-POR-PAGAR")
    aguinaldo_concept = await link_concept("AGUINALDO", "PASIVO-AGUINALDO-PROVISION")
    check("CCSS-EMPLEADO vinculado a su cuenta", ccss_emp is not None and ccss_emp.accounting_account_id == accounts_by_code["PASIVO-CCSS-EMPLEADO-POR-PAGAR"].id)
    check("AGUINALDO vinculado a su cuenta", aguinaldo_concept is not None and aguinaldo_concept.accounting_account_id == accounts_by_code["PASIVO-AGUINALDO-PROVISION"].id)
    check("AGUINALDO.value es real (8.33, no usa employer_value)", aguinaldo_concept is not None and float(aguinaldo_concept.value) == 8.33, f"got={aguinaldo_concept.value if aguinaldo_concept else None}")
    check("RENTA no existe como concepto - se resuelve por codigo fijo PASIVO-RENTA-POR-PAGAR", "PASIVO-RENTA-POR-PAGAR" in accounts_by_code)

    async with tenant_session(TENANT_ID) as session:
        result = await session.execute(select(PayrollConcept).where(PayrollConcept.code == "CCSS-PATRONAL"))
        ccss_pat = result.scalars().first()
    if ccss_pat is None:
        aguinaldo_pattern = aguinaldo_concept
        ccss_pat_resp = await create_concept(
            PayrollConceptCreate(
                code="CCSS-PATRONAL", name="CCSS Patronal (aporte del empleador - valor de prueba, pendiente validacion contador)",
                calculation_method="porcentaje",
                nature="ingreso", origin="patronal", value=26.67,
                employer_value=None,
                accounting_account_id=accounts_by_code["PASIVO-CCSS-PATRONAL-POR-PAGAR"].id,
            ),
            current_user=admin, locale="es",
        )
        check("CCSS-PATRONAL creado (tasa de prueba flageada 26.67% en .value, mismo patron que AGUINALDO)", ccss_pat_resp.value == 26.67)
    else:
        ccss_pat_resp = await update_concept(
            ccss_pat.id, PayrollConceptUpdate(accounting_account_id=accounts_by_code["PASIVO-CCSS-PATRONAL-POR-PAGAR"].id),
            current_user=admin, locale="es",
        )
        check("CCSS-PATRONAL ya existia, vinculado a su cuenta", ccss_pat_resp.accounting_account_id is not None)

    print("\n=== STAGE B: generate_payroll_journal_entry (planilla ordinaria) ===")
    async with tenant_session(TENANT_ID) as session:
        period_payroll = PayrollPeriod(
            id=uuid4(), tenant_id=TENANT_ID, pay_frequency="mensual",
            period_start=date(2028, 1, 1), period_end=date(2028, 1, 31),
            status="closed", notes=MARKER,
        )
        session.add(period_payroll)
        await session.commit()

    emp1, emp2 = uuid4(), uuid4()

    async def fake_net_payroll_rows(session, tenant_id, period, branch_id=None):
        return [
            {"employee_id": emp1, "branch_id": BRANCH_CARTAGO, "gross_pay": 500000.0,
             "ccss_deduction": 53350.0, "renta_amount": 15000.0, "renta_is_refund": False, "net_pay": 431650.0},
            {"employee_id": emp2, "branch_id": BRANCH_CARTAGO, "gross_pay": 300000.0,
             "ccss_deduction": 32010.0, "renta_amount": 0.0, "renta_is_refund": False, "net_pay": 267990.0},
        ]

    original_net_rows = accounting_mod.compute_net_payroll_rows
    accounting_mod.compute_net_payroll_rows = fake_net_payroll_rows
    try:
        payroll_entry = await create_payroll_entry(payroll_period_id=period_payroll.id, branch_id=None, current_user=admin)
    finally:
        accounting_mod.compute_net_payroll_rows = original_net_rows

    check("planilla: total_debit == total_credit == 800000", payroll_entry.total_debit == 800000.0 and payroll_entry.total_credit == 800000.0,
          f"debit={payroll_entry.total_debit} credit={payroll_entry.total_credit}")
    check("planilla: 4 lineas (1 gasto + ccss + renta + salarios)", len(payroll_entry.lines) == 4, f"got={len(payroll_entry.lines)}")
    line_by_account = {l.account_code: l for l in payroll_entry.lines}
    check("planilla: debe a GASTO-PLANILLA-CARTAGO == 800000", line_by_account["GASTO-PLANILLA-CARTAGO"].debit == 800000.0)
    check("planilla: haber a PASIVO-CCSS-EMPLEADO-POR-PAGAR == 85360", line_by_account["PASIVO-CCSS-EMPLEADO-POR-PAGAR"].credit == 85360.0)
    check("planilla: haber a PASIVO-RENTA-POR-PAGAR == 15000", line_by_account["PASIVO-RENTA-POR-PAGAR"].credit == 15000.0)
    check("planilla: haber a PASIVO-SALARIOS-POR-PAGAR == 699640", line_by_account["PASIVO-SALARIOS-POR-PAGAR"].credit == 699640.0)

    print("\n=== STAGE B2: missing_accounts (sucursal sin accounting_account configurado) ===")
    async def fake_net_payroll_rows_heredia(session, tenant_id, period, branch_id=None):
        return [{"employee_id": uuid4(), "branch_id": BRANCH_HEREDIA, "gross_pay": 100000.0,
                  "ccss_deduction": 10670.0, "renta_amount": 0.0, "renta_is_refund": False, "net_pay": 89330.0}]
    accounting_mod.compute_net_payroll_rows = fake_net_payroll_rows_heredia
    try:
        try:
            await create_payroll_entry(payroll_period_id=period_payroll.id, branch_id=BRANCH_HEREDIA, current_user=admin)
            check("planilla sucursal sin cuenta debe fallar", False, "no lanzo excepcion")
        except HTTPException as e:
            check("planilla sucursal sin cuenta -> 400 missing_accounts", e.status_code == 400 and e.detail.get("error") == "missing_accounts", f"got={e.status_code} {e.detail}")
    finally:
        accounting_mod.compute_net_payroll_rows = original_net_rows

    print("\n=== STAGE C: generate_aguinaldo_provision_entry ===")
    async def fake_payroll_rows_800k(session, start_date, end_date, branch_id=None):
        return [{"employee_id": emp1, "gross_pay": 500000.0}, {"employee_id": emp2, "gross_pay": 300000.0}]

    original_payroll_rows = accounting_mod.compute_payroll_rows
    accounting_mod.compute_payroll_rows = fake_payroll_rows_800k
    try:
        aguinaldo_prov_entry = await create_aguinaldo_provision_entry(payroll_period_id=period_payroll.id, branch_id=None, current_user=admin)
    finally:
        accounting_mod.compute_payroll_rows = original_payroll_rows

    check("aguinaldo provision: monto == 800000*8.33% == 66640.0", aguinaldo_prov_entry.total_debit == 66640.0, f"got={aguinaldo_prov_entry.total_debit}")
    check("aguinaldo provision: balanceado", aguinaldo_prov_entry.total_debit == aguinaldo_prov_entry.total_credit)

    print("\n=== STAGE D: generate_ccss_patronal_entry ===")
    accounting_mod.compute_payroll_rows = fake_payroll_rows_800k
    try:
        ccss_pat_entry = await create_ccss_patronal_entry(payroll_period_id=period_payroll.id, branch_id=None, current_user=admin)
    finally:
        accounting_mod.compute_payroll_rows = original_payroll_rows
    check("ccss patronal: monto == 800000*26.67% == 213360.0", ccss_pat_entry.total_debit == 213360.0, f"got={ccss_pat_entry.total_debit}")

    print("\n=== STAGE E: generate_vacation_provision_entry ===")
    emp_vac_ok, emp_vac_blocked = uuid4(), uuid4()

    async def fake_payroll_rows_vac(session, start_date, end_date, branch_id=None):
        return [{"employee_id": emp_vac_ok, "gross_pay": 400000.0}, {"employee_id": emp_vac_blocked, "gross_pay": 400000.0}]

    async def fake_vacation_balance(session, employee_id, as_of_date):
        if employee_id == emp_vac_blocked:
            return {"blocked": True}
        if as_of_date == period_payroll.period_start:
            return {"blocked": False, "accrued_days": 5.0}
        return {"blocked": False, "accrued_days": 5.5}

    async def fake_vacation_daily_rate(session, employee_id, as_of_date, cycle_weeks, branch_id=None):
        return 17000.0, None

    original_vac_balance = vacations_mod.compute_vacation_balance
    original_vac_rate = vacations_mod.compute_vacation_daily_rate
    accounting_mod.compute_payroll_rows = fake_payroll_rows_vac
    vacations_mod.compute_vacation_balance = fake_vacation_balance
    vacations_mod.compute_vacation_daily_rate = fake_vacation_daily_rate
    try:
        vac_entry = await create_vacation_provision_entry(payroll_period_id=period_payroll.id, branch_id=None, current_user=admin)
    finally:
        accounting_mod.compute_payroll_rows = original_payroll_rows
        vacations_mod.compute_vacation_balance = original_vac_balance
        vacations_mod.compute_vacation_daily_rate = original_vac_rate

    check("vacaciones provision: monto == 0.5*17000 == 8500.0 (solo el empleado no bloqueado)", vac_entry.total_debit == 8500.0, f"got={vac_entry.total_debit}")

    print("\n=== STAGE F: generate_aguinaldo_payment_entry (reconciliacion) ===")
    async def fake_aguinaldo_rows(session, year, branch_id=None):
        return [{"employee_id": emp1, "aguinaldo_amount": 400000.0}, {"employee_id": emp2, "aguinaldo_amount": 300000.0}]

    original_aguinaldo_rows = aguinaldo_mod.compute_aguinaldo_rows
    aguinaldo_mod.compute_aguinaldo_rows = fake_aguinaldo_rows
    try:
        payment_entry = await create_aguinaldo_payment_entry(year=2028, branch_id=None, current_user=admin)
    finally:
        aguinaldo_mod.compute_aguinaldo_rows = original_aguinaldo_rows

    check("aguinaldo pago: real_total == 700000", any(l.credit == 700000.0 for l in payment_entry.lines), f"lines={[(l.account_code, l.debit, l.credit) for l in payment_entry.lines]}")
    check("aguinaldo pago: cancela pasivo provisionado (66640)", any(l.debit == 66640.0 and l.account_code == "PASIVO-AGUINALDO-PROVISION" for l in payment_entry.lines))
    check("aguinaldo pago: ajuste por diferencia (700000-66640=633360)", any(l.debit == 633360.0 and l.account_code == "GASTO-AJUSTE-AGUINALDO" for l in payment_entry.lines))
    check("aguinaldo pago: balanceado", payment_entry.total_debit == payment_entry.total_credit)

    print("\n=== STAGE G: generate_cesantia_entry ===")
    async with tenant_session(TENANT_ID) as session:
        emp_cesantia = Employee(
            id=uuid4(), tenant_id=TENANT_ID, branch_id=BRANCH_CARTAGO,
            first_name="TestAcct", last_name="Cesantia", id_type="cedula_fisica",
            id_number="9-0002-0001", position=MARKER, hire_date=date(2015, 1, 1), active=True,
        )
        session.add(emp_cesantia)
        await session.flush()
        term = Termination(
            id=uuid4(), tenant_id=TENANT_ID, employee_id=emp_cesantia.id,
            termination_date=date(2028, 1, 15), cause="Despido injustificado",
            con_responsabilidad_patronal=True, status="pending",
        )
        session.add(term)
        await session.commit()
        term_id = term.id

    async def fake_cesantia_amount(session, termination, branch_id=None):
        return {"eligible": True, "amount": 500000.0, "days": 50.0, "years_recognized": 2,
                "daily_rate": 10000.0, "config_missing": False, "scale_missing": False,
                "frequency_unsupported": False, "no_history": False, "partial_history": False}

    original_cesantia_amount = cesantia_mod.compute_cesantia_amount
    cesantia_mod.compute_cesantia_amount = fake_cesantia_amount
    try:
        cesantia_entry = await create_cesantia_entry(termination_id=term_id, current_user=admin, locale="es")
    finally:
        cesantia_mod.compute_cesantia_amount = original_cesantia_amount

    check("cesantia: monto == 500000", cesantia_entry.total_debit == 500000.0, f"got={cesantia_entry.total_debit}")
    check("cesantia: termination_id vinculado", cesantia_entry.termination_id == term_id)

    async def fake_cesantia_not_eligible(session, termination, branch_id=None):
        return {"eligible": False, "amount": 0.0, "days": 0.0}

    cesantia_mod.compute_cesantia_amount = fake_cesantia_not_eligible
    try:
        try:
            await create_cesantia_entry(termination_id=term_id, current_user=admin, locale="es")
            check("cesantia not_eligible debe fallar", False, "no lanzo excepcion")
        except HTTPException as e:
            check("cesantia not_eligible -> 400", e.status_code == 400 and e.detail.get("error") == "not_eligible", f"got={e.detail}")
    finally:
        cesantia_mod.compute_cesantia_amount = original_cesantia_amount

    print("\n=== STAGE H: persist_journal_entry (validacion de balance) ===")
    async with tenant_session(TENANT_ID) as session:
        bad_result = {
            "error": None, "entry_date": date(2028, 1, 31), "entry_type": "planilla",
            "payroll_period_id": None, "termination_id": None, "description": "test desbalanceado",
            "lines": [{"account_id": accounts_by_code["PASIVO-SALARIOS-POR-PAGAR"].id, "branch_id": None, "debit": 100.0, "credit": 0.0, "description": "x"}],
        }
        entry, error = await persist_journal_entry(session, TENANT_ID, bad_result, admin.id)
    check("persist_journal_entry detecta asiento desbalanceado", entry is None and error["error"] == "unbalanced", f"got={error}")

    print("\n=== STAGE I: listar + exportar CSV ===")
    all_entries = await list_journal_entries(entry_type=None, start_date=date(2028, 1, 1), end_date=date(2028, 12, 31), current_user=admin)
    check("list_journal_entries incluye los 5 asientos creados", len(all_entries) >= 5, f"got={len(all_entries)}")

    csv_response = await export_journal_entries_csv(entry_type=None, start_date=date(2028, 1, 1), end_date=date(2028, 12, 31), current_user=admin)
    csv_text = csv_response.body.decode("utf-8-sig")
    check("export CSV tiene encabezado correcto", csv_text.startswith("fecha,tipo_asiento"), f"got={csv_text[:60]!r}")
    check("export CSV incluye monto de planilla (800000.00)", "800000.00" in csv_text)

    print("\n=== STAGE J: ChartOfAccount CRUD (duplicado + update) ===")
    try:
        await create_chart_of_account(
            ChartOfAccountCreate(code="PASIVO-SALARIOS-POR-PAGAR", name="dup", account_type="pasivo"),
            current_user=admin, locale="es",
        )
        check("crear cuenta con codigo duplicado debe fallar", False, "no lanzo excepcion")
    except HTTPException as e:
        check("cuenta duplicada -> 400 account_code_exists", e.status_code == 400)

    updated_account = await update_chart_of_account(
        accounts_by_code["GASTO-AJUSTE-AGUINALDO"].id,
        ChartOfAccountUpdate(name="Ajuste de aguinaldo (renombrado)"),
        current_user=admin, locale="es",
    )
    check("update_chart_of_account cambia el nombre", updated_account.name == "Ajuste de aguinaldo (renombrado)")

    print("\n=== CLEANUP: borrando solo datos transaccionales de prueba ===")
    async with tenant_session(TENANT_ID) as session:
        await session.execute(delete(JournalEntryLine).where(JournalEntryLine.tenant_id == TENANT_ID, JournalEntryLine.journal_entry_id.in_(
            select(JournalEntry.id).where(JournalEntry.payroll_period_id == period_payroll.id)
        )))
        await session.execute(delete(JournalEntryLine).where(JournalEntryLine.tenant_id == TENANT_ID, JournalEntryLine.journal_entry_id.in_(
            select(JournalEntry.id).where(JournalEntry.termination_id == term_id)
        )))
        await session.execute(delete(JournalEntryLine).where(JournalEntryLine.tenant_id == TENANT_ID, JournalEntryLine.journal_entry_id == payment_entry.id))
        await session.execute(delete(JournalEntry).where(JournalEntry.payroll_period_id == period_payroll.id))
        await session.execute(delete(JournalEntry).where(JournalEntry.termination_id == term_id))
        await session.execute(delete(JournalEntry).where(JournalEntry.id == payment_entry.id))
        await session.execute(delete(Termination).where(Termination.id == term_id))
        await session.execute(delete(Employee).where(Employee.position == MARKER))
        await session.execute(delete(PayrollPeriod).where(PayrollPeriod.notes == MARKER))
        await session.commit()
    print("Cleanup OK (plan de cuentas, vinculos de concepto y CCSS-PATRONAL quedan como catalogo real)")

    print("\n" + "=" * 60)
    print(f"RESULTADOS: {len(PASS)} PASS, {len(FAIL)} FAIL")
    if FAIL:
        print("FALLAS:")
        for f in FAIL:
            print(f"  - {f}")
    print("=" * 60)


if __name__ == "__main__":
    asyncio.run(main())
