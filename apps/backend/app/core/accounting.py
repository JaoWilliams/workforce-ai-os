"""
Asientos contables (fase 9 del roadmap de nomina).

No existia un plan de cuentas cargado en el sistema antes de esta fase -
se crea desde cero (ChartOfAccount). Las cuentas se resuelven asi:

- Gasto de planilla ordinaria (nomina bruta): se busca por el codigo en
  Branch.accounting_account (campo que ya existia desde mod. 6,
  pensado exactamente para esto - "centro de costo -> cuenta contable").
- Pasivo/por-pagar de cada concepto individual (CCSS-EMPLEADO, RENTA,
  AGUINALDO, CCSS-PATRONAL): PayrollConcept.accounting_account_id
  (agregado en esta fase). Cada concepto se mapea a UNA cuenta, que
  actua como el lado pasivo/por-pagar de ese concepto especifico.
- Gasto de provisiones y aportes patronales que no tienen un hogar
  natural en Branch o PayrollConcept: se buscan por codigo FIJO en
  ChartOfAccount (mismo tipo de clave fija que "AGUINALDO" o
  "HORAS_EXTRA" ya usan como PayrollConcept.code en core/payroll.py -
  es una clave de busqueda, no un valor financiero, así que no viola
  la regla de cero-hardcode). Codigos esperados:
    GASTO-AGUINALDO-PROVISION, PASIVO-SALARIOS-POR-PAGAR,
    GASTO-VACACIONES-PROVISION, PASIVO-VACACIONES-PROVISION,
    GASTO-CESANTIA, PASIVO-CESANTIA, GASTO-CCSS-PATRONAL,
    GASTO-AJUSTE-AGUINALDO.

Cesantia: el asiento SOLO se genera al aprobar una Termination con
con_responsabilidad_patronal=True (decision confirmada con el cliente).
NO hay provision mensual especulativa - provisionar mensualmente
requeriria asumir una tasa de rotacion/despidos que no existe como
dato real, y esa fue precisamente la razon para no hacerlo.

Aguinaldo: la provision mensual (8.33% patronal, PayrollConcept.AGUINALDO
ya existente desde mod.6) acumula en su cuenta de pasivo. El pago real
de diciembre (generate_aguinaldo_payment_entry) CANCELA ese pasivo
acumulado hasta el monto real pagado o lo provisionado (el que sea
menor) - decision confirmada con el cliente. La diferencia, si existe,
se ajusta contra GASTO-AJUSTE-AGUINALDO.

Todas las funciones generate_*_entry() devuelven un dict sin persistir
nada - permite inspeccionar/validar antes de guardar. persist_journal_entry()
hace la escritura real, validando que debe==haber antes de comitear.
"""
from datetime import date
from typing import Optional
from uuid import UUID, uuid4

from sqlalchemy import select

from app.core.payroll import compute_payroll_rows
from app.core.renta import compute_net_payroll_rows
from app.db.models import (
    Branch,
    ChartOfAccount,
    JournalEntry,
    JournalEntryLine,
    PayrollConcept,
    PayrollPeriod,
    Termination,
)

FIXED_ACCOUNT_CODES = (
    "GASTO-AGUINALDO-PROVISION",
    "PASIVO-SALARIOS-POR-PAGAR",
    "GASTO-VACACIONES-PROVISION",
    "PASIVO-VACACIONES-PROVISION",
    "GASTO-CESANTIA",
    "PASIVO-CESANTIA",
    "GASTO-CCSS-PATRONAL",
    "GASTO-AJUSTE-AGUINALDO",
)


async def _get_account_by_code(session, code: str) -> Optional[ChartOfAccount]:
    result = await session.execute(
        select(ChartOfAccount).where(ChartOfAccount.code == code, ChartOfAccount.active.is_(True))
    )
    return result.scalars().first()


async def _get_concept_with_account(session, code: str):
    """Devuelve (concept, account) - account es None si el concepto no
    existe, esta inactivo, o no tiene accounting_account_id configurado."""
    result = await session.execute(
        select(PayrollConcept).where(PayrollConcept.code == code, PayrollConcept.active.is_(True))
    )
    concept = result.scalars().first()
    if concept is None or concept.accounting_account_id is None:
        return concept, None
    account = await session.get(ChartOfAccount, concept.accounting_account_id)
    return concept, account


