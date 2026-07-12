#!/bin/bash
# ============================================================
# Fase 9 (Asientos contables) - Parte 4d: fix core/accounting.py
# ============================================================
# BUGS ENCONTRADOS (via query real a payroll_concepts):
#   1. AGUINALDO guarda su 8.33% en .value (origin=patronal, concepto
#      puro sin lado empleado) - NO en .employer_value (que quedo NULL).
#      generate_aguinaldo_provision_entry() leia el campo equivocado.
#   2. No existe ningun PayrollConcept con code="RENTA" - el calculo de
#      renta (fase 5) usa TaxBracket/RentaCredits directamente, no pasa
#      por el catalogo de conceptos. El pasivo de renta se resuelve por
#      codigo fijo (PASIVO-RENTA-POR-PAGAR), igual que las demas cuentas
#      sin concepto asociado.
#   3. CCSS-PATRONAL (concepto nuevo de esta fase) debe seguir el mismo
#      patron que AGUINALDO (origin=patronal, tasa en .value) - no
#      employer_value, que es para conceptos con AMBOS lados en la
#      misma fila (patron distinto, no usado aqui).
# Ejecutar: cd /opt/workforce-ai-os && bash fase9_parte4d_fix_accounting.sh
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

python3 << 'PYEOF'
path = "apps/backend/app/core/accounting.py"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

# --- Fix 1: generate_payroll_journal_entry - RENTA por codigo fijo, no por concepto ---
anchor1 = '''    missing = []
    ccss_concept, ccss_account = await _get_concept_with_account(session, "CCSS-EMPLEADO")
    renta_concept, renta_account = await _get_concept_with_account(session, "RENTA")
    salarios_account = await _get_account_by_code(session, "PASIVO-SALARIOS-POR-PAGAR")
    if ccss_account is None:
        missing.append("PayrollConcept CCSS-EMPLEADO.accounting_account_id")
    if renta_account is None:
        missing.append("PayrollConcept RENTA.accounting_account_id")
    if salarios_account is None:
        missing.append("ChartOfAccount PASIVO-SALARIOS-POR-PAGAR")'''
assert anchor1 in src, "ANCHOR NOT FOUND: fix1 (payroll RENTA lookup)"
new1 = '''    missing = []
    ccss_concept, ccss_account = await _get_concept_with_account(session, "CCSS-EMPLEADO")
    renta_account = await _get_account_by_code(session, "PASIVO-RENTA-POR-PAGAR")
    salarios_account = await _get_account_by_code(session, "PASIVO-SALARIOS-POR-PAGAR")
    if ccss_account is None:
        missing.append("PayrollConcept CCSS-EMPLEADO.accounting_account_id")
    if renta_account is None:
        missing.append("ChartOfAccount PASIVO-RENTA-POR-PAGAR (renta no usa PayrollConcept, se resuelve por codigo fijo)")
    if salarios_account is None:
        missing.append("ChartOfAccount PASIVO-SALARIOS-POR-PAGAR")'''
src = src.replace(anchor1, new1)

# --- Fix 2: generate_aguinaldo_provision_entry - leer .value, no .employer_value ---
anchor2 = '''    concept, pasivo_account = await _get_concept_with_account(session, "AGUINALDO")
    gasto_account = await _get_account_by_code(session, "GASTO-AGUINALDO-PROVISION")
    missing = []
    if concept is None or concept.employer_value is None:
        missing.append("PayrollConcept AGUINALDO.employer_value")
    if pasivo_account is None:
        missing.append("PayrollConcept AGUINALDO.accounting_account_id")
    if gasto_account is None:
        missing.append("ChartOfAccount GASTO-AGUINALDO-PROVISION")
    if missing:
        return {"error": "missing_accounts", "missing": missing}

    gross_total = sum(r["gross_pay"] for r in rows)
    rate = float(concept.employer_value) / 100.0'''
assert anchor2 in src, "ANCHOR NOT FOUND: fix2 (aguinaldo provision rate)"
new2 = '''    concept, pasivo_account = await _get_concept_with_account(session, "AGUINALDO")
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
    rate = float(concept.value) / 100.0'''
src = src.replace(anchor2, new2)

# --- Fix 3: generate_ccss_patronal_entry - leer .value, no .employer_value ---
anchor3 = '''    concept, pasivo_account = await _get_concept_with_account(session, "CCSS-PATRONAL")
    gasto_account = await _get_account_by_code(session, "GASTO-CCSS-PATRONAL")
    missing = []
    if concept is None or concept.employer_value is None:
        missing.append("PayrollConcept CCSS-PATRONAL.employer_value")
    if pasivo_account is None:
        missing.append("PayrollConcept CCSS-PATRONAL.accounting_account_id")
    if gasto_account is None:
        missing.append("ChartOfAccount GASTO-CCSS-PATRONAL")
    if missing:
        return {"error": "missing_accounts", "missing": missing}

    gross_total = sum(r["gross_pay"] for r in rows)
    rate = float(concept.employer_value) / 100.0'''
assert anchor3 in src, "ANCHOR NOT FOUND: fix3 (ccss patronal rate)"
new3 = '''    concept, pasivo_account = await _get_concept_with_account(session, "CCSS-PATRONAL")
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
    rate = float(concept.value) / 100.0'''
src = src.replace(anchor3, new3)

with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("OK: core/accounting.py corregido (RENTA por codigo fijo, AGUINALDO/CCSS-PATRONAL leen .value)")
PYEOF

python3 -m py_compile apps/backend/app/core/accounting.py && echo "SYNTAX OK: accounting.py"
