#!/bin/bash
# ============================================================
# Fase 8 (Cesantía) - Parte 2: core/cesantia.py
# ============================================================
# CAMBIOS:
#   - Nuevo archivo apps/backend/app/core/cesantia.py
#   - Implementa: cálculo de antigüedad, días Art.29 (casos <1 año +
#     tabla acumulativa >=1 año con tope 8 años), promedio salarial
#     (últimos N meses mensual/quincenal, semanal bloqueado como
#     frequency_unsupported), y combinador compute_cesantia_amount()
#     con banderas config_missing/scale_missing/no_history/etc en vez
#     de asumir valores (mismo patrón "blocking cascade" de fases 5-7).
#   - Import de compute_payroll_rows a nivel de módulo (top-level):
#     SEGURO, porque core/payroll.py NO importa core/cesantia.py (igual
#     que aguinaldo.py) - no hay riesgo de import circular aquí.
#   - Interpretación de fracción de año (>6 meses, no ">=6") queda
#     documentada en el docstring del archivo, flageada como pendiente
#     de validación legal (mismo hallazgo ya comunicado en el chat).
# Ejecutar en el servidor: cd /ruta/al/repo && bash fase8_parte2_core_cesantia.sh
# ============================================================
set -e

REPO_DIR="${/opt/workforce-ai-os}"

cat > apps/backend/app/core/cesantia.py << 'PYEOF'
"""
Cesantia (Auxilio de Cesantia) - Codigo de Trabajo Art. 28/29/30, Art. 63
constitucional. Fuente: "Cesantia Art 29.docx" cargado por el cliente
(2026-07-10), tratado como fuente legal autoritativa para esta fase.

Solo aplica cuando la terminacion es CON responsabilidad patronal
(despido injustificado / despido indirecto). Sin responsabilidad
patronal (justa causa, renuncia voluntaria) = 0 dias, sin importar
antiguedad.

Antiguedad (Employee.hire_date -> Termination.termination_date):
  - < 3 meses: 0 dias, sin derecho.
  - 3 a <6 meses: CesantiaConfig.days_3to6_months (real: 7).
  - 6 meses a <1 anio: CesantiaConfig.days_6to12_months (real: 14).
  - >= 1 anio: suma de CesantiaScaleRow.days para year_number 1..N,
    donde N = anios completos (+1 si el resto de meses es
    ESTRICTAMENTE MAYOR a CesantiaConfig.fraction_round_months, real 6).
    N se topa en CesantiaConfig.max_years_cap (real: 8).

    NOTA DE INTERPRETACION (flageada, pendiente validacion legal): el
    documento del cliente se contradice a si mismo - el resumen
    ejecutivo dice "fracciones IGUALES O MAYORES a 6 meses redondean"
    pero la seccion detallada con la tabla dice "SUPERIOR a 6 meses".
    Se adopto la version detallada (estrictamente > 6 meses, umbral
    parametrizado en fraction_round_months) por ser la fuente mas
    especifica del documento.

Salario diario: promedio de gross_pay de los ultimos
CesantiaConfig.months_for_average (real: 6) meses calendario de
planilla antes de la terminacion, dividido entre
CesantiaConfig.daily_divisor (real: 30). Solo se soporta
pay_frequency mensual y quincenal en esta fase (mismo alcance que
core/renta.py) - semanal queda bloqueado explicitamente
(frequency_unsupported) porque el documento distingue un divisor de
26 para empresas no comerciales que no esta definido para este
tenant todavia.
"""
from datetime import date
from typing import Optional
from uuid import UUID

from sqlalchemy import select

from app.core.payroll import compute_payroll_rows
from app.db.models import (
    CesantiaConfig,
    CesantiaScaleRow,
    Contract,
    Employee,
    PayrollPeriod,
)

CESANTIA_SUPPORTED_FREQUENCIES = ("mensual", "quincenal")


def compute_years_months(start: date, end: date):
    """Antiguedad exacta en anios completos + meses de resto."""
    years = end.year - start.year
    months = end.month - start.month
    days = end.day - start.day
    if days < 0:
        months -= 1
    if months < 0:
        years -= 1
        months += 12
    return years, months


async def _get_config(session) -> Optional[CesantiaConfig]:
    result = await session.execute(select(CesantiaConfig))
    return result.scalars().first()


async def _get_scale(session) -> dict:
    result = await session.execute(select(CesantiaScaleRow))
    return {row.year_number: float(row.days) for row in result.scalars().all()}


def compute_cesantia_days(
    years: int, months: int, config: CesantiaConfig, scale: dict
) -> Optional[dict]:
    """Devuelve {days, years_recognized, reason} o None si falta tabla."""
    total_months = years * 12 + months

    if total_months < 3:
        return {"days": 0.0, "years_recognized": 0, "reason": "menos_3_meses"}
    if total_months < 6:
        return {
            "days": float(config.days_3to6_months),
            "years_recognized": 0,
            "reason": "3_a_6_meses",
        }
    if total_months < 12:
        return {
            "days": float(config.days_6to12_months),
            "years_recognized": 0,
            "reason": "6_meses_a_1_anio",
        }

    years_recognized = years
    if months > config.fraction_round_months:
        years_recognized += 1
    years_recognized = min(years_recognized, config.max_years_cap)

    missing_rows = [y for y in range(1, years_recognized + 1) if y not in scale]
    if missing_rows:
        return None

    total_days = sum(scale[y] for y in range(1, years_recognized + 1))
    return {
        "days": round(total_days, 2),
        "years_recognized": years_recognized,
        "reason": "tabla_art29",
    }