async def _sum_journal_credits(session, entry_type: str, account_id: UUID, year: int) -> float:
    result = await session.execute(
        select(JournalEntryLine.credit)
        .join(JournalEntry, JournalEntry.id == JournalEntryLine.journal_entry_id)
        .where(
            JournalEntry.entry_type == entry_type,
            JournalEntryLine.account_id == account_id,
            JournalEntry.entry_date >= date(year, 1, 1),
            JournalEntry.entry_date <= date(year, 12, 31),
        )
    )
    return sum(float(c) for c in result.scalars().all())


async def generate_payroll_journal_entry(session, tenant_id: UUID, payroll_period_id: UUID, branch_id: Optional[UUID] = None) -> dict:
    """Asiento de planilla ordinaria: debita el gasto de planilla por
    sucursal (Branch.accounting_account), acredita CCSS empleado,
    renta y salarios netos por pagar."""
    period = await session.get(PayrollPeriod, payroll_period_id)
    if period is None:
        return {"error": "period_not_found"}

    rows = await compute_net_payroll_rows(session, tenant_id, period, branch_id)
    if not rows:
        return {"error": "no_rows"}

    blocked_rows = [r for r in rows if r.get("gross_pay") is None or r.get("net_pay") is None]
    if blocked_rows:
        return {"error": "blocked_rows", "count": len(blocked_rows)}

    missing = []
    ccss_concept, ccss_account = await _get_concept_with_account(session, "CCSS-EMPLEADO")
    renta_account = await _get_account_by_code(session, "PASIVO-RENTA-POR-PAGAR")
    salarios_account = await _get_account_by_code(session, "PASIVO-SALARIOS-POR-PAGAR")
    if ccss_account is None:
        missing.append("PayrollConcept CCSS-EMPLEADO.accounting_account_id")
    if renta_account is None:
        missing.append("ChartOfAccount PASIVO-RENTA-POR-PAGAR (renta no usa PayrollConcept, se resuelve por codigo fijo)")
    if salarios_account is None:
        missing.append("ChartOfAccount PASIVO-SALARIOS-POR-PAGAR")

    branch_ids = {r["branch_id"] for r in rows}
    branch_result = await session.execute(select(Branch).where(Branch.id.in_(branch_ids)))
    branches = {b.id: b for b in branch_result.scalars().all()}
    branch_accounts = {}
    for bid, b in branches.items():
        if not b.accounting_account:
            missing.append(f"Branch '{b.name}'.accounting_account no configurado")
            continue
        acc = await _get_account_by_code(session, b.accounting_account)
        if acc is None:
            missing.append(f"ChartOfAccount con code='{b.accounting_account}' (Branch '{b.name}')")
            continue
        branch_accounts[bid] = acc

    if missing:
        return {"error": "missing_accounts", "missing": missing}

    gross_by_branch = {}
    ccss_total = 0.0
    renta_total = 0.0
    net_total = 0.0
    for r in rows:
        gross_by_branch[r["branch_id"]] = gross_by_branch.get(r["branch_id"], 0.0) + (r["gross_pay"] or 0.0)
        ccss_total += r.get("ccss_deduction") or 0.0
        if not r.get("renta_is_refund") and r.get("renta_amount"):
            renta_total += r["renta_amount"]
        net_total += r.get("net_pay") or 0.0

    lines = []
    for bid, amount in gross_by_branch.items():
        if amount > 0:
            lines.append({
                "account_id": branch_accounts[bid].id, "branch_id": bid,
                "debit": round(amount, 2), "credit": 0.0,
                "description": f"Gasto de planilla - {branches[bid].name}",
            })
    if ccss_total > 0:
        lines.append({"account_id": ccss_account.id, "branch_id": None, "debit": 0.0, "credit": round(ccss_total, 2), "description": "CCSS empleado por pagar"})
    if renta_total > 0:
        lines.append({"account_id": renta_account.id, "branch_id": None, "debit": 0.0, "credit": round(renta_total, 2), "description": "Renta por pagar"})
    if net_total > 0:
        lines.append({"account_id": salarios_account.id, "branch_id": None, "debit": 0.0, "credit": round(net_total, 2), "description": "Salarios netos por pagar"})

    if not lines:
        return {"error": "zero_amount"}

    return {
        "error": None, "entry_date": period.period_end, "entry_type": "planilla",
        "payroll_period_id": period.id, "termination_id": None,
        "description": f"Planilla {period.pay_frequency} {period.period_start.isoformat()} a {period.period_end.isoformat()}",
        "lines": lines,
    }


