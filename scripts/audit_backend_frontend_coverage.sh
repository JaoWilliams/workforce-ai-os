#!/bin/bash
# ============================================================
# Detecta endpoints del backend que NINGUNA pantalla del frontend
# usa (el tipo de hueco real que paso con /api/catalogs/concepts:
# el backend existia desde Mod. 6 pero nunca se construyo la UI).
#
# Como funciona: extrae todas las rutas reales de FastAPI (no
# adivinadas - se leen directo del app.routes en runtime, mismo
# metodo usado en la verificacion final del #104), separa la parte
# estatica de cada ruta (quita los {parametros}), y busca esa parte
# estatica en todo el codigo fuente del frontend. Si no aparece en
# ningun archivo, se marca como "SIN UI".
#
# Uso: bash scripts/audit_backend_frontend_coverage.sh
# ============================================================
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

echo "Extrayendo rutas reales del backend..."
docker compose exec -T api python3 -c "
from app.main import app
seen = set()
for r in app.routes:
    methods = getattr(r, 'methods', None)
    if not methods:
        continue
    path = r.path
    if path in seen:
        continue
    seen.add(path)
    print(path)
" | sort -u > /tmp/_backend_routes.txt

echo ""
echo "ruta backend                                            | usada en frontend?"
echo "--------------------------------------------------------------------------"

FRONTEND_DIR="apps/frontend/app"
sin_ui=0
total=0

while IFS= read -r route; do
  [ -z "$route" ] && continue
  case "$route" in
    /docs*|/redoc*|/openapi.json) continue ;;
  esac
  total=$((total + 1))
  # parte estatica: primeros 2 segmentos reales despues de /api/ (suficiente
  # para distinguir modulos - ej /api/catalogs/concepts vs /api/catalogs/vacation-config)
  static_part=$(echo "$route" | sed -E 's#\{[^}]+\}##g' | sed -E 's#/+#/#g' | sed -E 's#/$##')
  # probamos con el path completo sin parametros; si no aparece, probamos
  # solo con el ultimo segmento no vacio (mas permisivo, evita falsos positivos
  # de rutas que difieren solo en el prefijo pero comparten el recurso final)
  found=$(grep -rl "$static_part" "$FRONTEND_DIR" 2>/dev/null | head -1)
  if [ -z "$found" ]; then
    last_segment=$(echo "$static_part" | awk -F/ '{print $NF}')
    if [ -n "$last_segment" ]; then
      found=$(grep -rl "$last_segment" "$FRONTEND_DIR" 2>/dev/null | head -1)
    fi
  fi
  if [ -n "$found" ]; then
    printf "%-56s | SI\n" "$route"
  else
    printf "%-56s | SIN UI\n" "$route"
    sin_ui=$((sin_ui + 1))
  fi
done < /tmp/_backend_routes.txt

echo ""
echo "Total rutas: $total | Sin UI detectada: $sin_ui"
echo ""
echo "Nota: esto es un heuristico (busca texto, no analiza imports reales)."
echo "Un 'SIN UI' puede ser normal para sub-rutas de detalle (ej. export-pdf"
echo "de una pantalla que ya llama al endpoint base) - revisar con criterio,"
echo "no asumir automaticamente que hay que construir algo."
