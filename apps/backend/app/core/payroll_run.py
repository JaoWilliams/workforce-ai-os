"""
Orquestacion y auto-validacion de la corrida de nomina (Nomina fase 11).

Maquina de estados sobre PayrollPeriod.status, estrictamente secuencial
(un solo paso hacia adelante por vez, sin saltos):

    draft -> validado -> calculado -> aprobado -> pagado -> contabilizado -> archivo_bancario

Cada transicion tiene su propia validacion proactiva (patron
blocking-cascade de siempre: si falta algo, no se permite avanzar, y
se explica exactamente que falta):

- draft -> validado: catalogos requeridos para calcular existen
  (TaxBracket/RentaCredits del ano, concepto CCSS-EMPLEADO activo,
  PayrollHoursConfig de la frecuencia del periodo).
- validado -> calculado: compute_net_payroll_rows no puede tener
  ninguna fila bloqueada (gross_pay o net_pay en None) - se congela el
  snapshot inmutable (PayrollSnapshotLine) y se corren las reglas de
  anomalia que no dependen del archivo bancario.
- calculado -> aprobado: todos los TrustFlag de este periodo deben
  estar resueltos (revision humana obligatoria de cada anomalia
  detectada antes de aprobar el pago).
- aprobado -> pagado: confirmacion manual (no hay forma de verificar
  desde el sistema que el dinero salio del banco).
- pagado -> contabilizado: debe existir un JournalEntry tipo 'planilla'
  para este periodo (fase 9 - generarlo antes de este paso).
- contabilizado -> archivo_bancario: debe existir un BankTransferFile
  para este periodo (fase 10 - generarlo antes de este paso). Ademas
  se corre la regla de anomalia que si depende del archivo bancario
  (cuenta bancaria cambiada justo antes del pago, via AuditLog).

Snapshot inmutable: una vez que un periodo pasa a 'calculado', los
consumidores downstream (core/accounting.py, core/bank_file.py) deben
preferir el snapshot congelado sobre recalcular en vivo -
get_net_payroll_rows_for_period() es el punto unico de lectura para
eso, con fallback a calculo en vivo si el periodo todavia no llego a
'calculado'.
"""
from datetime import timedelta
from typing import Optional
from uuid import UUID, uuid4

from sqlalchemy import delete, select

from app.core.audit import log_audit
from app.db.models import (
    AuditLog,
    BankTransferFile,
    BankTransferFileLine,
    Branch,
    JournalEntry,
    PayrollAnomalyConfig,
    PayrollConcept,
    PayrollHoursConfig,
    PayrollPeriod,
    PayrollSnapshotLine,
    RentaCredits,
    TaxBracket,
    Termination,
    TrustFlag,
)

VALID_TRANSITIONS = {
    "draft": "validado",
    "validado": "calculado",
    "calculado": "aprobado",
    "aprobado": "pagado",
    "pagado": "contabilizado",
    "contabilizado": "archivo_bancario",
}

ALL_STATUSES = ["draft"] + list(VALID_TRANSITIONS.values())


def _json_safe(row: dict) -> dict:
    safe = {}
    for k, v in row.items():
        if isinstance(v, UUID):
            safe[k] = str(v)
        else:
            safe[k] = v
    return safe


async def get_net_payroll_rows_for_period(session, tenant_id: UUID, period: PayrollPeriod, branch_id: Optional[UUID] = None) -> list:
    """
    Punto unico de lectura para el neto de un periodo. Si el periodo ya
    tiene snapshot congelado (paso por 'calculado'), devuelve esas
    filas inmutables. Si no, recalcula en vivo (periodos que todavia no
    llegaron a 'calculado', o llamadas fuera del pipeline de fase 11).
    """
    result = await session.execute(
        select(PayrollSnapshotLine).where(PayrollSnapshotLine.payroll_period_id == period.id)
    )
    snapshot_lines = result.scalars().all()
    if snapshot_lines:
        rows = []
        for line in snapshot_lines:
            if branch_id is not None and line.branch_id != branch_id:
                continue
            row = dict(line.detail) if line.detail else {}
            row.update({
                "employee_id": line.employee_id,
                "branch_id": line.branch_id,
                "gross_pay": float(line.gross_pay) if line.gross_pay is not None else None,
                "ccss_deduction": float(line.ccss_deduction) if line.ccss_deduction is not None else None,
                "renta_amount": float(line.renta_amount) if line.renta_amount is not None else None,
                "renta_is_refund": line.renta_is_refund,
                "net_pay": float(line.net_pay) if line.net_pay is not None else None,
            })
            rows.append(row)
        return rows

    # Import local a proposito (mismo patron ya usado en core/accounting.py y
    # core/bank_file.py): permite monkeypatchear renta_mod.compute_net_payroll_rows
    # en los tests sin tocar este modulo.
    from app.core.renta import compute_net_payroll_rows
    return await compute_net_payroll_rows(session, tenant_id, period, branch_id)


