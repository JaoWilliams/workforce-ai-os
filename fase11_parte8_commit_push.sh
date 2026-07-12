#!/bin/bash
# ============================================================
# Fase 11 (Orquestacion) - Parte 8: commit + push
# ============================================================
# Deja fuera el test_*.py y los .sh de entrega (mismo criterio de
# siempre - no forman parte del repo de la app).
# Ejecutar: cd /opt/workforce-ai-os && bash fase11_parte8_commit_push.sh
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

git add \
  apps/backend/app/db/models.py \
  apps/backend/app/core/payroll_run.py \
  apps/backend/app/core/accounting.py \
  apps/backend/app/core/bank_file.py \
  apps/backend/app/modules/catalogs/router.py \
  apps/backend/app/modules/catalogs/schemas.py \
  apps/backend/app/modules/payroll/router.py \
  apps/backend/app/modules/payroll/schemas.py \
  apps/backend/app/modules/confianza_operativa/router.py \
  apps/backend/app/modules/confianza_operativa/schemas.py \
  apps/backend/alembic/versions/b01b17e5fbc8_orquestacion_payroll_run.py

echo "=== git status tras el add ==="
git status

git commit -m "Nomina fase 11: Orquestacion y auto-validacion (Payroll Run)

Las 4 piezas completas, confirmadas con el cliente: maquina de
estados, snapshot inmutable, validacion proactiva, y cola de
anomalias reutilizando el Motor de Confianza Operativa (mod 17a).

Maquina de estados (core/payroll_run.py): PayrollPeriod.status pasa
de 3 valores (draft/closed/paid) a 7, estrictamente secuencial, sin
saltos:
  draft -> validado -> calculado -> aprobado -> pagado ->
  contabilizado -> archivo_bancario
Cada transicion valida antes de avanzar (patron blocking-cascade de
siempre):
  - validado: catalogos requeridos existen (TaxBracket/RentaCredits
    del ano, CCSS-EMPLEADO activo, PayrollHoursConfig de la
    frecuencia).
  - calculado: ninguna fila puede tener gross_pay/net_pay en None ->
    se congela el snapshot y corren 5 de las 6 reglas de anomalia.
  - aprobado: todos los TrustFlag del periodo deben estar resueltos
    (revision humana obligatoria antes de aprobar el pago).
  - pagado: confirmacion manual, sin validacion extra (no hay forma
    de verificar desde el sistema que el dinero salio del banco).
  - contabilizado: debe existir un JournalEntry tipo planilla (fase 9).
  - archivo_bancario: debe existir un BankTransferFile (fase 10); ahi
    corre la 6ta regla (cuenta bancaria cambiada antes del pago).

Snapshot inmutable (PayrollSnapshotLine, nueva tabla): al pasar a
'calculado' se congela compute_net_payroll_rows por empleado (bruto,
CCSS, renta, neto, mas el detalle completo en JSONB para
trazabilidad). get_net_payroll_rows_for_period() es el punto unico de
lectura: prefiere el snapshot si existe, cae a calculo en vivo si no.
RETROFIT minimo de core/accounting.py y core/bank_file.py (fase 9/10)
para leer de ahi en vez de recalcular siempre en vivo - asi un cambio
posterior en TaxBracket/CCSS ya no altera un periodo ya
calculado/pagado. Probado explicitamente: se cambia el monkeypatch de
compute_net_payroll_rows DESPUES de congelar y se verifica que el
asiento contable y el archivo bancario siguen usando los montos
originales.

Motor de anomalias (6 reglas, TrustFlag extendido con
payroll_period_id/branch_id nullable + employee_id ahora nullable
para senales a nivel sucursal):
  - payroll_net_deviation: neto muy distinto al periodo anterior del
    mismo empleado.
  - payroll_net_zero_or_negative: neto cero o negativo inesperado.
  - payroll_overtime_outlier: horas extra muy por encima del
    promedio historico del empleado.
  - payroll_paid_after_termination: empleado con Termination
    aprobada que igual aparece con pago en la corrida (cruce con
    fase 8).
  - payroll_branch_net_outlier: sucursal con neto total muy fuera
    del promedio de las demas.
  - payroll_bank_account_changed_before_payment: cuenta bancaria
    cambiada pocos dias antes de generarse el archivo bancario (via
    AuditLog, cruce con fase 10) - control anti-fraude clasico.
Umbrales en PayrollAnomalyConfig (catalogo nuevo, 1 fila por tenant,
valores de PRUEBA flageados - son sensibilidad heuristica, no
valores legales, pero igual van a catalogo y no al codigo).

Endpoints nuevos/extendidos:
- PUT/GET /api/catalogs/payroll-anomaly-config (catalogs.manage/.view)
- PATCH /api/payroll/periods/{id}/status ahora pasa por la maquina de
  estados en vez de solo asignar el valor (mismo endpoint, logica
  nueva por dentro)
- GET /api/payroll/periods/{id}/snapshot (payroll.view)
- GET /api/confianza-operativa/flags extendido con filtro
  payroll_period_id (reusa el endpoint existente, no crea una cola
  de excepciones nueva - la cola ES la lista de TrustFlag sin
  resolver de un periodo)

RBAC: reutiliza permisos existentes (catalogs.*, payroll.*,
confianza.*), sin roles nuevos.

Migracion: b01b17e5fbc8 (2 tablas nuevas con RLS, mas 3 columnas
nuevas en trust_flags - employee_id se vuelve nullable).

Test end-to-end (37/37 PASS, no comiteado): las 7 transiciones
recorridas de punta a punta, los 3 bloqueos negativos (transicion
invalida saltando un paso, filas bloqueadas al calcular, catalogos
faltantes con un periodo de prueba en el ano 2099), las 5 reglas de
'calculado' disparadas con datos conocidos, la 6ta regla probada
generando un cambio real de cuenta bancaria y verificando que se
detecto, e inmutabilidad demostrada cambiando el monkeypatch despues
de congelar y confirmando que accounting.py y bank_file.py siguieron
usando los montos originales. Datos transaccionales de prueba
limpiados; PayrollAnomalyConfig, la cuenta contable nueva de BK
Heredia y BankFileConfig quedan como catalogo real de produccion."

echo "=== push ==="
git push

echo "=== FIN Parte 8 (commit + push) ==="
