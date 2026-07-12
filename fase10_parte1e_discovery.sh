#!/bin/bash
# ============================================================
# Fase 10 - Parte 1e: DISCOVERY micro (catalogs/schemas.py)
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

echo "=== 1. Imports (primeras 15 lineas) de catalogs/schemas.py ==="
sed -n '1,15p' apps/backend/app/modules/catalogs/schemas.py

echo
echo "=== 2. Ultimas 15 lineas de catalogs/schemas.py ==="
tail -15 apps/backend/app/modules/catalogs/schemas.py

echo
echo "=== 3. i18n: bloque alrededor de payroll.period_not_found (para agregar clave nueva) ==="
grep -n '"payroll.period_not_found"' apps/backend/app/i18n/es/messages.json apps/backend/app/i18n/en/messages.json

echo
echo "=== FIN discovery 1e ==="
