#!/bin/bash
# ============================================================
# Fase 10 - Parte 1d: DISCOVERY micro (estilo de columnas Numeric/Integer)
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

echo "=== 1. Como se tipean columnas Numeric en models.py (ejemplos) ==="
grep -n "Numeric(" apps/backend/app/db/models.py | head -10

echo
echo "=== 2. Como se tipean columnas Integer en models.py (ejemplos) ==="
grep -n "Integer" apps/backend/app/db/models.py | head -10

echo
echo "=== 3. Imports (primeras 25 lineas) de models.py ==="
sed -n '1,25p' apps/backend/app/db/models.py

echo
echo "=== FIN discovery 1d ==="