async def _validate_catalogs_for_validado(session, tenant_id: UUID, period: PayrollPeriod) -> list:
    missing = []
    year = period.period_start.year
    brackets = await session.execute(select(TaxBracket).where(TaxBracket.year == year))
    if not brackets.scalars().first():
        missing.append(f"TaxBracket para el ano {year}")
    credits = await session.execute(select(RentaCredits).where(RentaCredits.year == year))
    if not credits.scalars().first():
        missing.append(f"RentaCredits para el ano {year}")
    ccss = await session.execute(
        select(PayrollConcept).where(PayrollConcept.code == "CCSS-EMPLEADO", PayrollConcept.active.is_(True))
    )
    if not ccss.scalars().first():
        missing.append("PayrollConcept CCSS-EMPLEADO activo")
    hours_config = await session.execute(
        select(PayrollHoursConfig).where(PayrollHoursConfig.pay_frequency == period.pay_frequency)
    )
    if not hours_config.scalars().first():
        missing.append(f"PayrollHoursConfig para la frecuencia '{period.pay_frequency}'")
    return missing


async def _freeze_snapshot(session, tenant_id: UUID, period: PayrollPeriod) -> dict:
    from app.core.renta import compute_net_payroll_rows
    rows = await compute_net_payroll_rows(session, tenant_id, period, None)
    if not rows:
        return {"error": "no_rows"}
    blocked = [r for r in rows if r.get("gross_pay") is None or r.get("net_pay") is None]
    if blocked:
        return {"error": "blocked_rows", "count": len(blocked), "employee_ids": [str(r["employee_id"]) for r in blocked]}

    await session.execute(delete(PayrollSnapshotLine).where(PayrollSnapshotLine.payroll_period_id == period.id))
    for r in rows:
        session.add(PayrollSnapshotLine(
            id=uuid4(), tenant_id=tenant_id, payroll_period_id=period.id, employee_id=r["employee_id"],
            branch_id=r.get("branch_id"), gross_pay=r.get("gross_pay"), ccss_deduction=r.get("ccss_deduction"),
            renta_amount=r.get("renta_amount"), renta_is_refund=bool(r.get("renta_is_refund")),
            net_pay=r.get("net_pay"), detail=_json_safe(r),
        ))
    await session.flush()
    return {"error": None, "row_count": len(rows)}


def _rule_zero_or_negative(tenant_id: UUID, period: PayrollPeriod, snapshot_lines: list) -> list:
    flags = []
    for line in snapshot_lines:
        if line.net_pay is not None and float(line.net_pay) <= 0:
            flags.append(TrustFlag(
                id=uuid4(), tenant_id=tenant_id, employee_id=line.employee_id,
                payroll_period_id=period.id, branch_id=line.branch_id,
                rule_code="payroll_net_zero_or_negative", severity="high",
                details={"net_pay": float(line.net_pay), "reason": "El neto calculado es cero o negativo"},
                resolved=False,
            ))
    return flags