async def generate_aguinaldo_provision_entry(session, tenant_id: UUID, payroll_period_id: UUID, branch_id: Optional[UUID] = None) -> dict:
    """Provision mensual de aguinaldo: 8.33% (PayrollConcept.AGUINALDO.
    employer_value, ya real desde mod.6) del gross_pay del periodo."""
    period = await session.get(PayrollPeriod, payroll_period_id)
    if period is None:
        return {"error": "period_not_found"}

    rows = await compute_payroll_rows(session, period.period_start, period.period_end, branch_id)
    if not rows:
        return {"error": "no_rows"}

    blocked_rows = [r for r in rows if r.get("gross_pay") is None]
    if blocked_rows:
        return {"error": "blocked_rows", "count": len(blocked_rows)}

    concept, pasivo_account = await _get_concept_with_account(session, "AGUINALDO")
    gasto_account = await _get_account_by_code(session, "GASTO-AGUINALDO-PROVISION")
    missing = []
    if concept is None or concept.value is None:
        missing.append("PayrollConcept AGUINALDO.value")
    if pasivo_account is None:
        missing.append("PayrollConcept AGUINALDO.accounting_account_id")
    if gasto_account is None:
        missing.append("ChartOfAccount GASTO-AGUINALDO-PROVISION")
    if missing:
        return {"error": "missing_accounts", "missing": missing}

    gross_total = sum(r["gross_pay"] for r in rows)
    rate = float(concept.value) / 100.0
    amount = round(gross_total * rate, 2)
    if amount <= 0:
        return {"error": "zero_amount"}

    lines = [
        {"account_id": gasto_account.id, "branch_id": branch_id, "debit": amount, "credit": 0.0, "description": "Provision de aguinaldo (mensual)"},
        {"account_id": pasivo_account.id, "branch_id": branch_id, "debit": 0.0, "credit": amount, "description": "Pasivo de aguinaldo acumulado"},
    ]
    return {
        "error": None, "entry_date": period.period_end, "entry_type": "aguinaldo_provision",
        "payroll_period_id": period.id, "termination_id": None,
        "description": f"Provision de aguinaldo {period.period_start.isoformat()} a {period.period_end.isoformat()}",
        "lines": lines,
    }


async def generate_aguinaldo_payment_entry(session, tenant_id: UUID, year: int, branch_id: Optional[UUID] = None) -> dict:
    """Pago real de aguinaldo de diciembre (usa core/aguinaldo.py, fase
    7). Cancela el pasivo acumulado por las provisiones mensuales del
    anio hasta el monto real o lo provisionado (el menor) - decision
    confirmada con el cliente. La diferencia se ajusta contra
    GASTO-AJUSTE-AGUINALDO."""
    from app.core.aguinaldo import compute_aguinaldo_rows

    rows = await compute_aguinaldo_rows(session, year, branch_id)
    if not rows:
        return {"error": "no_rows"}

    blocked = [r for r in rows if r.get("aguinaldo_amount") is None]
    real_total = round(sum(r["aguinaldo_amount"] for r in rows if r.get("aguinaldo_amount")), 2)
    if real_total <= 0:
        return {"error": "zero_amount"}

    concept, pasivo_account = await _get_concept_with_account(session, "AGUINALDO")
    salarios_account = await _get_account_by_code(session, "PASIVO-SALARIOS-POR-PAGAR")
    ajuste_account = await _get_account_by_code(session, "GASTO-AJUSTE-AGUINALDO")
    missing = []
    if pasivo_account is None:
        missing.append("PayrollConcept AGUINALDO.accounting_account_id")
    if salarios_account is None:
        missing.append("ChartOfAccount PASIVO-SALARIOS-POR-PAGAR")
    if missing:
        return {"error": "missing_accounts", "missing": missing}

    provisioned_total = round(await _sum_journal_credits(session, "aguinaldo_provision", pasivo_account.id, year), 2)
    cancel_amount = round(min(provisioned_total, real_total), 2)

    lines = []
    if cancel_amount > 0:
        lines.append({"account_id": pasivo_account.id, "branch_id": branch_id, "debit": cancel_amount, "credit": 0.0, "description": f"Cancelacion de pasivo de aguinaldo provisionado ({year})"})

    diff = round(real_total - provisioned_total, 2)
    if diff != 0:
        if ajuste_account is None:
            return {"error": "missing_accounts", "missing": ["ChartOfAccount GASTO-AJUSTE-AGUINALDO (hay diferencia entre lo provisionado y lo real)"]}
        if diff > 0:
            lines.append({"account_id": ajuste_account.id, "branch_id": branch_id, "debit": diff, "credit": 0.0, "description": "Ajuste: aguinaldo real superior a lo provisionado"})
        else:
            lines.append({"account_id": ajuste_account.id, "branch_id": branch_id, "debit": 0.0, "credit": abs(diff), "description": "Ajuste: aguinaldo provisionado superior al real"})

    lines.append({"account_id": salarios_account.id, "branch_id": branch_id, "debit": 0.0, "credit": real_total, "description": f"Aguinaldo real por pagar ({year})"})

    return {
        "error": None, "entry_date": date(year, 12, 31), "entry_type": "aguinaldo_pago",
        "payroll_period_id": None, "termination_id": None,
        "description": f"Pago real de aguinaldo {year}",
        "lines": lines, "blocked_employees": len(blocked), "provisioned_total": provisioned_total, "real_total": real_total,
    }


