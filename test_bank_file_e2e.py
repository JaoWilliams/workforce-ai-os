"""
Fase 10 (Archivo bancario) - Test end-to-end.
Corre DENTRO del contenedor api. Copiar con:
    docker compose cp test_bank_file_e2e.py api:/app/test_bank_file_e2e.py
    docker compose exec -T api python3 test_bank_file_e2e.py

Estrategia:
- STAGE A: crea empleados de prueba (marcados) + 2 PayrollPeriod de
  prueba (marcados).
- STAGE B/C: configura BankFileConfig con la glosa REAL confirmada por
  el cliente ("PLANILLA EMPRESARIAL BURGER KING COSTA RICA"). Si ya
  existe de una corrida anterior se reusa (es catalogo real, no se
  borra en el cleanup); si no existe todavia, primero se prueba el
  bloqueo bank_config_missing.
- STAGE D-G: compute_net_payroll_rows (fase 5, ya probado en su fase)
  se MONKEYPARCHEA a filas fijas conocidas que cubren cada rama del
  patron blocking-cascade de generate_bank_transfer_rows: neto no
  computable, empleado no encontrado, neto cero/negativo, cuenta
  bancaria faltante, y el caso valido. Se prueba solo la logica NUEVA
  (generacion/persistencia del archivo), no el calculo de neto.
- STAGE H: flujo completo via los endpoints reales (bypass JWT).
- STAGE I: caso no_valid_rows (todos los empleados excluidos).
- Cleanup: borra BankTransferFileLine/BankTransferFile/Employee/
  PayrollPeriod de prueba. BankFileConfig queda como catalogo real.
"""
import asyncio
from datetime import date
from uuid import UUID, uuid4

from fastapi import HTTPException
from sqlalchemy import delete, select

from app.core.tenant import tenant_session
from app.db.models import BankTransferFile, BankTransferFileLine, Employee, PayrollPeriod, User
import app.core.renta as renta_mod
from app.core.bank_file import generate_bank_transfer_rows, persist_bank_transfer_file, render_bank_transfer_txt
from app.modules.catalogs.router import upsert_bank_file_config, get_bank_file_config
from app.modules.catalogs.schemas import BankFileConfigUpsert
from app.modules.employees.router import create_employee, update_employee
from app.modules.employees.schemas import EmployeeCreate, EmployeeUpdate
from app.modules.bank_file.router import (
    generate_bank_transfer_file,
    get_bank_transfer_file,
    list_bank_transfer_files,
    export_bank_transfer_file_txt,
)

TENANT_ID = UUID("a7bacc80-f8d9-471f-bb96-b546581184a8")
ADMIN_USER_ID = UUID("b3aa36ab-fa6c-4374-b17d-c5d55b93a789")
BRANCH_CARTAGO = UUID("8819bfff-cb86-418b-8d61-50e92ff01579")
MARKER = "TEST_BANKFILE_DELETE_ME"
REAL_GLOSA = "PLANILLA EMPRESARIAL BURGER KING COSTA RICA"

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