async def _rule_paid_after_termination(session, tenant_id: UUID, period: PayrollPeriod, snapshot_lines: list) -> list:
    flags = []
    employee_ids = [l.employee_id for l in snapshot_lines]
    if not employee_ids:
        return flags
    term_result = await session.execute(
        select(Termination).where(
            Termination.employee_id.in_(employee_ids),
            Termination.status == "approved",
            Termination.termination_date <= period.period_end,
        )
    )
    terminations_by_employee = {t.employee_id: t for t in term_result.scalars().all()}
    for line in snapshot_lines:
        term = terminations_by_employee.get(line.employee_id)
        if term is not None and line.net_pay is not None and float(line.net_pay) > 0:
            flags.append(TrustFlag(
                id=uuid4(), tenant_id=tenant_id, employee_id=line.employee_id,
                payroll_period_id=period.id, branch_id=line.branch_id,
                rule_code="payroll_paid_after_termination", severity="high",
                details={
                    "termination_id": str(term.id), "termination_date": term.termination_date.isoformat(),
                    "net_pay": float(line.net_pay),
                    "reason": "Empleado con terminacion aprobada sigue apareciendo con pago en esta corrida",
                },
                resolved=False,
            ))
    return flags


async def _rule_net_deviation(session, tenant_id: UUID, period: PayrollPeriod, snapshot_lines: list, config: PayrollAnomalyConfig) -> list:
    flags = []
    prev_period_result = await session.execute(
        select(PayrollPeriod).where(
            PayrollPeriod.tenant_id == tenant_id,
            PayrollPeriod.pay_frequency == period.pay_frequency,
            PayrollPeriod.period_start < period.period_start,
        ).order_by(PayrollPeriod.period_start.desc()).limit(1)
    )
    prev_period = prev_period_result.scalar_one_or_none()
    if prev_period is None:
        return flags
    prev_lines_result = await session.execute(
        select(PayrollSnapshotLine).where(PayrollSnapshotLine.payroll_period_id == prev_period.id)
    )
    prev_by_employee = {l.employee_id: l for l in prev_lines_result.scalars().all()}
    threshold = float(config.net_deviation_pct_threshold)
    for line in snapshot_lines:
        prev_line = prev_by_employee.get(line.employee_id)
        if prev_line is None or prev_line.net_pay is None or line.net_pay is None:
            continue
        prev_net = float(prev_line.net_pay)
        if prev_net == 0:
            continue
        pct = abs(float(line.net_pay) - prev_net) / abs(prev_net) * 100
        if pct >= threshold:
            flags.append(TrustFlag(
                id=uuid4(), tenant_id=tenant_id, employee_id=line.employee_id,
                payroll_period_id=period.id, branch_id=line.branch_id,
                rule_code="payroll_net_deviation", severity="medium",
                details={
                    "previous_period_id": str(prev_period.id), "previous_net_pay": prev_net,
                    "current_net_pay": float(line.net_pay), "pct_change": round(pct, 1),
                    "threshold_pct": threshold,
                    "reason": f"El neto cambio {pct:.1f}% respecto al periodo anterior",
                },
                resolved=False,
            ))
    return flags


async def _rule_overtime_outlier(session, tenant_id: UUID, period: PayrollPeriod, snapshot_lines: list, config: PayrollAnomalyConfig) -> list:
    flags = []
    multiplier = float(config.overtime_hours_multiplier_threshold)
    prev_periods_result = await session.execute(
        select(PayrollPeriod).where(
            PayrollPeriod.tenant_id == tenant_id,
            PayrollPeriod.pay_frequency == period.pay_frequency,
            PayrollPeriod.period_start < period.period_start,
        ).order_by(PayrollPeriod.period_start.desc()).limit(3)
    )
    prev_periods = prev_periods_result.scalars().all()
    if not prev_periods:
        return flags
    prev_ids = [p.id for p in prev_periods]
    prev_lines_result = await session.execute(
        select(PayrollSnapshotLine).where(PayrollSnapshotLine.payroll_period_id.in_(prev_ids))
    )
    history_by_employee = {}
    for l in prev_lines_result.scalars().all():
        hours = (l.detail or {}).get("overtime_extra_hours")
        if hours is not None:
            history_by_employee.setdefault(l.employee_id, []).append(float(hours))
    for line in snapshot_lines:
        current_hours = (line.detail or {}).get("overtime_extra_hours")
        if not current_hours or current_hours <= 5:
            continue
        history = history_by_employee.get(line.employee_id)
        if not history:
            continue
        avg = sum(history) / len(history)
        if avg > 0 and current_hours > avg * multiplier:
            flags.append(TrustFlag(
                id=uuid4(), tenant_id=tenant_id, employee_id=line.employee_id,
                payroll_period_id=period.id, branch_id=line.branch_id,
                rule_code="payroll_overtime_outlier", severity="medium",
                details={
                    "current_extra_hours": current_hours, "historical_average_hours": round(avg, 1),
                    "multiplier_threshold": multiplier,
                    "reason": f"Horas extra ({current_hours}) muy por encima del promedio historico ({avg:.1f})",
                },
                resolved=False,
            ))
    return flags


