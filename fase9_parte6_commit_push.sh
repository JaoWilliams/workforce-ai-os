#!/bin/bash
# ============================================================
# Fase 9 (Asientos contables) - Parte 6: commit + push
# ============================================================
# Deja fuera los .sh de entrega y los test_*.py (mismo criterio que
# fases anteriores - no forman parte del repo de la app).
# Ejecutar: cd /opt/workforce-ai-os && bash fase9_parte6_commit_push.sh
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

git add \
  apps/backend/app/db/models.py \
  apps/backend/app/i18n/en/messages.json \
  apps/backend/app/i18n/es/messages.json \
  apps/backend/app/main.py \
  apps/backend/app/modules/catalogs/router.py \
  apps/backend/app/modules/catalogs/schemas.py \
  apps/backend/alembic/versions/df26253754a1_asientos_contables.py \
  apps/backend/alembic/versions/4bf4405bd559_widen_chart_of_account_code.py \
  apps/backend/app/core/accounting.py \
  apps/backend/app/modules/accounting/

echo "=== git status tras el add ==="
git status

git commit -m "Nomina fase 9: Asientos contables (planilla + provisiones + CCSS patronal)

Alcance confirmado con el cliente: planilla ordinaria + provision de
aguinaldo (con reconciliacion al pago real que cancela el pasivo
acumulado) + provision de vacaciones (delta de dias acumulados x
tarifa Art.157) + cesantia SOLO al aprobar una Termination con
responsabilidad patronal (sin provision mensual especulativa - eso
requeriria asumir una tasa de rotacion que no existe como dato real) +
aporte patronal CCSS (tasa de prueba flageada). Exportacion: CSV
generico (no se confirmo sistema contable especifico, el cliente pidio
un CSV).

Modelos nuevos:
- ChartOfAccount (chart_of_accounts, tenant_id+code unico, code
  ampliado a String(50) tras un primer intento con String(20) que no
  alcanzaba para codigos contables descriptivos reales): plan de
  cuentas, no existia previamente.
- JournalEntry + JournalEntryLine: cabecera + lineas debe/haber de
  cada asiento. entry_type distingue planilla/aguinaldo_provision/
  aguinaldo_pago/vacaciones_provision/cesantia/ccss_patronal.
- PayrollConcept.accounting_account_id (FK opcional a ChartOfAccount):
  cada concepto individual se puede mapear a su cuenta de pasivo.

core/accounting.py: 6 funciones generate_*_entry() que devuelven un
dict {error, lines, ...} sin persistir nada (permite validar antes de
guardar), mas persist_journal_entry() que valida debe==haber antes de
comitear. Resolucion de cuentas:
  - Gasto de planilla ordinaria: Branch.accounting_account (campo que
    ya existia desde mod.6, pensado exactamente para esto).
  - Pasivo de CCSS-EMPLEADO/AGUINALDO/CCSS-PATRONAL: PayrollConcept.
    accounting_account_id (nuevo).
  - RENTA: NO existe como PayrollConcept (el calculo de fase 5 usa
    TaxBracket/RentaCredits directamente) - su pasivo se resuelve por
    codigo fijo ChartOfAccount (PASIVO-RENTA-POR-PAGAR), no por
    concepto. Esto se descubrio durante el testing (el primer intento
    asumia un concepto RENTA que no existe).
  - Gasto de provisiones/patronales sin hogar natural: codigos fijos
    de ChartOfAccount (mismo tipo de clave fija que 'AGUINALDO' o
    'HORAS_EXTRA' ya usan como PayrollConcept.code - no es un valor
    financiero).

BUG encontrado y corregido durante el testing: AGUINALDO y CCSS-
PATRONAL guardan su tasa patronal en PayrollConcept.value (origin=
patronal, concepto puro sin lado empleado), NO en employer_value (ese
campo es para conceptos con AMBOS lados en la MISMA fila, patron
distinto no usado en esta fase). El codigo inicial leia employer_value
por error; corregido para leer value, verificado con datos reales de
AGUINALDO (8.33% confirmado en value, employer_value NULL).

CCSS patronal: PayrollConcept nuevo (code=CCSS-PATRONAL, origin=
patronal, tasa 26.67% en .value) - VALOR DE PRUEBA FLAGEADO, pendiente
de validacion de tu contador (mismo tratamiento que CCSS-EMPLEADO al
10.67%, HORAS_EXTRA, FERIADO_OBLIGATORIO_TRABAJADO).

Endpoints nuevos:
- PUT/GET/PATCH /api/catalogs/chart-of-accounts (catalogs.manage/.view)
- Nuevo modulo /api/accounting/journal-entries/{payroll|aguinaldo-
  provision|aguinaldo-payment|vacaciones-provision|ccss-patronal} (POST,
  payroll.manage) + /cesantia/{termination_id} (POST, payroll.manage)
- GET /api/accounting/journal-entries (listado, payroll.view)
- GET /api/accounting/journal-entries/export-csv (payroll.view)

RBAC: reutiliza permisos existentes (catalogs.*, payroll.*), sin roles
nuevos - mismo criterio que fases anteriores.

Migraciones: df26253754a1 (3 tablas nuevas con RLS + columna en
payroll_concepts) y 4bf4405bd559 (ampliar chart_of_accounts.code a 50
caracteres).

Test end-to-end (31/31 PASS, no comiteado): siembra de plan de cuentas
real (13 cuentas), vinculacion de conceptos existentes, creacion de
CCSS-PATRONAL, y cada uno de los 6 generadores probado con las
funciones de computo downstream (compute_net_payroll_rows,
compute_payroll_rows, compute_vacation_balance/daily_rate,
compute_aguinaldo_rows, compute_cesantia_amount) monkeypatcheadas a
valores fijos conocidos - esos calculos ya se probaron en sus fases
respectivas, aqui se probo solo la logica nueva de generacion y
persistencia de asientos, incluyendo la reconciliacion de aguinaldo
(cancela pasivo + ajusta diferencia), el bloqueo por cuentas faltantes,
la deteccion de asientos desbalanceados, y el CRUD de ChartOfAccount.
Datos transaccionales de prueba limpiados; el plan de cuentas, los
vinculos concepto->cuenta y CCSS-PATRONAL quedan como catalogo real en
produccion."

echo "=== push ==="
git push

echo "=== FIN Parte 6 ==="