async def generate_vacation_provision_entry(session, tenant_id: UUID, payroll_period_id: UUID, branch_id: Optional[UUID] = None) -> dict:
    """Provision mensual de vacaciones: delta de dias acumulados durante
    el periodo (compute_vacation_balance en period_start vs period_end)
    x tarifa Art.157 vigente del empleado."""
    from app.core.vacations import compute_vacation_balance, compute_vacation_daily_rate, _get_vacation_config

    period = await session.get(PayrollPeriod, payroll_period_id)
    if period is None:
        return {"error": "period_not_found"}

    rows = await compute_payroll_rows(session, period.period_start, period.period_end, branch_id)
    if not rows:
        return {"error": "no_rows"}

    config = await _get_vacation_config(session)
    gasto_account = await _get_account_by_code(session, "GASTO-VACACIONES-PROVISION")
    pasivo_account = await _get_account_by_code(session, "PASIVO-VACACIONES-PROVISION")
    missing = []
    if config is None:
        missing.append("VacationConfig")
    if gasto_account is None:
        missing.append("ChartOfAccount GASTO-VACACIONES-PROVISION")
    if pasivo_account is None:
        missing.append("ChartOfAccount PASIVO-VACACIONES-PROVISION")
    if missing:
        return {"error": "missing_accounts", "missing": missing}

    total = 0.0
    skipped = 0
    for r in rows:
        emp_id = r["employee_id"]
        before = await compute_vacation_balance(session, emp_id, period.period_start)
        after = await compute_vacation_balance(session, emp_id, period.period_end)
        if before.get("blocked") or after.get("blocked"):
            skipped += 1
            continue
        delta_days = (after.get("accrued_days") or 0) - (before.get("accrued_days") or 0)
        if delta_days <= 0:
            continue
        daily_rate, _flag = await compute_vacation_daily_rate(session, emp_id, period.period_end, config.cycle_weeks, branch_id)
        if daily_rate is None:
            skipped += 1
            continue
        total += delta_days * daily_rate

    if total <= 0:
        return {"error": "zero_amount", "skipped_employees": skipped}

    amount = round(total, 2)
    lines = [
        {"account_id": gasto_account.id, "branch_id": branch_id, "debit": amount, "credit": 0.0, "description": "Provision de vacaciones (mensual)"},
        {"account_id": pasivo_account.id, "branch_id": branch_id, "debit": 0.0, "credit": amount, "description": "Pasivo de vacaciones acumulado"},
    ]
    return {
        "error": None, "entry_date": period.period_end, "entry_type": "vacaciones_provision",
        "payroll_period_id": period.id, "termination_id": None,
        "description": f"Provision de vacaciones {period.period_start.isoformat()} a {period.period_end.isoformat()}",
        "lines": lines, "skipped_employees": skipped,
    }