async def main():
    admin = await get_admin_user()

    print("=== STAGE A: empleados y periodos de prueba ===")
    emp1 = await create_employee(
        EmployeeCreate(branch_id=BRANCH_CARTAGO, first_name="Test", last_name="BankfileUno",
                        id_type="cedula_fisica", id_number="TEST-BANKFILE-001",
                        position=MARKER, hire_date=date(2024, 1, 1)),
        current_user=admin, locale="es",
    )
    emp2 = await create_employee(
        EmployeeCreate(branch_id=BRANCH_CARTAGO, first_name="Test", last_name="BankfileDos",
                        id_type="cedula_fisica", id_number="TEST-BANKFILE-002",
                        position=MARKER, hire_date=date(2024, 1, 1)),
        current_user=admin, locale="es",
    )
    emp3 = await create_employee(
        EmployeeCreate(branch_id=BRANCH_CARTAGO, first_name="Test", last_name="BankfileTres",
                        id_type="cedula_fisica", id_number="TEST-BANKFILE-003",
                        position=MARKER, hire_date=date(2024, 1, 1)),
        current_user=admin, locale="es",
    )
    emp4 = await create_employee(
        EmployeeCreate(branch_id=BRANCH_CARTAGO, first_name="Test", last_name="BankfileCuatro",
                        id_type="cedula_fisica", id_number="TEST-BANKFILE-004",
                        position=MARKER, hire_date=date(2024, 1, 1)),
        current_user=admin, locale="es",
    )

    emp1 = await update_employee(emp1.id, EmployeeUpdate(bank_account_type="Cuenta de Ahorro", bank_account_number="16001590266"), current_user=admin, locale="es")
    emp2 = await update_employee(emp2.id, EmployeeUpdate(bank_account_type="Cuenta Corriente", bank_account_number="16001591782"), current_user=admin, locale="es")
    emp4 = await update_employee(emp4.id, EmployeeUpdate(bank_account_type="Cuenta de Ahorro", bank_account_number="16001590444"), current_user=admin, locale="es")
    # emp3 queda a proposito SIN cuenta bancaria

    check("PATCH empleado guarda tipo de cuenta", emp1.bank_account_type == "Cuenta de Ahorro")
    check("PATCH empleado guarda numero de cuenta", emp1.bank_account_number == "16001590266")
    check("empleado sin PATCH de banco queda sin cuenta", emp3.bank_account_type is None and emp3.bank_account_number is None)

    async with tenant_session(TENANT_ID) as session:
        period_ok = PayrollPeriod(
            id=uuid4(), tenant_id=TENANT_ID, pay_frequency="mensual",
            period_start=date(2026, 6, 1), period_end=date(2026, 6, 30),
            status="draft", notes=MARKER,
        )
        period_blocked = PayrollPeriod(
            id=uuid4(), tenant_id=TENANT_ID, pay_frequency="mensual",
            period_start=date(2026, 5, 1), period_end=date(2026, 5, 31),
            status="draft", notes=MARKER,
        )
        session.add(period_ok)
        session.add(period_blocked)
        await session.commit()
        await session.refresh(period_ok)
        await session.refresh(period_blocked)

    print("\n=== STAGE B: bloqueo por config faltante (solo si aun no existe) ===")
    existing_config = await get_bank_file_config(current_user=admin)
    if existing_config is None:
        async with tenant_session(TENANT_ID) as session:
            result = await generate_bank_transfer_rows(session, TENANT_ID, period_ok, None)
        check("sin BankFileConfig -> error bank_config_missing", result.get("error") == "bank_config_missing")
    else:
        print("  SKIP  BankFileConfig ya existe de una corrida anterior (catalogo real) - no se puede re-probar este bloqueo")

    print("\n=== STAGE C: configurar BankFileConfig (glosa real) ===")
    config = await upsert_bank_file_config(BankFileConfigUpsert(glosa=REAL_GLOSA), current_user=admin)
    check("BankFileConfig.glosa es la glosa real confirmada", config.glosa == REAL_GLOSA)
    check("BankFileConfig queda activo", config.active is True)

    print("\n=== STAGE D: monkeypatch compute_net_payroll_rows (casos conocidos) ===")
    ghost_id_1 = uuid4()  # neto no computable
    ghost_id_2 = uuid4()  # empleado no encontrado

    fake_rows_ok = [
        {"employee_id": emp1.id, "net_pay": 962275.00},
        {"employee_id": emp2.id, "net_pay": 619575.00},
        {"employee_id": emp3.id, "net_pay": 405075.00},   # sin cuenta bancaria
        {"employee_id": emp4.id, "net_pay": 0.00},        # neto cero
        {"employee_id": ghost_id_1, "net_pay": None},     # neto no computable
        {"employee_id": ghost_id_2, "net_pay": 100.00},   # empleado no existe
    ]

    async def fake_compute_net_payroll_rows(session, tenant_id, period, branch_id=None):
        return fake_rows_ok

    renta_mod.compute_net_payroll_rows = fake_compute_net_payroll_rows

    print("\n=== STAGE E: generate_bank_transfer_rows (funcion core) ===")
    async with tenant_session(TENANT_ID) as session:
        result = await generate_bank_transfer_rows(session, TENANT_ID, period_ok, None)

    check("row_count == 2 (solo emp1 y emp2 validos)", result.get("row_count") == 2, f"got={result.get('row_count')}")
    check("total_amount == 1581850.00", abs(result.get("total_amount", 0) - 1581850.00) < 0.01, f"got={result.get('total_amount')}")
    missing_reasons = {m["employee_id"]: m["reason"] for m in result.get("missing", [])}
    check("emp3 excluido por missing_bank_account", missing_reasons.get(emp3.id) == "missing_bank_account")
    check("emp4 excluido por zero_or_negative_net_pay", missing_reasons.get(emp4.id) == "zero_or_negative_net_pay")
    check("ghost_id_1 excluido por net_pay_not_computable", missing_reasons.get(ghost_id_1) == "net_pay_not_computable")
    check("ghost_id_2 excluido por employee_not_found", missing_reasons.get(ghost_id_2) == "employee_not_found")
    check("filas validas usan la glosa real", all(r["glosa"] == REAL_GLOSA for r in result["rows"]))

    print("\n=== STAGE F: persist_bank_transfer_file (funcion core) ===")
    async with tenant_session(TENANT_ID) as session:
        persisted = await persist_bank_transfer_file(session, TENANT_ID, period_ok.id, None, result, admin.id)

    check("persist devuelve bank_transfer_file_id", persisted.get("bank_transfer_file_id") is not None)
    check("persist row_count == 2", persisted.get("row_count") == 2)
    check("persist missing_count == 4", persisted.get("missing_count") == 4, f"got={persisted.get('missing_count')}")

    async with tenant_session(TENANT_ID) as session:
        header = await session.get(BankTransferFile, persisted["bank_transfer_file_id"])
        lines_result = await session.execute(select(BankTransferFileLine).where(BankTransferFileLine.bank_transfer_file_id == header.id))
        lines = lines_result.scalars().all()

    check("header persistido con total_amount correcto", abs(float(header.total_amount) - 1581850.00) < 0.01, f"got={header.total_amount}")
    check("2 lineas persistidas", len(lines) == 2, f"got={len(lines)}")

    print("\n=== STAGE G: render_bank_transfer_txt (formato exacto) ===")
    txt = render_bank_transfer_txt([
        {"account_type": l.account_type, "account_number": l.account_number, "amount": l.amount, "glosa": l.glosa}
        for l in sorted(lines, key=lambda x: x.account_number)
    ])
    expected_line_emp1 = f"Cuenta de Ahorro\t16001590266\t962275.00\t{REAL_GLOSA}"
    check("linea TAB-delimitada sin encabezado coincide con el formato real", expected_line_emp1 in txt, f"got={txt!r}")
    check("archivo no tiene encabezado (no arranca con texto de columna)", not txt.lower().startswith("tipo") and not txt.lower().startswith("account"))

    print("\n=== STAGE H: flujo completo via endpoints reales (router) ===")
    header_resp = await generate_bank_transfer_file(period_ok.id, None, current_user=admin, locale="es")
    check("endpoint generate devuelve row_count == 2", header_resp.row_count == 2)
    check("endpoint generate devuelve missing_count == 4", header_resp.missing_count == 4)

    detail = await get_bank_transfer_file(header_resp.id, current_user=admin, locale="es")
    check("endpoint detail devuelve 2 lineas", len(detail.lines) == 2, f"got={len(detail.lines)}")
    check("endpoint detail resuelve el nombre del empleado", any(l.employee_name == "Test BankfileUno" for l in detail.lines))

    export_resp = await export_bank_transfer_file_txt(header_resp.id, current_user=admin, locale="es")
    export_text = export_resp.body.decode("utf-8")
    check("export-txt coincide con el formato real", expected_line_emp1 in export_text, f"got={export_text!r}")

    listed = await list_bank_transfer_files(payroll_period_id=period_ok.id, current_user=admin)
    check("list devuelve al menos 2 archivos para el periodo", len(listed) >= 2, f"got={len(listed)}")

    print("\n=== STAGE I: caso no_valid_rows (todos excluidos) ===")
    fake_rows_blocked = [
        {"employee_id": emp3.id, "net_pay": 100.00},  # sin cuenta bancaria
    ]

    async def fake_all_blocked(session, tenant_id, period, branch_id=None):
        return fake_rows_blocked

    renta_mod.compute_net_payroll_rows = fake_all_blocked
    try:
        await generate_bank_transfer_file(period_blocked.id, None, current_user=admin, locale="es")
        check("todos excluidos -> debe lanzar HTTPException", False, "no lanzo excepcion")
    except HTTPException as e:
        check("todos excluidos -> 400 no_valid_rows", e.status_code == 400 and e.detail.get("error") == "no_valid_rows", f"detail={e.detail}")

    print("\n=== CLEANUP: borrando solo datos transaccionales de prueba ===")
    async with tenant_session(TENANT_ID) as session:
        await session.execute(delete(BankTransferFileLine).where(
            BankTransferFileLine.tenant_id == TENANT_ID,
            BankTransferFileLine.bank_transfer_file_id.in_(
                select(BankTransferFile.id).where(BankTransferFile.payroll_period_id.in_([period_ok.id, period_blocked.id]))
            ),
        ))
        await session.execute(delete(BankTransferFile).where(
            BankTransferFile.payroll_period_id.in_([period_ok.id, period_blocked.id])
        ))
        await session.execute(delete(Employee).where(Employee.position == MARKER))
        await session.execute(delete(PayrollPeriod).where(PayrollPeriod.notes == MARKER))
        await session.commit()
    print("Cleanup OK (BankFileConfig con la glosa real queda como catalogo de produccion)")

    print("\n" + "=" * 60)
    print(f"RESULTADOS: {len(PASS)} PASS, {len(FAIL)} FAIL")
    if FAIL:
        print("FALLAS:")
        for f in FAIL:
            print(f"  - {f}")
    print("=" * 60)


if __name__ == "__main__":
    asyncio.run(main())
