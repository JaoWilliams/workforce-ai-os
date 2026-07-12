"""
Fase 8 (Cesantia) - Test end-to-end.

Corre DENTRO del contenedor api (necesita el entorno real: sqlalchemy,
asyncpg, DATABASE_URL apuntando a postgres:5432). Copiar con:
    docker compose cp test_cesantia_e2e.py api:/app/test_cesantia_e2e.py
    docker compose exec -T api python3 test_cesantia_e2e.py

Estrategia de prueba:
- STAGE A: siembra CesantiaConfig + CesantiaScaleRow REALES (Art. 29)
  via las funciones reales del router de catalogs (mismo codigo que
  produccion).
- STAGE B: prueba pura de compute_cesantia_days contra 7 casos con
  valores esperados calculados a mano (no reutiliza la formula interna
  para "inventar" el esperado - son literales).
- STAGE C: prueba de compute_cesantia_daily_rate con
  app.core.cesantia.compute_payroll_rows MONKEYPARCHEADO a valores fijos
  conocidos. Esto es deliberado: el calculo de gross_pay por periodo ya
  se probo en una fase anterior (nomina bruta); aqui solo se prueba la
  logica NUEVA de este fase (promedio, agrupacion quincenal por mes,
  deteccion de historial parcial/nulo, bloqueo de frecuencia semanal).
- STAGE D: integracion real via create_termination/update_termination_status
  (las funciones REALES del router, llamadas directamente con un
  current_user real - sin pasar por HTTP/JWT, que ya esta probado en la
  fase de RBAC). Incluye un caso con monto calculado end-to-end (usando
  el mismo monkeypatch de compute_payroll_rows).
- STAGE E: validaciones de negocio (terminacion duplicada, empleado ya
  inactivo, estado invalido, terminacion no encontrada, ya revisada).
- STAGE F: con_responsabilidad_patronal=False -> 0, pero el efecto
  lateral Employee.active=False igual aplica al aprobar.
- Cleanup: borra SOLO los datos creados por este test (marcados con
  position="TEST_CESANTIA_DELETE_ME"). CesantiaConfig/CesantiaScaleRow
  NO se borran - son catalogo real.
"""
import asyncio
from datetime import date, datetime, timezone
from uuid import UUID, uuid4

from fastapi import HTTPException
from sqlalchemy import delete, select

from app.core.tenant import tenant_session
from app.db.models import (
    CesantiaConfig,
    CesantiaScaleRow,
    Contract,
    Employee,
    PayrollPeriod,
    Termination,
    User,
)
from app.core.cesantia import (
    compute_cesantia_days,
    compute_cesantia_daily_rate,
    compute_years_months,
    _get_config,
    _get_scale,
)
import app.core.cesantia as cesantia_mod
from app.modules.catalogs.router import (
    upsert_cesantia_config,
    get_cesantia_config,
    upsert_cesantia_scale,
    get_cesantia_scale,
)
from app.modules.catalogs.schemas import (
    CesantiaConfigUpsert,
    CesantiaScaleBulkUpsert,
    CesantiaScaleRowUpsert,
)
from app.modules.payroll.router import (
    create_termination,
    list_terminations,
    update_termination_status,
)
from app.modules.payroll.schemas import TerminationCreate, TerminationStatusUpdate

TENANT_ID = UUID("a7bacc80-f8d9-471f-bb96-b546581184a8")
ADMIN_USER_ID = UUID("b3aa36ab-fa6c-4374-b17d-c5d55b93a789")
BRANCH_ID = UUID("8819bfff-cb86-418b-8d61-50e92ff01579")
MARKER = "TEST_CESANTIA_DELETE_ME"

REAL_SCALE = {
    1: 19.5, 2: 20, 3: 20.5, 4: 21, 5: 21.24, 6: 21.5, 7: 22, 8: 22,
    9: 22, 10: 21.5, 11: 21, 12: 20.5, 13: 20,
}

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
        _ = user.id, user.tenant_id  # forzar carga de escalares antes de que la sesion cierre
        return user


async def make_employee(session, first_name, hire_date, id_number, pay_frequency, base_salary=500000):
    emp = Employee(
        id=uuid4(), tenant_id=TENANT_ID, branch_id=BRANCH_ID,
        first_name=first_name, last_name="Cesantia", id_type="cedula_fisica",
        id_number=id_number, position=MARKER, hire_date=hire_date, active=True,
    )
    session.add(emp)
    await session.flush()
    contract = Contract(
        id=uuid4(), tenant_id=TENANT_ID, employee_id=emp.id, contract_type="indefinido",
        start_date=hire_date, base_salary=base_salary, currency="CRC",
        pay_frequency=pay_frequency,
    )
    session.add(contract)
    await session.flush()
    return emp, contract


