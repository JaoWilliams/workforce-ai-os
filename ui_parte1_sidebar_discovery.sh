#!/bin/bash
# ============================================================
# UI/UX Nomina - Parte 1: DISCOVERY del sidebar/nav actual
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

echo "=== estructura general del frontend (2 niveles) ==="
find . -maxdepth 4 -iname "*frontend*" -type d 2>/dev/null

echo ""
echo "=== buscando componente de sidebar/nav ==="
SIDEBAR_FILES=$(grep -rli "sidebar\|nav-items\|navigation" --include="*.tsx" --include="*.ts" apps/*/src apps/*/app 2>/dev/null | grep -vi node_modules | grep -vi "\.next" || true)
echo "$SIDEBAR_FILES"

echo ""
echo "=== contenido de cada archivo encontrado ==="
for f in $SIDEBAR_FILES; do
  echo "--- $f ---"
  cat "$f"
  echo ""
done

echo ""
echo "=== todas las rutas/paginas existentes (app router) ==="
find . -path "*/app/*/page.tsx" -not -path "*/node_modules/*" -not -path "*/.next/*" 2>/dev/null | sort

echo ""
echo "=== FIN discovery sidebar ==="
