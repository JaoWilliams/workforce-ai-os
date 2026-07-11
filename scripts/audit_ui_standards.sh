#!/bin/bash
# ============================================================
# Auditoria del estandar de pantallas con listado (ver CLAUDE.md).
# Uso: bash scripts/audit_ui_standards.sh
# Correr desde la raiz del repo, o exportar REPO_DIR.
# ============================================================
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

DIR="apps/frontend/app/[locale]/dashboard"

echo "pantalla              | busqueda | sucursal | toast | branches-fetch"
echo "-----------------------------------------------------------------"
for path in "$DIR"/*/page.js "$DIR"/nomina/corridas/page.js; do
  [ -f "$path" ] || continue
  name=$(echo "$path" | sed -E 's#.*dashboard/##; s#/page.js##')
  search=$(grep -c 'searchQuery\|roleSearch\|userSearch' "$path" 2>/dev/null || echo 0)
  branch_filter=$(grep -c 'branchFilter' "$path" 2>/dev/null || echo 0)
  toast=$(grep -c 'showToast(' "$path" 2>/dev/null || echo 0)
  branches_fetch=$(grep -c '/api/branches' "$path" 2>/dev/null || echo 0)
  printf "%-22s | %-8s | %-8s | %-5s | %-5s\n" "$name" \
    "$([ "$search" -gt 0 ] && echo SI || echo NO)" \
    "$([ "$branch_filter" -gt 0 ] && echo SI || echo NO)" \
    "$([ "$toast" -gt 0 ] && echo SI || echo NO)" \
    "$([ "$branches_fetch" -gt 0 ] && echo SI || echo NO)"
done
echo ""
echo "Nota: 'sucursal'/'branches-fetch' en NO puede ser correcto si la"
echo "pantalla no lista datos asociables a empleado/sucursal (ej. Sucursales"
echo "mismo, Usuarios y Roles, Feature Flags sin ese vinculo). Usar criterio."