async def _rule_branch_net_outlier(session, tenant_id: UUID, period: PayrollPeriod, snapshot_lines: list, config: PayrollAnomalyConfig) -> list:
    flags = []
    threshold = float(config.branch_net_deviation_pct_threshold)
    totals_by_branch = {}
    for line in snapshot_lines:
        if line.branch_id is None or line.net_pay is None:
            continue
        totals_by_branch[line.branch_id] = totals_by_branch.get(line.branch_id, 0.0) + float(line.net_pay)
    if len(totals_by_branch) < 2:
        return flags
    branch_result = await session.execute(select(Branch).where(Branch.id.in_(totals_by_branch.keys())))
    branches_by_id = {b.id: b for b in branch_result.scalars().all()}
    for bid, total in totals_by_branch.items():
        others = [v for k, v in totals_by_branch.items() if k != bid]
        avg_others = sum(others) / len(others)
        if avg_others == 0:
            continue
        pct = abs(total - avg_others) / avg_others * 100
        if pct >= threshold:
            branch = branches_by_id.get(bid)
            flags.append(TrustFlag(
                id=uuid4(), tenant_id=tenant_id, employee_id=None,
                payroll_period_id=period.id, branch_id=bid,
                rule_code="payroll_branch_net_outlier", severity="medium",
                details={
                    "branch_name": branch.name if branch else None, "branch_total_net": round(total, 2),
                    "average_other_branches": round(avg_others, 2), "pct_deviation": round(pct, 1),
                    "threshold_pct": threshold,
                    "reason": f"El neto total de esta sucursal se desvia {pct:.1f}% del promedio de las demas",
                },
                resolved=False,
            ))
    return flags


async def run_anomaly_checks_on_calculate(session, tenant_id: UUID, period: PayrollPeriod) -> dict:
    config_result = await session.execute(select(PayrollAnomalyConfig))
    config = config_result.scalars().first()

    snapshot_result = await session.execute(
        select(PayrollSnapshotLine).where(PayrollSnapshotLine.payroll_period_id == period.id)
    )
    snapshot_lines = snapshot_result.scalars().all()

    flags = []
    flags += _rule_zero_or_negative(tenant_id, period, snapshot_lines)
    flags += await _rule_paid_after_termination(session, tenant_id, period, snapshot_lines)
    if config is not None:
        flags += await _rule_net_deviation(session, tenant_id, period, snapshot_lines, config)
        flags += await _rule_overtime_outlier(session, tenant_id, period, snapshot_lines, config)
        flags += await _rule_branch_net_outlier(session, tenant_id, period, snapshot_lines, config)

    for f in flags:
        session.add(f)
    await session.flush()
    return {"skipped": config is None, "flags_created": len(flags)}


