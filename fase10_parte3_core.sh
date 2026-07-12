#!/bin/bash
# ============================================================
# Fase 10 (Archivo bancario) - Parte 3: core/bank_file.py (nuevo)
# ============================================================
# Genera las filas del archivo de transferencia bancaria a partir del
# neto ya calculado (compute_net_payroll_rows, fase 5 - no se reinventa
# el calculo, solo se consume). Formato de salida: exactamente el que
# diste como ejemplo real -- tipo_cuenta \t numero_cuenta \t monto \t
# glosa, sin encabezado, monto con 2 decimales fijos.
#
# Patron blocking-cascade de siempre: si falta la config de glosa, no
# se genera nada. Si a un empleado le falta tipo/numero de cuenta, ESE
# empleado se excluye del archivo y queda listado en "missing" (no
# bloquea a los demas) -- igual que vacaciones excluye empleados con
# balance no resoluble.
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

cat > apps/backend/app/core/bank_file.py << 'PYEOF'
"""
Archivo de transferencia bancaria (Nomina fase 10).

Formato de salida (confirmado por el cliente con un ejemplo real de su
banco, no inventado): texto plano delimitado por TAB, sin encabezado,
4 columnas por linea:

    tipo_cuenta \t numero_cuenta \t monto (2 decimales) \t glosa

La glosa (ej. "PLANILLA EMPRESARIAL BURGER KING COSTA RICA") es un
valor real del cliente, cargado en el catalogo BankFileConfig (1 fila
por tenant) -- nunca hardcodeada en este modulo.

El tipo y numero de cuenta bancaria de cada empleado se cargan en
Employee.bank_account_type / bank_account_number (nullable -- se
completan despues del alta, via PATCH /api/employees/{id}).

Cada generacion real queda persistida (BankTransferFile + lineas) para
auditoria: que se genero, cuando, por cuanto, y que empleados quedaron
fuera por falta de datos bancarios.
"""
from typing import Optional
from uuid import UUID, uuid4

from sqlalchemy import select

from app.db.models import BankFileConfig, BankTransferFile, BankTransferFileLine, Employee, PayrollPeriod


async def _get_bank_file_config(session, tenant_id: UUID) -> Optional[BankFileConfig]:
    result = await session.execute(select(BankFileConfig).where(BankFileConfig.tenant_id == tenant_id))
    return result.scalars().first()


async def generate_bank_transfer_rows(session, tenant_id: UUID, period: PayrollPeriod, branch_id: Optional[UUID] = None) -> dict:
    """
    Devuelve {"rows": [...], "missing": [...], "total_amount": float,
    "row_count": int} sin persistir nada -- permite previsualizar antes
    de guardar. Si falta la config de glosa, devuelve
    {"error": "bank_config_missing"} y no calcula nada mas.
    """
    config = await _get_bank_file_config(session, tenant_id)
    if config is None or not config.active:
        return {"error": "bank_config_missing"}

    # Import local (no al tope del archivo) a proposito: permite en los
    # tests monkeypatchear renta_mod.compute_net_payroll_rows sin tocar
    # este modulo, mismo patron ya usado en core/accounting.py.
    from app.core.renta import compute_net_payroll_rows

    net_rows = await compute_net_payroll_rows(session, tenant_id, period, branch_id)

    employee_ids = [r["employee_id"] for r in net_rows]
    employees_result = await session.execute(select(Employee).where(Employee.id.in_(employee_ids)))
    employee_by_id = {e.id: e for e in employees_result.scalars().all()}

    rows = []
    missing = []
    for row in net_rows:
        employee = employee_by_id.get(row["employee_id"])
        employee_name = f"{employee.first_name} {employee.last_name}" if employee else None

        if row.get("net_pay") is None:
            missing.append({"employee_id": row["employee_id"], "employee_name": employee_name, "reason": "net_pay_not_computable"})
            continue
        if employee is None:
            missing.append({"employee_id": row["employee_id"], "employee_name": None, "reason": "employee_not_found"})
            continue
        if row["net_pay"] <= 0:
            missing.append({"employee_id": employee.id, "employee_name": employee_name, "reason": "zero_or_negative_net_pay"})
            continue
        if not employee.bank_account_type or not employee.bank_account_number:
            missing.append({"employee_id": employee.id, "employee_name": employee_name, "reason": "missing_bank_account"})
            continue

        rows.append({
            "employee_id": employee.id,
            "account_type": employee.bank_account_type,
            "account_number": employee.bank_account_number,
            "amount": round(float(row["net_pay"]), 2),
            "glosa": config.glosa,
        })

    total_amount = round(sum(r["amount"] for r in rows), 2)
    return {"rows": rows, "missing": missing, "total_amount": total_amount, "row_count": len(rows)}


async def persist_bank_transfer_file(session, tenant_id: UUID, payroll_period_id: UUID, branch_id: Optional[UUID], result: dict, created_by: Optional[UUID]) -> dict:
    """
    Persiste el resultado de generate_bank_transfer_rows como
    BankTransferFile + BankTransferFileLine. No persiste nada si hubo
    error o si no quedo ninguna fila valida (todos los empleados
    excluidos por falta de datos).
    """
    if "error" in result:
        return result
    if result["row_count"] == 0:
        return {"error": "no_valid_rows", "missing": result["missing"]}

    header = BankTransferFile(
        id=uuid4(),
        tenant_id=tenant_id,
        payroll_period_id=payroll_period_id,
        branch_id=branch_id,
        row_count=result["row_count"],
        total_amount=result["total_amount"],
        missing_count=len(result["missing"]),
        created_by=created_by,
    )
    session.add(header)
    await session.flush()  # necesario: sin relationship() declarada, el FK de las lineas necesita el id ya insertado

    for row in result["rows"]:
        session.add(BankTransferFileLine(
            id=uuid4(),
            tenant_id=tenant_id,
            bank_transfer_file_id=header.id,
            employee_id=row["employee_id"],
            account_type=row["account_type"],
            account_number=row["account_number"],
            amount=row["amount"],
            glosa=row["glosa"],
        ))

    await session.commit()
    await session.refresh(header)
    return {
        "bank_transfer_file_id": header.id,
        "row_count": header.row_count,
        "total_amount": header.total_amount,
        "missing_count": header.missing_count,
        "missing": result["missing"],
    }


def render_bank_transfer_txt(lines: list) -> str:
    """
    lines: lista de dicts con account_type/account_number/amount/glosa
    (tipicamente BankTransferFileLine ya persistidas, para que el
    archivo exportado sea el historico exacto aunque los datos del
    empleado hayan cambiado despues).
    Formato exacto del ejemplo real: TAB entre columnas, sin encabezado,
    monto con 2 decimales fijos, salto de linea simple.
    """
    out_lines = []
    for l in lines:
        amount = float(l["amount"])
        out_lines.append(f"{l['account_type']}\t{l['account_number']}\t{amount:.2f}\t{l['glosa']}")
    return "\n".join(out_lines)
PYEOF

python3 -m py_compile apps/backend/app/core/bank_file.py && echo "SYNTAX OK: core/bank_file.py"

echo "=== FIN Parte 3 (core) ==="
