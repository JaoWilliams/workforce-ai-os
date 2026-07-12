#!/bin/bash
# ============================================================
# UI/UX Nomina - Parte 3c: sidebar + i18n (pendientes) + build
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

# ---------- 1. agregar item al sidebar (grupo NOMINA) ----------
python3 << 'PYEOF'
path = "apps/frontend/app/[locale]/dashboard/layout.js"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

anchor = '''  {
    key: "nomina",
    icon: Wallet,
    items: [
      { key: "payroll", href: "/nomina", permission: "payroll.view" },
    ],
  },'''
assert anchor in src, "ANCHOR NOT FOUND: grupo nomina en NAV_GROUPS"
assert src.count(anchor) == 1, "ANCHOR NOT UNIQUE: grupo nomina en NAV_GROUPS"

nuevo = '''  {
    key: "nomina",
    icon: Wallet,
    items: [
      { key: "payroll", href: "/nomina", permission: "payroll.view" },
      { key: "payroll_runs", href: "/nomina/corridas", permission: "payroll.view" },
    ],
  },'''
src = src.replace(anchor, nuevo, 1)

with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("OK: item 'payroll_runs' agregado al grupo NOMINA del sidebar")
PYEOF

# ---------- 2. i18n: nav.payroll_runs + namespace payroll_run (ES/EN) ----------
python3 << 'PYEOF'
import json

nav_es = {"payroll_runs": "Corridas de Nómina"}
nav_en = {"payroll_runs": "Payroll Runs"}

payroll_run_es = {
    "title": "Corridas de Nómina",
    "subtitle": "Orquestación y auto-validación del pago de planilla",
    "new_run": "Nueva corrida",
    "back_to_list": "Volver a corridas",
    "no_periods": "Todavía no hay corridas creadas",
    "create_title": "Nueva corrida de nómina",
    "field_frequency": "Frecuencia de pago",
    "field_period_start": "Inicio del período",
    "field_period_end": "Fin del período",
    "field_pay_date": "Fecha de pago",
    "field_notes": "Notas (opcional)",
    "create_submit": "Crear corrida",
    "create_cancel": "Cancelar",
    "create_ok_toast": "Corrida creada correctamente",
    "status_draft": "Borrador",
    "status_validado": "Validado",
    "status_calculado": "Calculado",
    "status_aprobado": "Aprobado",
    "status_pagado": "Pagado",
    "status_contabilizado": "Contabilizado",
    "status_archivo_bancario": "Archivo Bancario",
    "step_draft_title": "Borrador",
    "step_draft_desc": "El período está creado pero todavía no se validaron los catálogos necesarios para calcular la nómina.",
    "step_draft_action": "Validar catálogos",
    "step_validado_title": "Validado",
    "step_validado_desc": "Los catálogos necesarios (tramos de renta, créditos, CCSS, horas estándar) están completos. Listo para calcular.",
    "step_validado_action": "Calcular nómina",
    "step_calculado_title": "Calculado",
    "step_calculado_desc": "El resultado por empleado quedó congelado (snapshot inmutable). Resolvé todas las anomalías detectadas antes de aprobar.",
    "step_calculado_action": "Aprobar corrida",
    "step_calculado_blocked": "Hay {count} anomalía(s) sin resolver",
    "step_aprobado_title": "Aprobado",
    "step_aprobado_desc": "La corrida fue aprobada. Confirmá manualmente cuando el pago haya salido del banco.",
    "step_aprobado_action": "Marcar como pagado",
    "step_pagado_title": "Pagado",
    "step_pagado_desc": "Generá el asiento contable de planilla para poder contabilizar este período.",
    "step_pagado_action_generate": "Generar asiento contable",
    "step_pagado_action_next": "Contabilizar",
    "step_contabilizado_title": "Contabilizado",
    "step_contabilizado_desc": "Generá el archivo bancario para el depósito de planilla.",
    "step_contabilizado_action_generate": "Generar archivo bancario",
    "step_contabilizado_action_next": "Cerrar corrida",
    "step_archivo_bancario_title": "Archivo Bancario",
    "step_archivo_bancario_desc": "Corrida completa. El archivo bancario está listo para subir al banco.",
    "step_archivo_bancario_download": "Descargar archivo TXT",
    "snapshot_title": "Resultado por empleado (congelado)",
    "net_preview_title": "Vista previa del cálculo",
    "anomaly_queue_title": "Cola de anomalías",
    "anomaly_none": "Sin anomalías detectadas",
    "anomaly_resolve": "Resolver",
    "anomaly_resolved_toast": "Anomalía marcada como resuelta",
    "rule_payroll_net_zero_or_negative": "Neto cero o negativo",
    "rule_payroll_paid_after_termination": "Pago después de terminación",
    "rule_payroll_net_deviation": "Desviación de neto",
    "rule_payroll_overtime_outlier": "Horas extra atípicas",
    "rule_payroll_branch_net_outlier": "Sucursal atípica",
    "rule_payroll_bank_account_changed_before_payment": "Cuenta bancaria cambiada",
    "severity_high": "Alta",
    "severity_medium": "Media",
    "col_employee": "Empleado",
    "col_gross": "Bruto",
    "col_ccss": "CCSS",
    "col_renta": "Renta",
    "col_net": "Neto",
    "no_data": "No hay datos para mostrar",
    "journal_entry_title": "Asiento contable generado",
    "journal_entry_total": "Total",
    "bank_file_title": "Archivo bancario generado",
    "bank_file_rows": "{count} empleado(s) incluidos",
    "bank_file_missing": "{count} empleado(s) excluidos",
    "transition_ok_toast": "Estado actualizado correctamente",
    "generating": "Generando...",
    "error_invalid_transition": "No se puede pasar directamente a este estado.",
    "error_missing_catalogs": "Faltan catálogos necesarios:",
    "error_blocked_rows": "{count} empleado(s) tienen datos bloqueados. Revisá Nómina Bruta.",
    "error_unresolved_flags": "Hay {count} anomalía(s) sin resolver.",
    "error_accounting_entry_missing": "Todavía no se generó el asiento contable.",
    "error_bank_file_missing": "Todavía no se generó el archivo bancario.",
    "error_bank_config_missing": "Falta configurar la glosa del archivo bancario.",
    "error_no_valid_rows": "Ningún empleado válido para el archivo bancario.",
    "error_no_rows": "No hay filas de nómina calculables para este período.",
    "error_missing_accounts": "Faltan cuentas contables configuradas.",
    "error_zero_amount": "El monto total calculado es cero.",
    "error_unbalanced": "El asiento no cuadra (debe distinto de haber).",
    "error_generic": "No se pudo completar la acción.",
}

