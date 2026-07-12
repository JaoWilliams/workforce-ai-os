#!/bin/bash
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"
DOC="./docs/WORKFORCE_AI_OS_PROYECTO.md"

echo "=== seccion 5.2 completa, lineas 142-165 ==="
sed -n '142,165p' "$DOC"

echo ""
echo "=== primeras lineas de seccion 0 (contexto exacto donde insertar la entrada de fase 11), lineas 9-13 ==="
sed -n '9,13p' "$DOC"
