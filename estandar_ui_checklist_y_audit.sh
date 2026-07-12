#!/bin/bash
# ============================================================
# Estandar UI: checklist en CLAUDE.md + script de auditoria reutilizable
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

# ---------- 1. checklist en CLAUDE.md ----------
python3 << 'PYEOF'
path = "CLAUDE.md"
with open(path, encoding="utf-8") as f:
    src = f.read()

marker = "## Estandar de pantallas con listado (obligatorio)"
if marker in src:
    print("OK: el checklist ya existe en CLAUDE.md, no se duplica")
else:
    addition = """

## Estandar de pantallas con listado (obligatorio)

Toda pantalla nueva que liste datos por empleado y/o sucursal (empleados,
marcacion, excepciones, confianza operativa, dispositivos, reportes, etc.)
debe cumplir, sin excepcion, dado que el sistema opera a escala de ~1400
empleados en 54+ sucursales:

1. Busqueda de texto libre (nombre, codigo, lo que aplique).
2. Filtro por sucursal (dropdown poblado desde /api/branches) cuando los
   registros se puedan asociar a una sucursal via employee.branch_id.
3. Toast de exito/error en toda accion de creacion/edicion/eliminacion,
   usando el hook useToast (lib/toast.js) - nunca solo un estado local.
4. Autorefresh: recargar la lista (load()/loadX()) despues de cualquier
   mutacion exitosa - nunca dejar que el usuario tenga que refrescar
   manualmente.
5. Estados de carga y vacio (LoadingState / EmptyState de lib/ui.js).
6. Acciones de escritura ocultas/deshabilitadas segun permisos reales
   (hasPermission de lib/permissions.js), nunca visibles a todos.

Antes de dar por cerrada una pantalla nueva, correr:
  bash scripts/audit_ui_standards.sh
y revisar que no falte ninguno de los 6 puntos.
"""
    with open(path, "a", encoding="utf-8") as f:
        f.write(addition)
    print("OK: checklist agregado a CLAUDE.md")
PYEOF

# ---------- 2. script de auditoria reutilizable ----------
mkdir -p scripts
cat > scripts/audit_ui_standards.sh << 'AUDITEOF'
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
AUDITEOF
chmod +x scripts/audit_ui_standards.sh
echo "OK: scripts/audit_ui_standards.sh creado"

# ---------- 3. commit ----------
git add CLAUDE.md scripts/audit_ui_standards.sh
git commit -m "docs: estandar de pantallas con listado + script de auditoria

- CLAUDE.md: checklist obligatorio (busqueda, filtro sucursal, toast,
  autorefresh, loading/empty states, permisos) para toda pantalla nueva
  que liste datos por empleado/sucursal.
- scripts/audit_ui_standards.sh: audita todas las pantallas del dashboard
  contra el estandar, para correr antes de cerrar cualquier pantalla nueva
  o como chequeo periodico."
git push origin main
echo "OK: commit + push"

echo "=== FIN estandar UI checklist + audit ==="
