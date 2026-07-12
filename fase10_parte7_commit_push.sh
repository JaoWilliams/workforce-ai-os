#!/bin/bash
# ============================================================
# Fase 10 (Archivo bancario) - Parte 7: commit + push
# ============================================================
# Deja fuera el test_*.py y los .sh de entrega (mismo criterio de
# siempre - no forman parte del repo de la app).
# Ejecutar: cd /opt/workforce-ai-os && bash fase10_parte7_commit_push.sh
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
  apps/backend/app/modules/employees/router.py \
  apps/backend/app/modules/employees/schemas.py \
  apps/backend/alembic/versions/a372cffde918_archivo_bancario.py \
  apps/backend/app/core/bank_file.py \
  apps/backend/app/modules/bank_file/

echo "=== git status tras el add ==="
git status

git commit -m "Nomina fase 10: Archivo de transferencia bancaria

Formato de salida confirmado por el cliente con un ejemplo REAL de su
banco (no inventado, per el principio de 'no se inventa formato' ya
aplicado en asientos contables): texto plano delimitado por TAB, sin
encabezado, 4 columnas: tipo_cuenta / numero_cuenta / monto (2
decimales) / glosa.

Modelos nuevos:
- Employee.bank_account_type / bank_account_number (nullable, se
  completan despues del alta via PATCH existente, no es obligatorio
  al crear el empleado).
- BankFileConfig (bank_file_configs, 1 fila por tenant, unique en
  tenant_id): guarda la glosa real de transferencia. Valor REAL
  confirmado por el cliente: 'PLANILLA EMPRESARIAL BURGER KING COSTA
  RICA' (el ejemplo que dio tenia un typo de ortografia -sin la R de
  BURGER-, confirmado y corregido antes de construir).
- BankTransferFile + BankTransferFileLine: cabecera + lineas de cada
  generacion real del archivo, para auditoria (que se genero, cuando,
  por cuanto, cuantos empleados quedaron fuera por falta de cuenta
  bancaria cargada). La glosa se congela en la linea al momento de
  generar, no se recalcula si la config cambia despues.

core/bank_file.py: generate_bank_transfer_rows() consume
compute_net_payroll_rows() (fase 5, ya probado - no se reinventa el
calculo de neto). Patron blocking-cascade: si falta la config de
glosa, no se genera nada. Si a un empleado individual le falta cuenta
bancaria, o su neto es None/cero/negativo, o no se encuentra el
registro de empleado, ESE empleado se excluye del archivo y queda
listado en 'missing' con el motivo exacto -- no bloquea a los demas
(mismo patron que vacaciones excluye empleados con balance no
resoluble). persist_bank_transfer_file() no persiste nada si no queda
ninguna fila valida (no_valid_rows).

Endpoints nuevos:
- PUT/GET /api/catalogs/bank-file-config (catalogs.manage/.view)
- POST /api/bank-file/generate/{payroll_period_id} (payroll.manage)
- GET /api/bank-file (listado, payroll.view)
- GET /api/bank-file/{id} (detalle con lineas, payroll.view)
- GET /api/bank-file/{id}/export-txt (descarga el TXT historico
  exacto reconstruido desde las lineas persistidas, no recalculado)
- PATCH /api/employees/{id} extendido con bank_account_type/
  bank_account_number (reusa el endpoint existente, no crea uno nuevo)

RBAC: reutiliza permisos existentes (catalogs.*, payroll.*), sin
roles nuevos.

Migracion: a372cffde918 (3 tablas nuevas con RLS + 2 columnas nuevas
en employees).

Test end-to-end (27/27 PASS, no comiteado): 4 empleados de prueba
cubriendo cada rama del patron blocking-cascade (neto no computable,
empleado no encontrado, neto cero/negativo, cuenta bancaria faltante,
caso valido), compute_net_payroll_rows monkeypatcheado a valores fijos
conocidos (ya probado en fase 5, aqui se prueba solo la logica nueva),
persistencia verificada contra la base real, formato TXT verificado
caracter por caracter contra el ejemplo real que diste, los 4
endpoints probados via llamada directa a las funciones del router
(bypass JWT), y el caso no_valid_rows. Datos transaccionales de
prueba limpiados; BankFileConfig con la glosa real, y los 2
bank_account_type/number cargados durante el test en empleados reales
si aplicara, quedan como estaban (el test crea sus propios empleados
marcados y los borra)."

echo "=== push ==="
git push

echo "=== FIN Parte 7 (commit + push) ==="
