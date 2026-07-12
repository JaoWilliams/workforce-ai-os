#!/bin/bash
# ============================================================
# Fase 10 - Parte 1g: DISCOVERY micro (resto del boilerplate de test)
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

echo "=== lineas 70-160 de test_accounting_e2e.py ==="
sed -n '70,160p' test_accounting_e2e.py

echo
echo "=== helper de PASS/FAIL (buscar 'def check' o 'PASS' o 'ok(') ==="
grep -n "^def \|^PASS\|^FAIL\|passed = 0\|checks = \[\]\|def ok\|def check" test_accounting_e2e.py | head -20

echo
echo "=== ultimas 40 lineas (cleanup + resumen final) ==="
tail -40 test_accounting_e2e.py

echo
echo "=== FIN discovery 1g ==="