async def compute_cesantia_daily_rate(
    session,
    employee_id: UUID,
    pay_frequency: str,
    as_of_date: date,
    config: CesantiaConfig,
    branch_id: Optional[UUID] = None,
):
    """Devuelve (daily_rate, flag). flag en (None, 'partial_history',
    'no_history', 'frequency_unsupported')."""
    if pay_frequency not in CESANTIA_SUPPORTED_FREQUENCIES:
        return None, "frequency_unsupported"

    result = await session.execute(
        select(PayrollPeriod)
        .where(
            PayrollPeriod.pay_frequency == pay_frequency,
            PayrollPeriod.period_end < as_of_date,
        )
        .order_by(PayrollPeriod.period_start.desc())
    )
    periods = result.scalars().all()

    monthly_values = []

    if pay_frequency == "mensual":
        for period in periods[: config.months_for_average]:
            rows = await compute_payroll_rows(
                session, period.period_start, period.period_end, branch_id
            )
            row = next((r for r in rows if r["employee_id"] == employee_id), None)
            if row is not None and row.get("gross_pay") is not None:
                monthly_values.append(row["gross_pay"])
    else:  # quincenal: agrupar en meses calendario (2 quincenas = 1 mes)
        by_month: dict = {}
        for period in periods:
            key = (period.period_start.year, period.period_start.month)
            by_month.setdefault(key, []).append(period)
        for key in sorted(by_month.keys(), reverse=True)[: config.months_for_average]:
            month_total = 0.0
            found_any = False
            for period in by_month[key]:
                rows = await compute_payroll_rows(
                    session, period.period_start, period.period_end, branch_id
                )
                row = next(
                    (r for r in rows if r["employee_id"] == employee_id), None
                )
                if row is not None and row.get("gross_pay") is not None:
                    month_total += row["gross_pay"]
                    found_any = True
            if found_any:
                monthly_values.append(month_total)

    if not monthly_values:
        return None, "no_history"

    monthly_average = sum(monthly_values) / len(monthly_values)
    daily_rate = round(monthly_average / float(config.daily_divisor), 2)
    flag = "partial_history" if len(monthly_values) < config.months_for_average else None
    return daily_rate, flag


async def compute_cesantia_amount(session, termination, branch_id: Optional[UUID] = None) -> dict:
    """Calcula el monto de cesantia para una Termination dada.
    Devuelve un dict con banderas de datos faltantes en vez de asumir
    valores por defecto (patron 'blocking cascade' de fases anteriores)."""
    result = {
        "eligible": False,
        "days": None,
        "years_recognized": None,
        "daily_rate": None,
        "amount": None,
        "config_missing": False,
        "scale_missing": False,
        "frequency_unsupported": False,
        "no_history": False,
        "partial_history": False,
        "employee_missing": False,
        "contract_missing": False,
    }

    if not termination.con_responsabilidad_patronal:
        result["eligible"] = False
        result["days"] = 0.0
        result["amount"] = 0.0
        return result

    result["eligible"] = True

    emp_result = await session.execute(
        select(Employee).where(Employee.id == termination.employee_id)
    )
    employee = emp_result.scalar_one_or_none()
    if employee is None:
        result["employee_missing"] = True
        return result

    config = await _get_config(session)
    if config is None:
        result["config_missing"] = True
        return result

    scale = await _get_scale(session)

    years, months = compute_years_months(employee.hire_date, termination.termination_date)
    days_info = compute_cesantia_days(years, months, config, scale)
    if days_info is None:
        result["scale_missing"] = True
        return result

    result["days"] = days_info["days"]
    result["years_recognized"] = days_info["years_recognized"]

    if days_info["days"] == 0:
        result["amount"] = 0.0
        return result

    contract_result = await session.execute(
        select(Contract)
        .where(Contract.employee_id == termination.employee_id)
        .order_by(Contract.start_date.desc())
    )
    contract = contract_result.scalars().first()
    if contract is None:
        result["contract_missing"] = True
        return result

    daily_rate, flag = await compute_cesantia_daily_rate(
        session,
        termination.employee_id,
        contract.pay_frequency,
        termination.termination_date,
        config,
        branch_id,
    )
    if daily_rate is None:
        if flag == "frequency_unsupported":
            result["frequency_unsupported"] = True
        else:
            result["no_history"] = True
        return result

    if flag == "partial_history":
        result["partial_history"] = True

    result["daily_rate"] = daily_rate
    result["amount"] = round(days_info["days"] * daily_rate, 2)
    return result
PYEOF

echo "OK: apps/backend/app/core/cesantia.py escrito"

python3 -m py_compile apps/backend/app/core/cesantia.py
echo "SYNTAX OK: cesantia.py"
