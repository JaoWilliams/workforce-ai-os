"""
Deducciones para llegar del bruto al neto: CCSS + Renta (Impuesto sobre la
Renta). Alcance de esta fase (confirmado con el usuario 2026-07-10): renta
solo se calcula para pay_frequency mensual y quincenal - la mecanica de
acumulado para semanal/bisemanal no esta definida todavia, esos casos
quedan bloqueados explicitamente (no se asume un prorrateo).

CCSS: reutiliza el catalogo PayrollConcept ya existente (mod. 6) - se suman
todos los conceptos activos con nature=deduccion, origin=empleado. Cero
logica CCSS-especifica hardcodeada: cualquier concepto de deduccion que el
cliente cargue ahi (CCSS-SEM, CCSS-IVM, Banco Popular, etc) se descuenta
igual. calculation_method="cantidad" se excluye para deducciones (no hay
una unidad de "cantidad" clara a nivel de fila de nomina, no se asume).

Renta: tabla de tramos (TaxBracket) y creditos fijos por conyuge/hijo menor
de 25 (RentaCredits), ambos parametrizables por ano fiscal, cero valores
quemados. Mecanica de acumulado quincenal (acordada con el usuario):
- Primera quincena del mes: tabla mensual dividida entre 2, IR provisional
  sobre el bruto de esa quincena, SIN creditos todavia.
- Segunda quincena: se suman los brutos de ambas quincenas, se calcula el
  IR real del mes con la tabla completa, SE APLICAN LOS CREDITOS aqui, se
  resta lo ya retenido en la primera quincena. Si el resultado es negativo,
  es devolucion (se suma al neto de esa quincena, no se descuenta).
  NOTA: el momento exacto en que se aplican los creditos (segunda quincena
  vs. prorrateados en ambas) es una interpretacion razonable del usuario y
  de este desarrollador, NO fue reconfirmada con una fuente legal explicita
  - pendiente de validacion del contador junto con el resto de los valores
  de catalogo (tramos, creditos, factores de recargo).
"""
from datetime import date
from typing import Optional
from uuid import UUID

from sqlalchemy import select

from app.core.payroll import compute_payroll_rows
from app.db.models import Dependent, PayrollConcept, PayrollPeriod, RentaCredits, TaxBracket

RENTA_SUPPORTED_FREQUENCIES = ("mensual", "quincenal")


def _progressive_tax(taxable: float, brackets: list) -> float:
    """brackets: lista de (lower, upper_or_None, rate) ordenada por lower asc."""
    if taxable <= 0:
        return 0.0
    tax = 0.0
    for lower, upper, rate in brackets:
        if taxable <= lower:
            break
        segment_top = upper if upper is not None else taxable
        segment = min(taxable, segment_top) - lower
        if segment > 0:
            tax += float(segment) * (float(rate) / 100)
    return round(tax, 2)


def _halve_brackets(brackets: list) -> list:
    return [
        (lower / 2, (upper / 2) if upper is not None else None, rate)
        for lower, upper, rate in brackets
    ]


async def _load_brackets(session, year: int) -> list:
    result = await session.execute(
        select(TaxBracket).where(TaxBracket.year == year).order_by(TaxBracket.bracket_order)
    )
    rows = result.scalars().all()
    return [
        (float(r.lower_bound), float(r.upper_bound) if r.upper_bound is not None else None, float(r.rate))
        for r in rows
    ]


async def _load_credits(session, year: int):
    result = await session.execute(select(RentaCredits).where(RentaCredits.year == year))
    return result.scalar_one_or_none()


async def _dependents_credit_total(session, employee_id: UUID, credits, as_of: date) -> float:
    result = await session.execute(
        select(Dependent).where(Dependent.employee_id == employee_id, Dependent.active.is_(True))
    )
    dependents = result.scalars().all()
    total = 0.0
    for d in dependents:
        if d.relationship_type == "conyuge":
            total += float(credits.spouse_credit)
        elif d.relationship_type == "hijo" and d.birth_date is not None:
            age = as_of.year - d.birth_date.year - ((as_of.month, as_of.day) < (d.birth_date.month, d.birth_date.day))
            if age < 25:
                total += float(credits.child_credit)
    return round(total, 2)


