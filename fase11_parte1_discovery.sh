#!/bin/bash
# ============================================================
# Fase 11 (Orquestacion y auto-validacion) - Parte 1: DISCOVERY
# ============================================================
# Solo lectura. Fase grande (4 piezas), necesito ver:
#  1. Donde se usa PayrollPeriod.status hoy (para no romper nada al
#     ampliar de 3 a 7 estados).
#  2. La forma completa de la fila que devuelve compute_payroll_rows
#     (para saber que congelar en el snapshot).
#  3. El modelo + router de TimeException (mod 14) - patron a espejar
#     para la cola de excepciones de nomina.
#  4. El modelo + motor de reglas de TrustFlag (mod 17a) - patron a
#     reusar/extender para las 6 reglas de anomalia.
# Ejecutar: cd /opt/workforce-ai-os && bash fase11_parte1_discovery.sh
# Pegame TODO el output de vuelta.
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

echo "############################################################"
echo "# 1. Donde se usa PayrollPeriod.status / 'draft'/'closed'/'paid'"
echo "############################################################"
grep -rn "PayrollPeriod.status\|period\.status\|\.status == \"draft\"\|\.status == \"closed\"\|\.status == \"paid\"" apps/backend/app/ 2>/dev/null

echo
echo "############################################################"
echo "# 2. Funcion compute_payroll_rows completa (core/payroll.py)"
echo "############################################################"
python3 << 'PYEOF'
path = "apps/backend/app/core/payroll.py"
with open(path, encoding="utf-8") as f:
    lines = f.readlines()
start = None
for i, l in enumerate(lines):
    if "def compute_payroll_rows" in l:
        start = i
        break
if start is None:
    print("NO ENCONTRADO")
else:
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if (lines[j].startswith("async def ") or lines[j].startswith("def ")) and j > start:
            end = j
            break
    print("".join(lines[start:end]))
PYEOF

echo
echo "############################################################"
echo "# 3. Modelo TimeException completo (models.py)"
echo "############################################################"
python3 << 'PYEOF'
path = "apps/backend/app/db/models.py"
with open(path, encoding="utf-8") as f:
    lines = f.readlines()
start = None
for i, l in enumerate(lines):
    if l.startswith("class TimeException(Base):"):
        start = i
        break
if start is None:
    print("NO ENCONTRADO")
else:
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if lines[j].startswith("class ") and lines[j].strip().endswith("(Base):"):
            end = j
            break
    print("".join(lines[start:end]))
PYEOF

echo
echo "############################################################"
echo "# 4. Modelo TrustFlag completo (models.py)"
echo "############################################################"
python3 << 'PYEOF'
path = "apps/backend/app/db/models.py"
with open(path, encoding="utf-8") as f:
    lines = f.readlines()
start = None
for i, l in enumerate(lines):
    if l.startswith("class TrustFlag(Base):"):
        start = i
        break
if start is None:
    print("NO ENCONTRADO")
else:
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if lines[j].startswith("class ") and lines[j].strip().endswith("(Base):"):
            end = j
            break
    print("".join(lines[start:end]))
PYEOF

echo
echo "############################################################"
echo "# 5. Modulos existentes relacionados (confianza_operativa, exceptions, payroll)"
echo "############################################################"
find apps/backend/app/modules/confianza_operativa apps/backend/app/modules/exceptions apps/backend/app/modules/payroll -type f -name "*.py" | sort

echo
echo "############################################################"
echo "# 6. Motor de reglas de confianza operativa - nombres de funciones"
echo "############################################################"
grep -n "^def \|^async def " apps/backend/app/core/confianza_operativa.py 2>/dev/null || find / -maxdepth 6 -iname "*confianza*" 2>/dev/null

echo
echo "=== FIN discovery fase 11 parte 1 ==="