payroll_run_en = {
    "title": "Payroll Runs",
    "subtitle": "Orchestration and auto-validation of the payroll run",
    "new_run": "New run",
    "back_to_list": "Back to runs",
    "no_periods": "No runs created yet",
    "create_title": "New payroll run",
    "field_frequency": "Pay frequency",
    "field_period_start": "Period start",
    "field_period_end": "Period end",
    "field_pay_date": "Pay date",
    "field_notes": "Notes (optional)",
    "create_submit": "Create run",
    "create_cancel": "Cancel",
    "create_ok_toast": "Run created successfully",
    "status_draft": "Draft",
    "status_validado": "Validated",
    "status_calculado": "Calculated",
    "status_aprobado": "Approved",
    "status_pagado": "Paid",
    "status_contabilizado": "Posted",
    "status_archivo_bancario": "Bank File",
    "step_draft_title": "Draft",
    "step_draft_desc": "The period is created but the required catalogs to calculate payroll haven't been validated yet.",
    "step_draft_action": "Validate catalogs",
    "step_validado_title": "Validated",
    "step_validado_desc": "Required catalogs (tax brackets, credits, CCSS, standard hours) are complete. Ready to calculate.",
    "step_validado_action": "Calculate payroll",
    "step_calculado_title": "Calculated",
    "step_calculado_desc": "The per-employee result was frozen (immutable snapshot). Resolve all detected anomalies before approving.",
    "step_calculado_action": "Approve run",
    "step_calculado_blocked": "{count} unresolved anomaly(ies)",
    "step_aprobado_title": "Approved",
    "step_aprobado_desc": "The run was approved. Confirm manually once the payment has left the bank.",
    "step_aprobado_action": "Mark as paid",
    "step_pagado_title": "Paid",
    "step_pagado_desc": "Generate the payroll journal entry to be able to post this period.",
    "step_pagado_action_generate": "Generate journal entry",
    "step_pagado_action_next": "Post",
    "step_contabilizado_title": "Posted",
    "step_contabilizado_desc": "Generate the bank file for the payroll deposit.",
    "step_contabilizado_action_generate": "Generate bank file",
    "step_contabilizado_action_next": "Close run",
    "step_archivo_bancario_title": "Bank File",
    "step_archivo_bancario_desc": "Run complete. The bank file is ready to upload to the bank.",
    "step_archivo_bancario_download": "Download TXT file",
    "snapshot_title": "Per-employee result (frozen)",
    "net_preview_title": "Calculation preview",
    "anomaly_queue_title": "Anomaly queue",
    "anomaly_none": "No anomalies detected",
    "anomaly_resolve": "Resolve",
    "anomaly_resolved_toast": "Anomaly marked as resolved",
    "rule_payroll_net_zero_or_negative": "Zero or negative net",
    "rule_payroll_paid_after_termination": "Paid after termination",
    "rule_payroll_net_deviation": "Net deviation",
    "rule_payroll_overtime_outlier": "Overtime outlier",
    "rule_payroll_branch_net_outlier": "Branch outlier",
    "rule_payroll_bank_account_changed_before_payment": "Bank account changed",
    "severity_high": "High",
    "severity_medium": "Medium",
    "col_employee": "Employee",
    "col_gross": "Gross",
    "col_ccss": "CCSS",
    "col_renta": "Income tax",
    "col_net": "Net",
    "no_data": "No data to show",
    "journal_entry_title": "Journal entry generated",
    "journal_entry_total": "Total",
    "bank_file_title": "Bank file generated",
    "bank_file_rows": "{count} employee(s) included",
    "bank_file_missing": "{count} employee(s) excluded",
    "transition_ok_toast": "Status updated successfully",
    "generating": "Generating...",
    "error_invalid_transition": "Cannot move directly to this status.",
    "error_missing_catalogs": "Missing required catalogs:",
    "error_blocked_rows": "{count} employee(s) have blocked data. Check Gross Payroll.",
    "error_unresolved_flags": "{count} unresolved anomaly(ies).",
    "error_accounting_entry_missing": "The journal entry hasn't been generated yet.",
    "error_bank_file_missing": "The bank file hasn't been generated yet.",
    "error_bank_config_missing": "The bank file description is not configured.",
    "error_no_valid_rows": "No valid employees for the bank file.",
    "error_no_rows": "No calculable payroll rows for this period.",
    "error_missing_accounts": "Missing configured accounting accounts.",
    "error_zero_amount": "The calculated total amount is zero.",
    "error_unbalanced": "The entry doesn't balance (debit != credit).",
    "error_generic": "Could not complete the action.",
}