def fake_compute_payroll_rows_factory(gross_by_period_start, employee_id):
    async def _fake(session, period_start, period_end, branch_id=None):
        gross = gross_by_period_start.get(period_start)
        if gross is None:
            return []
        return [{"employee_id": employee_id, "gross_pay": gross}]
    return _fake


async def main():
    print("=== STAGE A: sembrar catalogo real (Art. 29) ===")
    admin = await get_admin_user()

    config_payload = CesantiaConfigUpsert(
        max_years_cap=8, fraction_round_months=6, days_3to6_months=7,
        days_6to12_months=14, daily_divisor=30, months_for_average=6,
    )
    config_resp = await upsert_cesantia_config(config_payload, current_user=admin)
    check("config.max_years_cap == 8", config_resp.max_years_cap == 8)
    check("config.days_3to6_months == 7", config_resp.days_3to6_months == 7)
    check("config.days_6to12_months == 14", config_resp.days_6to12_months == 14)
    check("config.daily_divisor == 30", config_resp.daily_divisor == 30)

    scale_payload = CesantiaScaleBulkUpsert(
        rows=[CesantiaScaleRowUpsert(year_number=y, days=d) for y, d in REAL_SCALE.items()]
    )
    scale_resp = await upsert_cesantia_scale(scale_payload, current_user=admin)
    check("scale tiene 13 filas", len(scale_resp) == 13)
    scale_map = {r.year_number: r.days for r in scale_resp}
    check("scale[1] == 19.5", scale_map[1] == 19.5)
    check("scale[5] == 21.24", scale_map[5] == 21.24)
    check("scale[13] == 20", scale_map[13] == 20)

    get_config_resp = await get_cesantia_config(current_user=admin)
    check("get_cesantia_config persiste", get_config_resp is not None and get_config_resp.max_years_cap == 8)
    get_scale_resp = await get_cesantia_scale(current_user=admin)
    check("get_cesantia_scale persiste 13 filas", len(get_scale_resp) == 13)

    print("\n=== STAGE B: compute_cesantia_days (casos puros) ===")
    async with tenant_session(TENANT_ID) as session:
        config = await _get_config(session)
        scale = await _get_scale(session)

    cases_b = [
        ("menos_3_meses (2 meses)", 0, 2, 0.0, 0),
        ("3_a_6_meses (4 meses)", 0, 4, 7.0, 0),
        ("6_meses_a_1_anio (8 meses)", 0, 8, 14.0, 0),
        ("1 anio exacto, resto=6 (no redondea)", 1, 6, 19.5, 1),
        ("1 anio, resto=7 (redondea a 2)", 1, 7, 39.5, 2),
        ("15 anios (tope en 8)", 15, 0, 167.74, 8),
        ("7 anios, resto=6 (no redondea)", 7, 6, 145.74, 7),
    ]
    for label, years, months, expected_days, expected_years_rec in cases_b:
        result = compute_cesantia_days(years, months, config, scale)
        check(f"{label}: days=={expected_days}", result is not None and result["days"] == expected_days,
              f"got={result}")
        check(f"{label}: years_recognized=={expected_years_rec}",
              result is not None and result["years_recognized"] == expected_years_rec)

    print("\n=== STAGE C: compute_cesantia_daily_rate (monkeypatch de compute_payroll_rows) ===")
    fake_emp_full = uuid4()
    async with tenant_session(TENANT_ID) as session:
        periods_full = []
        for i, (y, m) in enumerate([(2027, 1), (2027, 2), (2027, 3), (2027, 4), (2027, 5), (2027, 6)]):
            start = date(y, m, 1)
            end = date(y, m, 28)
            p = PayrollPeriod(
                id=uuid4(), tenant_id=TENANT_ID, pay_frequency="mensual",
                period_start=start, period_end=end, status="paid",
                notes=MARKER,
            )
            session.add(p)
            periods_full.append(p)
        await session.flush()
        period_starts_full = [p.period_start for p in periods_full]
        await session.commit()

    gross_map_full = {ps: 300000.0 for ps in period_starts_full}
    original_fn = cesantia_mod.compute_payroll_rows
    cesantia_mod.compute_payroll_rows = fake_compute_payroll_rows_factory(gross_map_full, fake_emp_full)
    try:
        async with tenant_session(TENANT_ID) as session:
            rate, flag = await compute_cesantia_daily_rate(
                session, fake_emp_full, "mensual", date(2027, 8, 1), config,
            )
        check("daily_rate full history == 10000.0", rate == 10000.0, f"got={rate}")
        check("full history -> sin flag partial", flag is None, f"flag={flag}")

        async with tenant_session(TENANT_ID) as session:
            rate_partial, flag_partial = await compute_cesantia_daily_rate(
                session, fake_emp_full, "mensual", date(2027, 3, 1), config,
            )
        check("daily_rate parcial (solo 2 meses antes de cutoff) == 10000.0", rate_partial == 10000.0,
              f"got={rate_partial}")
        check("historial parcial -> flag partial_history", flag_partial == "partial_history",
              f"flag={flag_partial}")

        async with tenant_session(TENANT_ID) as session:
            rate_none, flag_none = await compute_cesantia_daily_rate(
                session, fake_emp_full, "mensual", date(2020, 1, 1), config,
            )
        check("sin historial -> rate None", rate_none is None)
        check("sin historial -> flag no_history", flag_none == "no_history", f"flag={flag_none}")

        rate_unsup, flag_unsup = await compute_cesantia_daily_rate(
            None, fake_emp_full, "semanal", date(2027, 8, 1), config,
        )
        check("frecuencia semanal -> rate None", rate_unsup is None)
        check("frecuencia semanal -> flag frequency_unsupported", flag_unsup == "frequency_unsupported")
    finally:
        cesantia_mod.compute_payroll_rows = original_fn

    fake_emp_quin = uuid4()
    async with tenant_session(TENANT_ID) as session:
        q1 = PayrollPeriod(
            id=uuid4(), tenant_id=TENANT_ID, pay_frequency="quincenal",
            period_start=date(2027, 7, 1), period_end=date(2027, 7, 15),
            status="paid", notes=MARKER,
        )
        q2 = PayrollPeriod(
            id=uuid4(), tenant_id=TENANT_ID, pay_frequency="quincenal",
            period_start=date(2027, 7, 16), period_end=date(2027, 7, 31),
            status="paid", notes=MARKER,
        )
        session.add(q1)
        session.add(q2)
        await session.flush()
        q1_start, q2_start = q1.period_start, q2.period_start
        await session.commit()

    gross_map_quin = {q1_start: 250000.0, q2_start: 260000.0}
    cesantia_mod.compute_payroll_rows = fake_compute_payroll_rows_factory(gross_map_quin, fake_emp_quin)
    try:
        async with tenant_session(TENANT_ID) as session:
            rate_q, flag_q = await compute_cesantia_daily_rate(
                session, fake_emp_quin, "quincenal", date(2027, 8, 1), config,
            )
        check("quincenal agrupado por mes: (250000+260000)/30 == 17000.0", rate_q == 17000.0, f"got={rate_q}")
        check("quincenal con 1 solo mes -> partial_history", flag_q == "partial_history")
    finally:
        cesantia_mod.compute_payroll_rows = original_fn

    print("\n=== STAGE D: integracion real via create_termination/update_termination_status ===")
    test_employee_ids = []

    async with tenant_session(TENANT_ID) as session:
        emp_boundary, _ = await make_employee(session, "Boundary6NoRound", date(2020, 1, 1), "9-0001-0001", "mensual")
        emp_round, _ = await make_employee(session, "Round7to2", date(2020, 1, 1), "9-0001-0002", "mensual")
        emp_cap, _ = await make_employee(session, "Cap15years", date(2010, 1, 1), "9-0001-0003", "mensual")
        emp_full, contract_full = await make_employee(session, "FullHistory8yr", date(2019, 8, 1), "9-0001-0004", "mensual")
        emp_unsupported, _ = await make_employee(session, "SemanalUnsupported", date(2013, 1, 1), "9-0001-0005", "semanal")
        emp_norep, _ = await make_employee(session, "SinResponsabilidad", date(2015, 1, 1), "9-0001-0006", "mensual")
        emp_dup, _ = await make_employee(session, "Duplicado", date(2022, 1, 1), "9-0001-0007", "mensual")
        await session.commit()
        for e in (emp_boundary, emp_round, emp_cap, emp_full, emp_unsupported, emp_norep, emp_dup):
            test_employee_ids.append(e.id)

    term_boundary = await create_termination(
        TerminationCreate(employee_id=emp_boundary.id, termination_date=date(2021, 7, 1),
                           cause="Despido injustificado", con_responsabilidad_patronal=True),
        current_user=admin, locale="es",
    )
    check("boundary (7 meses resto, sin redondeo): days==19.5", term_boundary.cesantia_days == 19.5,
          f"got={term_boundary.cesantia_days}")
    check("boundary: years_recognized==1", term_boundary.cesantia_years_recognized == 1)

    term_round = await create_termination(
        TerminationCreate(employee_id=emp_round.id, termination_date=date(2021, 8, 1),
                           cause="Despido injustificado", con_responsabilidad_patronal=True),
        current_user=admin, locale="es",
    )
    check("round (redondea a 2 anios): days==39.5", term_round.cesantia_days == 39.5, f"got={term_round.cesantia_days}")

    term_cap = await create_termination(
        TerminationCreate(employee_id=emp_cap.id, termination_date=date(2025, 1, 1),
                           cause="Cierre de sucursal", con_responsabilidad_patronal=True),
        current_user=admin, locale="es",
    )
    check("cap (15 anios -> tope 8): days==167.74", term_cap.cesantia_days == 167.74, f"got={term_cap.cesantia_days}")
    check("cap: years_recognized==8", term_cap.cesantia_years_recognized == 8)

    cesantia_mod.compute_payroll_rows = fake_compute_payroll_rows_factory(gross_map_full, emp_full.id)
    try:
        term_full = await create_termination(
            TerminationCreate(employee_id=emp_full.id, termination_date=date(2027, 8, 1),
                               cause="Despido injustificado", con_responsabilidad_patronal=True),
            current_user=admin, locale="es",
        )
    finally:
        cesantia_mod.compute_payroll_rows = original_fn
    check("full: days==167.74 (8 anios exactos)", term_full.cesantia_days == 167.74, f"got={term_full.cesantia_days}")
    check("full: daily_rate==10000.0", term_full.cesantia_daily_rate == 10000.0, f"got={term_full.cesantia_daily_rate}")
    check("full: amount==167.74*10000==1677400.0", term_full.cesantia_amount == 1677400.0,
          f"got={term_full.cesantia_amount}")
    check("full: sin flags de datos faltantes", not any([
        term_full.cesantia_config_missing, term_full.cesantia_scale_missing,
        term_full.cesantia_frequency_unsupported, term_full.cesantia_no_history,
    ]))

    term_unsupported = await create_termination(
        TerminationCreate(employee_id=emp_unsupported.id, termination_date=date(2020, 7, 1),
                           cause="Despido injustificado", con_responsabilidad_patronal=True),
        current_user=admin, locale="es",
    )
    check("semanal: days==145.74 (dias si se calculan)", term_unsupported.cesantia_days == 145.74)
    check("semanal: frequency_unsupported==True", term_unsupported.cesantia_frequency_unsupported is True)
    check("semanal: amount es None", term_unsupported.cesantia_amount is None)

    term_norep = await create_termination(
        TerminationCreate(employee_id=emp_norep.id, termination_date=date(2022, 1, 1),
                           cause="Renuncia voluntaria", con_responsabilidad_patronal=False),
        current_user=admin, locale="es",
    )
    check("sin responsabilidad patronal: eligible==False", term_norep.cesantia_eligible is False)
    check("sin responsabilidad patronal: days==0.0", term_norep.cesantia_days == 0.0)
    check("sin responsabilidad patronal: amount==0.0", term_norep.cesantia_amount == 0.0)

    print("\n=== STAGE E: efectos laterales + validaciones ===")
    approved = await update_termination_status(
        term_full.id, TerminationStatusUpdate(status="approved", notes="Aprobado por gerencia"),
        current_user=admin, locale="es",
    )
    check("approve: status==approved", approved.status == "approved")
    check("approve: reviewed_by==admin", approved.reviewed_by == admin.id)
    check("approve: reviewed_at no es None", approved.reviewed_at is not None)

    async with tenant_session(TENANT_ID) as session:
        emp_check = await session.get(Employee, emp_full.id)
        check("efecto lateral: Employee.active == False tras aprobar", emp_check.active is False)

    try:
        await update_termination_status(
            term_full.id, TerminationStatusUpdate(status="approved"), current_user=admin, locale="es",
        )
        check("PATCH sobre ya-revisada debe fallar", False, "no lanzo excepcion")
    except HTTPException as e:
        check("PATCH sobre ya-revisada -> 400 termination_not_pending", e.status_code == 400, f"got={e.status_code} {e.detail}")

    try:
        await update_termination_status(
            uuid4(), TerminationStatusUpdate(status="approved"), current_user=admin, locale="es",
        )
        check("PATCH sobre id inexistente debe fallar", False, "no lanzo excepcion")
    except HTTPException as e:
        check("PATCH id inexistente -> 404 termination_not_found", e.status_code == 404, f"got={e.status_code}")

    try:
        await update_termination_status(
            term_boundary.id, TerminationStatusUpdate(status="bogus"), current_user=admin, locale="es",
        )
        check("PATCH status invalido debe fallar", False, "no lanzo excepcion")
    except HTTPException as e:
        check("PATCH status invalido -> 400 termination_invalid_status", e.status_code == 400)

    try:
        await create_termination(
            TerminationCreate(employee_id=emp_full.id, termination_date=date(2027, 9, 1),
                               cause="Otra causa", con_responsabilidad_patronal=True),
            current_user=admin, locale="es",
        )
        check("crear terminacion para empleado ya inactivo debe fallar", False, "no lanzo excepcion")
    except HTTPException as e:
        check("empleado inactivo -> 400 termination_employee_inactive", e.status_code == 400, f"got={e.status_code} {e.detail}")

    await create_termination(
        TerminationCreate(employee_id=emp_dup.id, termination_date=date(2023, 1, 1),
                           cause="Primera", con_responsabilidad_patronal=True),
        current_user=admin, locale="es",
    )
    try:
        await create_termination(
            TerminationCreate(employee_id=emp_dup.id, termination_date=date(2023, 6, 1),
                               cause="Segunda", con_responsabilidad_patronal=True),
            current_user=admin, locale="es",
        )
        check("terminacion duplicada debe fallar", False, "no lanzo excepcion")
    except HTTPException as e:
        check("terminacion duplicada -> 400 termination_already_exists", e.status_code == 400, f"got={e.status_code} {e.detail}")

    try:
        await create_termination(
            TerminationCreate(employee_id=uuid4(), termination_date=date(2023, 1, 1),
                               cause="X", con_responsabilidad_patronal=True),
            current_user=admin, locale="es",
        )
        check("empleado inexistente debe fallar", False, "no lanzo excepcion")
    except HTTPException as e:
        check("empleado inexistente -> 404", e.status_code == 404)

    all_terms = await list_terminations(employee_id=None, status=None, current_user=admin)
    test_term_ids = {term_boundary.id, term_round.id, term_cap.id, term_full.id, term_unsupported.id, term_norep.id}
    found_ids = {t.id for t in all_terms}
    check("list_terminations incluye todas las creadas", test_term_ids.issubset(found_ids))

    print("\n=== STAGE F: aprobar caso sin responsabilidad patronal (activo -> False igual) ===")
    approved_norep = await update_termination_status(
        term_norep.id, TerminationStatusUpdate(status="approved"), current_user=admin, locale="es",
    )
    check("aprobar sin-responsabilidad: status==approved", approved_norep.status == "approved")
    async with tenant_session(TENANT_ID) as session:
        emp_norep_check = await session.get(Employee, emp_norep.id)
        check("aprobar sin-responsabilidad: Employee.active==False igual", emp_norep_check.active is False)

    print("\n=== CLEANUP: borrando datos de prueba (config/scale reales se conservan) ===")
    async with tenant_session(TENANT_ID) as session:
        await session.execute(delete(Termination).where(Termination.employee_id.in_(test_employee_ids + [emp_dup.id])))
        await session.execute(delete(Contract).where(Contract.employee_id.in_(test_employee_ids)))
        await session.execute(delete(Employee).where(Employee.id.in_(test_employee_ids)))
        await session.execute(delete(PayrollPeriod).where(PayrollPeriod.notes == MARKER))
        await session.commit()
    print("Cleanup OK")

    print("\n" + "=" * 60)
    print(f"RESULTADOS: {len(PASS)} PASS, {len(FAIL)} FAIL")
    if FAIL:
        print("FALLAS:")
        for f in FAIL:
            print(f"  - {f}")
    print("=" * 60)


if __name__ == "__main__":
    asyncio.run(main())
