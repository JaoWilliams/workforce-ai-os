#!/bin/bash
# ============================================================
# Fase 8 (Cesantía) - Parte 6: commit + push
# ============================================================
# Solo agrega el codigo de aplicacion real. Los scripts .sh de entrega
# y test_cesantia_e2e.py quedan FUERA del commit (no son parte del
# repo, fueron solo el mecanismo para pegar/ejecutar en el servidor -
# mismo criterio que fases anteriores, donde no se comiteo el arnes
# de pruebas).
# Ejecutar: cd /opt/workforce-ai-os && bash fase8_parte6_commit_push.sh
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

git add \
  apps/backend/app/db/models.py \
  apps/backend/app/i18n/en/messages.json \
  apps/backend/app/i18n/es/messages.json \
  apps/backend/app/modules/catalogs/router.py \
  apps/backend/app/modules/catalogs/schemas.py \
  apps/backend/app/modules/payroll/router.py \
  apps/backend/app/modules/payroll/schemas.py \
  apps/backend/alembic/versions/b36b15cd58ab_cesantia.py \
  apps/backend/app/core/cesantia.py

echo "=== git status tras el add (verificar que no se cuelen los .sh / test) ==="
git status

git commit -m "Nomina fase 8: Cesantia (Codigo de Trabajo Art. 28/29/30)

Fuente legal: \"Cesantia Art 29.docx\" cargado por el cliente (2026-07-10),
tratado como fuente autoritativa (mismo patron que vacaciones/aguinaldo).

Modelos nuevos:
- CesantiaConfig (tenant_id unico): max_years_cap, fraction_round_months,
  days_3to6_months, days_6to12_months, daily_divisor, months_for_average.
  Sembrado con valores REALES: 8 anios tope, 6 meses umbral de fraccion,
  7/14 dias para los casos <1 anio, divisor 30, promedio de 6 meses.
- CesantiaScaleRow (tenant_id+year_number unico): tabla oficial Art. 29
  completa (13 filas), sembrada con los valores REALES del documento:
  19.5, 20, 20.5, 21, 21.24, 21.5, 22, 22, 22, 21.5, 21, 20.5, 20.
  (filas 9-13 nunca se alcanzan por el tope de 8 anios, pero se guardan
  completas por fidelidad al documento legal por si el tope cambia).
- Termination (tenant_id+employee_id unico): modelo de terminacion con
  causa + flujo de aprobacion (pending/approved/rejected), igual patron
  que VacationRequest/OvertimeApproval. Al aprobar, efecto lateral
  Employee.active=False.

core/cesantia.py:
- compute_years_months: antiguedad exacta en anios+meses.
- compute_cesantia_days: los 4 casos del Art. 29 (<3m=0, 3-6m=fijo,
  6-12m=fijo, >=1anio=suma acumulativa de la tabla con tope).
- compute_cesantia_daily_rate: promedio de gross_pay de los ultimos N
  meses (mensual directo, quincenal agrupado por mes calendario) / 30.
  Semanal -> frequency_unsupported (mismo alcance que renta/vacaciones,
  el documento distingue un divisor de 26 para no-comercial que no esta
  definido para este tenant).
- compute_cesantia_amount: combina todo con banderas de datos faltantes
  (config_missing/scale_missing/no_history/frequency_unsupported/
  partial_history) en vez de asumir - mismo patron 'blocking cascade'
  de fases 5-7. con_responsabilidad_patronal=False -> 0 directo.

INTERPRETACION FLAGEADA (pendiente validacion con abogado del cliente):
el documento se contradice a si mismo sobre el redondeo de fraccion de
anio - el resumen ejecutivo dice 'fracciones IGUALES O MAYORES a 6 meses
redondean' pero la seccion detallada con la tabla dice 'SUPERIOR a 6
meses'. Se adopto la version detallada (estrictamente >6, umbral
parametrizado en fraction_round_months, no hardcodeado) por ser la
fuente mas especifica. Documentado en el docstring de core/cesantia.py
y se documenta tambien en el master doc.

Endpoints nuevos:
- PUT/GET /api/catalogs/cesantia-config (catalogs.manage/.view)
- PUT/GET /api/catalogs/cesantia-scale (reemplazo total de la tabla)
- POST /api/payroll/terminations (payroll.manage) - valida empleado
  activo y que no exista terminacion previa (unique constraint)
- GET /api/payroll/terminations (payroll.view) - cesantia calculada inline
- PATCH /api/payroll/terminations/{id}/status (payroll.manage) - approve/
  reject, efecto lateral Employee.active=False al aprobar

RBAC: reutiliza permisos existentes (catalogs.*, payroll.*), sin roles
nuevos - mismo criterio que fases anteriores.

Migracion b36b15cd58ab: 3 tablas nuevas (cesantia_configs,
cesantia_scale_rows, terminations) con RLS (ENABLE+FORCE+policy
tenant_isolation) inyectado tras el autogenerate.

Test end-to-end (62/62 PASS, no comiteado): siembra de catalogo real, 7
casos de compute_cesantia_days con valores calculados a mano (incluye el
caso limite de la interpretacion >6 meses), promedio salarial con
compute_payroll_rows monkeypatcheado a valores conocidos (el calculo de
nomina bruta ya se probo en fase 1 - aqui solo se prueba la logica nueva:
promedio, agrupacion quincenal, historial parcial/nulo, bloqueo semanal),
integracion real via create_termination/update_termination_status (mismo
codigo que produccion), validaciones de negocio (terminacion duplicada,
empleado inactivo, estados invalidos), y el efecto lateral
Employee.active=False al aprobar (incluso sin responsabilidad patronal -
el empleado se fue igual, la cesantia es una cuestion legal aparte).
Datos de prueba limpiados; catalogo real (config + tabla de 13 filas)
queda activo en produccion.

Pendiente para fase 9 (asientos contables): reconciliar el concepto
AGUINALDO (8.33% patronal, provision mensual) con el pago real de
diciembre calculado en fase 7 - nota del cliente ya registrada."

echo "=== push ==="
git push

echo "=== FIN Parte 6 ==="