def _ccss_deduction(gross_pay: float, concepts: list):
    total = 0.0
    detail = []
    for c in concepts:
        if c.nature != "deduccion" or c.origin != "empleado" or not c.active:
            continue
        if c.calculation_method == "porcentaje":
            amount = round(gross_pay * float(c.value) / 100, 2)
        elif c.calculation_method == "monto_fijo":
            amount = round(float(c.value), 2)
        else:
            continue
        total += amount
        detail.append({"code": c.code, "name": c.name, "amount": amount})
    return round(total, 2), detail


async def compute_net_payroll_rows(session, tenant_id: UUID, period: PayrollPeriod, branch_id: Optional[UUID] = None):
    bruto_rows = await compute_payroll_rows(session, period.period_start, period.period_end, branch_id)

    concepts_result = await session.execute(select(PayrollConcept).where(PayrollConcept.active.is_(True)))
    concepts = concepts_result.scalars().all()

    renta_supported = period.pay_frequency in RENTA_SUPPORTED_FREQUENCIES
    year = period.period_start.year
    brackets = await _load_brackets(session, year) if renta_supported else []
    credits = await _load_credits(session, year) if renta_supported else None

    sibling_period = None
    is_second_quincena = False
    if period.pay_frequency == "quincenal":
        siblings_result = await session.execute(
            select(PayrollPeriod).where(PayrollPeriod.pay_frequency == "quincenal").order_by(PayrollPeriod.period_start)
        )
        month_periods = [
            p for p in siblings_result.scalars().all()
            if p.period_start.year == period.period_start.year and p.period_start.month == period.period_start.month
        ]
        if len(month_periods) == 2:
            month_periods.sort(key=lambda p: p.period_start)
            if month_periods[1].id == period.id:
                is_second_quincena = True
                sibling_period = month_periods[0]
            elif month_periods[0].id == period.id:
                sibling_period = month_periods[1]

    net_rows = []
    for row in bruto_rows:
        row = dict(row)
        row.update({
            "ccss_deduction": None, "renta_amount": None, "renta_is_refund": False,
            "net_pay": None, "renta_frequency_unsupported": False,
            "tax_brackets_missing": False, "renta_credits_missing": False,
            "renta_period_pairing_missing": False,
        })

        if row["gross_pay"] is None:
            net_rows.append(row)
            continue

        ccss_total, _detail = _ccss_deduction(row["gross_pay"], concepts)
        row["ccss_deduction"] = ccss_total

        if not renta_supported:
            row["renta_frequency_unsupported"] = True
            net_rows.append(row)
            continue
        if not brackets:
            row["tax_brackets_missing"] = True
            net_rows.append(row)
            continue
        if credits is None:
            row["renta_credits_missing"] = True
            net_rows.append(row)
            continue

        if period.pay_frequency == "mensual":
            credit_total = await _dependents_credit_total(session, row["employee_id"], credits, period.period_end)
            raw_tax = _progressive_tax(row["gross_pay"], brackets)
            renta = max(0.0, round(raw_tax - credit_total, 2))
            row["renta_amount"] = renta
            row["net_pay"] = round(row["gross_pay"] - ccss_total - renta, 2)
            net_rows.append(row)
            continue

        if sibling_period is None:
            row["renta_period_pairing_missing"] = True
            net_rows.append(row)
            continue

        half_brackets = _halve_brackets(brackets)

        if not is_second_quincena:
            renta = _progressive_tax(row["gross_pay"], half_brackets)
            row["renta_amount"] = renta
            row["net_pay"] = round(row["gross_pay"] - ccss_total - renta, 2)
            net_rows.append(row)
            continue

        primera_rows = await compute_payroll_rows(session, sibling_period.period_start, sibling_period.period_end, branch_id)
        primera_row = next((r for r in primera_rows if r["employee_id"] == row["employee_id"]), None)
        if primera_row is None or primera_row.get("gross_pay") is None:
            row["renta_period_pairing_missing"] = True
            net_rows.append(row)
            continue

        primera_gross = primera_row["gross_pay"]
        primera_withheld = _progressive_tax(primera_gross, half_brackets)
        combined_gross = round(primera_gross + row["gross_pay"], 2)
        credit_total = await _dependents_credit_total(session, row["employee_id"], credits, period.period_end)
        real_tax = _progressive_tax(combined_gross, brackets)
        real_tax_after_credits = round(real_tax - credit_total, 2)
        renta_this_period = round(real_tax_after_credits - primera_withheld, 2)

        row["renta_amount"] = renta_this_period
        row["renta_is_refund"] = renta_this_period < 0
        row["net_pay"] = round(row["gross_pay"] - ccss_total - renta_this_period, 2)
        net_rows.append(row)

    return net_rows