async def run_anomaly_checks_on_bank_file(session, tenant_id: UUID, period: PayrollPeriod, bank_file: BankTransferFile) -> dict:
    config_result = await session.execute(select(PayrollAnomalyConfig))
    config = config_result.scalars().first()
    if config is None:
        return {"skipped": True, "reason": "config_missing", "flags_created": 0}

    window = timedelta(days=int(config.bank_account_change_window_days))
    lines_result = await session.execute(
        select(BankTransferFileLine).where(BankTransferFileLine.bank_transfer_file_id == bank_file.id)
    )
    lines = lines_result.scalars().all()
    flags = []
    for line in lines:
        audit_result = await session.execute(
            select(AuditLog).where(
                AuditLog.action == "employee.updated",
                AuditLog.resource_type == "employee",
                AuditLog.resource_id == line.employee_id,
                AuditLog.extra.has_key("bank_account_number"),
                AuditLog.created_at >= bank_file.generated_at - window,
                AuditLog.created_at <= bank_file.generated_at,
            ).order_by(AuditLog.created_at.desc())
        )
        change = audit_result.scalars().first()
        if change is not None:
            days_before = (bank_file.generated_at - change.created_at).total_seconds() / 86400
            flags.append(TrustFlag(
                id=uuid4(), tenant_id=tenant_id, employee_id=line.employee_id,
                payroll_period_id=period.id, branch_id=None,
                rule_code="payroll_bank_account_changed_before_payment", severity="high",
                details={
                    "changed_at": change.created_at.isoformat(), "days_before_payment": round(days_before, 1),
                    "window_days": config.bank_account_change_window_days,
                    "new_account_number": change.extra.get("bank_account_number"),
                    "reason": f"La cuenta bancaria cambio {days_before:.1f} dias antes de generarse este pago",
                },
                resolved=False,
            ))
    for f in flags:
        session.add(f)
    await session.flush()
    return {"skipped": False, "flags_created": len(flags)}


async def validate_transition(session, tenant_id: UUID, period: PayrollPeriod, target_status: str) -> dict:
    current = period.status
    expected_next = VALID_TRANSITIONS.get(current)
    if expected_next != target_status:
        return {"error": "invalid_transition", "from": current, "to": target_status, "expected_next": expected_next}

    if target_status == "validado":
        missing = await _validate_catalogs_for_validado(session, tenant_id, period)
        if missing:
            return {"error": "missing_catalogs", "missing": missing}
        return {"error": None}

    if target_status == "calculado":
        return {"error": None}

    if target_status == "aprobado":
        unresolved_result = await session.execute(
            select(TrustFlag).where(TrustFlag.payroll_period_id == period.id, TrustFlag.resolved.is_(False))
        )
        unresolved = unresolved_result.scalars().all()
        if unresolved:
            return {"error": "unresolved_flags", "count": len(unresolved), "flag_ids": [str(f.id) for f in unresolved]}
        return {"error": None}

    if target_status == "pagado":
        return {"error": None}

    if target_status == "contabilizado":
        entry_result = await session.execute(
            select(JournalEntry).where(JournalEntry.payroll_period_id == period.id, JournalEntry.entry_type == "planilla")
        )
        if entry_result.scalars().first() is None:
            return {"error": "accounting_entry_missing"}
        return {"error": None}

    if target_status == "archivo_bancario":
        file_result = await session.execute(
            select(BankTransferFile).where(BankTransferFile.payroll_period_id == period.id)
        )
        bank_file = file_result.scalars().first()
        if bank_file is None:
            return {"error": "bank_file_missing"}
        return {"error": None, "bank_file": bank_file}

    return {"error": "unknown_target_status"}


async def transition_period(session, tenant_id: UUID, period: PayrollPeriod, target_status: str, actor_user_id: Optional[UUID]) -> dict:
    validation = await validate_transition(session, tenant_id, period, target_status)
    if validation.get("error"):
        return validation

    extra_info = {}
    if target_status == "calculado":
        freeze_result = await _freeze_snapshot(session, tenant_id, period)
        if freeze_result.get("error"):
            return freeze_result
        extra_info["snapshot_row_count"] = freeze_result["row_count"]
        anomaly_result = await run_anomaly_checks_on_calculate(session, tenant_id, period)
        extra_info["anomaly_check"] = anomaly_result

    if target_status == "archivo_bancario":
        bank_file = validation["bank_file"]
        anomaly_result = await run_anomaly_checks_on_bank_file(session, tenant_id, period, bank_file)
        extra_info["anomaly_check"] = anomaly_result

    old_status = period.status
    period.status = target_status
    await log_audit(
        session, tenant_id=tenant_id, actor_user_id=actor_user_id,
        action="payroll_period.transitioned", resource_type="payroll_period", resource_id=period.id,
        extra={"from": old_status, "to": target_status, **extra_info},
    )
    await session.commit()
    await session.refresh(period)
    return {"error": None, "from": old_status, "to": target_status, **extra_info}
