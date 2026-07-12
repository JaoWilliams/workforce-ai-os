#!/bin/bash
# ============================================================
# Fase 10 - Parte 7b: DISCOVERY del doc maestro (solo lectura)
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

echo "=== seccion 0: primeras 15 lineas ==="
sed -n '/## 0. Registro de cambios/,+15p' docs/WORKFORCE_AI_OS_PROYECTO.md

echo
echo "=== roadmap nomina: items 9-12 ==="
grep -n "^9\.\|^10\.\|^11\.\|^12\." docs/WORKFORCE_AI_OS_PROYECTO.md

echo
echo "=== seccion 5.2: contexto CCSS patronal / plan de cuentas (fase 9) ==="
grep -n "CCSS patronal y plan de cuentas" docs/WORKFORCE_AI_OS_PROYECTO.md -A 3 -B 1

echo
echo "=== seccion 5.3: bullet Mod 15 actual ==="
grep -n "Mód. 15" docs/WORKFORCE_AI_OS_PROYECTO.md

echo
echo "=== FIN discovery 7b ==="