for path, nav_new, section_new in [
    ("apps/frontend/messages/es.json", nav_es, payroll_run_es),
    ("apps/frontend/messages/en.json", nav_en, payroll_run_en),
]:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    added_nav = 0
    for k, v in nav_new.items():
        if k not in data.get("nav", {}):
            data["nav"][k] = v
            added_nav += 1
    data.setdefault("payroll_run", {})
    added_section = 0
    for k, v in section_new.items():
        if k not in data["payroll_run"]:
            data["payroll_run"][k] = v
            added_section += 1
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"OK: {path} - nav +{added_nav}, payroll_run +{added_section}")
PYEOF

# ---------- 3. verificaciones finales ----------
echo "=== verificando sidebar ==="
grep -n "payroll_runs" "apps/frontend/app/[locale]/dashboard/layout.js"

echo "=== verificando i18n ==="
python3 -c "
import json
for path in ['apps/frontend/messages/es.json', 'apps/frontend/messages/en.json']:
    with open(path, encoding='utf-8') as f:
        data = json.load(f)
    assert 'payroll_runs' in data.get('nav', {}), f'{path}: falta nav.payroll_runs'
    assert 'title' in data.get('payroll_run', {}), f'{path}: falta payroll_run.title'
    print(f'OK: {path} tiene las claves nuevas')
"

# ---------- 4. rebuild ----------
echo "=== rebuild frontend ==="
docker compose build --no-cache frontend
docker compose up -d frontend
sleep 5
docker compose logs frontend --tail 30

echo "=== FIN Parte 3c ==="
