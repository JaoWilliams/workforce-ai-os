#!/bin/bash
# ============================================================
# Fase 11 - Parte 9b: DISCOVERY 2 - ubicar seccion 5.2 exacta
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"
DOC="./docs/WORKFORCE_AI_OS_PROYECTO.md"

echo "=== indice de encabezados (## y ###) ==="
grep -n "^##" "$DOC"

echo ""
echo "=== bloque alrededor de cualquier '5.2' literal ==="
grep -n "5\.2" "$DOC"