async def generate_cesantia_entry(session, tenant_id: UUID, termination: Termination) -> dict:
    """Asiento de cesantia - SOLO al aprobar una Termination con
    con_responsabilidad_patronal=True (decision confirmada, no hay
    provision mensual especulativa)."""
    from app.core.cesantia import compute_cesantia_amount

    result = await compute_cesantia_amount(session, termination)
    if not result["eligible"]:
        return {"error": "not_eligible"}
    if not result.get("amount"):
        return {"error": "amount_not_computable", "flags": {
            k: v for k, v in result.items() if k.endswith("_missing") or k in ("no_history", "frequency_unsupported")
        }}

    gasto_account = await _get_account_by_code(session, "GASTO-CESANTIA")
    pasivo_account = await _get_account_by_code(session, "PASIVO-CESANTIA")
    missing = []
    if gasto_account is None:
        missing.append("ChartOfAccount GASTO-CESANTIA")
    if pasivo_account is None:
        missing.append("ChartOfAccount PASIVO-CESANTIA")
    if missing:
        return {"error": "missing_accounts", "missing": missing}

    amount = result["amount"]
    lines = [
        {"account_id": gasto_account.id, "branch_id": None, "debit": amount, "credit": 0.0, "description": "Gasto de cesantia"},
        {"account_id": pasivo_account.id, "branch_id": None, "debit": 0.0, "credit": amount, "description": "Pasivo de cesantia por pagar"},
    ]
    return {
        "error": None, "entry_date": termination.termination_date, "entry_type": "cesantia",
        "payroll_period_id": None, "termination_id": termination.id,
        "description": f"Cesantia - terminacion {termination.id}",
        "lines": lines,
    }


async def generate_ccss_patronal_entry(session, tenant_id: UUID, payroll_period_id: UUID, branch_id: Optional[UUID] = None) -> dict:
    """Aporte patronal a la CCSS - reutiliza PayrollConcept.employer_value
    (concepto CCSS-PATRONAL, tasa de PRUEBA flageada pendiente de
    contador - mismo tratamiento que CCSS-EMPLEADO)."""
    period = await session.get(PayrollPeriod, payroll_period_id)
    if period is None:
        return {"error": "period_not_found"}

    rows = await compute_payroll_rows(session, period.period_start, period.period_end, branch_id)
    if not rows:
        return {"error": "no_rows"}

    blocked_rows = [r for r in rows if r.get("gross_pay") is None]
    if blocked_rows:
        return {"error": "blocked_rows", "count": len(blocked_rows)}

    concept, pasivo_account = await _get_concept_with_account(session, "CCSS-PATRONAL")
    gasto_account = await _get_account_by_code(session, "GASTO-CCSS-PATRONAL")
    missing = []
    if concept is None or concept.value is None:
        missing.append("PayrollConcept CCSS-PATRONAL.value")
    if pasivo_account is None:
        missing.append("PayrollConcept CCSS-PATRONAL.accounting_account_id")
    if gasto_account is None:
        missing.append("ChartOfAccount GASTO-CCSS-PATRONAL")
    if missing:
        return {"error": "missing_accounts", "missing": missing}

    gross_total = sum(r["gross_pay"] for r in rows)
    rate = float(concept.value) / 100.0
    amount = round(gross_total * rate, 2)
    if amount <= 0:
        return {"error": "zero_amount"}

    lines = [
        {"account_id": gasto_account.id, "branch_id": branch_id, "debit": amount, "credit": 0.0, "description": "Gasto CCSS patronal"},
        {"account_id": pasivo_account.id, "branch_id": branch_id, "debit": 0.0, "credit": amount, "description": "CCSS patronal por pagar"},
    ]
    return {
        "error": None, "entry_date": period.period_end, "entry_type": "ccss_patronal",
        "payroll_period_id": period.id, "termination_id": None,
        "description": f"CCSS patronal {period.period_start.isoformat()} a {period.period_end.isoformat()}",
        "lines": lines,
    }


async def persist_journal_entry(session, tenant_id: UUID, result: dict, created_by: Optional[UUID]):
    """Persiste un resultado de generate_*_entry(). Valida debe==haber
    antes de comitear (nunca deberia fallar si las funciones de arriba
    estan bien, pero es la ultima linea de defensa)."""
    if result.get("error"):
        return None, result

    lines = result["lines"]
    total_debit = round(sum(l["debit"] for l in lines), 2)
    total_credit = round(sum(l["credit"] for l in lines), 2)
    if total_debit != total_credit:
        return None, {"error": "unbalanced", "debit": total_debit, "credit": total_credit}

    entry = JournalEntry(
        id=uuid4(), tenant_id=tenant_id, entry_date=result["entry_date"], entry_type=result["entry_type"],
        payroll_period_id=result.get("payroll_period_id"), termination_id=result.get("termination_id"),
        description=result["description"], created_by=created_by,
    )
    session.add(entry)
    await session.flush()
    for l in lines:
        line = JournalEntryLine(
            id=uuid4(), tenant_id=tenant_id, journal_entry_id=entry.id, account_id=l["account_id"],
            branch_id=l.get("branch_id"), debit=l["debit"], credit=l["credit"], description=l.get("description"),
        )
        session.add(line)

    return entry, None
