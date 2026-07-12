#!/bin/bash
# ============================================================
# Fase 11 - Parte 9: DISCOVERY para actualizar el documento maestro
# ============================================================
# Localiza el doc maestro (mismo patron de fase9/fase10) y muestra:
#  - las primeras lineas (encabezado/fecha)
#  - la linea del roadmap de "Orquestacion y auto-validacion"
#  - la seccion 5.2 (pendientes de validacion) completa
#  - la linea de seccion 5.3 del Mod.15 (Nomina)
# Ejecutar: cd /opt/workforce-ai-os && bash fase11_parte9_masterdoc_discovery.sh
# Pegame TODO el output.
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

DOC=$(find . -iname "*.md" -maxdepth 2 | xargs grep -l "Orquestacion y auto-validacion\|Orquestación y auto-validación" 2>/dev/null | head -1)
if [ -z "$DOC" ]; then
  echo "NO SE ENCONTRO el doc maestro buscando 'Orquestacion y auto-validacion'. Buscando por nombre comun..."
  DOC=$(find . -iname "*maestro*.md" -o -iname "*MASTER*.md" -o -iname "*roadmap*.md" 2>/dev/null | head -1)
fi
echo "DOC detectado: $DOC"
echo ""

echo "=== primeras 15 lineas ==="
head -15 "$DOC"

echo ""
echo "=== linea(s) con 'Orquestacion' o 'Orquestación' (con contexto) ==="
grep -n -B2 -A2 "Orquestaci" "$DOC"

echo ""
echo "=== seccion 5.2 completa (pendientes de validacion) ==="
python3 << PYEOF
path = "$DOC"
with open(path, encoding="utf-8") as f:
    lines = f.readlines()
start = None
end = None
for i, l in enumerate(lines):
    if l.strip().startswith("## 5.2") or l.strip().startswith("### 5.2") or "5.2" in l and ("pendiente" in l.lower() or "validaci" in l.lower()):
        start = i
        break
if start is not None:
    for j in range(start + 1, len(lines)):
        if lines[j].strip().startswith("## ") or lines[j].strip().startswith("### "):
            if j > start + 1:
                end = j
                break
    end = end or min(start + 60, len(lines))
    print("".join(lines[start:end]))
else:
    print("NO ENCONTRADO seccion 5.2 con ese patron - pegame el indice del documento (grep -n '^#' ) para ubicarla manualmente.")
PYEOF

echo ""
echo "=== linea de seccion 5.3 - Mod.15 Nomina (con contexto) ==="
grep -n -B2 -A2 "Mod. 15\|Mod.15\|Módulo 15\|Modulo 15\|fases 1-10 de 11" "$DOC"

echo ""
echo "=== FIN Parte 9 (discovery master doc) ==="
