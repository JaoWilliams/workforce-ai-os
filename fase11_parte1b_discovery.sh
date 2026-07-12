#!/bin/bash
# ============================================================
# Fase 11 - Parte 1b: DISCOVERY (motor de reglas + endpoint de status)
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

echo "############################################################"
echo "# 1. core/confianza_operativa.py COMPLETO"
echo "############################################################"
cat apps/backend/app/core/confianza_operativa.py 2>/dev/null || find / -maxdepth 6 -iname "confianza_operativa.py" 2>/dev/null

echo
echo "############################################################"
echo "# 2. modules/confianza_operativa/router.py COMPLETO"
echo "############################################################"
cat apps/backend/app/modules/confianza_operativa/router.py

echo
echo "############################################################"
echo "# 3. modules/confianza_operativa/schemas.py COMPLETO"
echo "############################################################"
cat apps/backend/app/modules/confianza_operativa/schemas.py

echo
echo "############################################################"
echo "# 4. payroll/router.py lineas 140-215 (endpoint de status)"
echo "############################################################"
sed -n '140,215p' apps/backend/app/modules/payroll/router.py

echo
echo "############################################################"
echo "# 5. payroll/schemas.py - buscar el schema de status update"
echo "############################################################"
grep -n "class.*Status\|status:" apps/backend/app/modules/payroll/schemas.py

echo
echo "=== FIN discovery 1b ==="
