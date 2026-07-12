#!/bin/bash
# ============================================================
# Fase 10 (Archivo bancario) - Parte 1: DISCOVERY (solo lectura)
# ============================================================
# No modifica nada. Junta el contexto exacto que necesito para
# construir fase 10 sin adivinar (mismo criterio de siempre: los
# anchors se toman del archivo real, nunca se asumen).
# Ejecutar: cd /opt/workforce-ai-os && bash fase10_parte1_discovery.sh
# Pegame TODO el output de vuelta.
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

echo "############################################################"
echo "# 1. Modulos existentes"
echo "############################################################"
find apps/backend/app/modules -maxdepth 1 -type d | sort

echo
echo "############################################################"
echo "# 2. Donde vive Employee (schemas y router)"
echo "############################################################"
grep -rln "class EmployeeCreate\|class EmployeeResponse\|class EmployeeUpdate" apps/backend/app/modules/ 2>/dev/null || echo "(no encontrado con ese patron)"
grep -rln "def create_employee\|def update_employee" apps/backend/app/modules/ 2>/dev/null || echo "(no encontrado con ese patron)"

echo
echo "############################################################"
echo "# 3. Bloque completo de la clase Employee en models.py"
echo "############################################################"
python3 << 'PYEOF'
import re
path = "apps/backend/app/db/models.py"
with open(path, encoding="utf-8") as f:
    lines = f.readlines()
start = None
for i, l in enumerate(lines):
    if l.startswith("class Employee(Base):"):
        start = i
        break
if start is None:
    print("NO ENCONTRADO: class Employee(Base):")
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
echo "# 4. Anchor 'class Device(Base):' (para insertar modelos nuevos)"
echo "############################################################"
grep -n "^class Device(Base):" apps/backend/app/db/models.py || echo "NO ENCONTRADO"

echo
echo "############################################################"
echo "# 5. Bloque completo de la clase PayrollPeriod en models.py"
echo "############################################################"
python3 << 'PYEOF'
path = "apps/backend/app/db/models.py"
with open(path, encoding="utf-8") as f:
    lines = f.readlines()
start = None
for i, l in enumerate(lines):
    if l.startswith("class PayrollPeriod(Base):"):
        start = i
        break
if start is None:
    print("NO ENCONTRADO: class PayrollPeriod(Base):")
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
echo "# 6. Firma y cuerpo de compute_net_payroll_rows (core/renta.py)"
echo "############################################################"
python3 << 'PYEOF'
path = "apps/backend/app/core/renta.py"
with open(path, encoding="utf-8") as f:
    lines = f.readlines()
start = None
for i, l in enumerate(lines):
    if "def compute_net_payroll_rows" in l:
        start = i
        break
if start is None:
    print("NO ENCONTRADO: def compute_net_payroll_rows")
else:
    end = min(start + 60, len(lines))
    print("".join(lines[start:end]))
PYEOF

echo
echo "############################################################"
echo "# 7. Bloque CesantiaConfig en catalogs/router.py (patron a espejar)"
echo "############################################################"
python3 << 'PYEOF'
path = "apps/backend/app/modules/catalogs/router.py"
with open(path, encoding="utf-8") as f:
    lines = f.readlines()
start = None
for i, l in enumerate(lines):
    if "cesantia-config" in l or "cesantia_config" in l.lower():
        start = i
        break
if start is None:
    print("NO ENCONTRADO: cesantia-config")
else:
    start = max(0, start - 5)
    end = min(start + 70, len(lines))
    print("".join(lines[start:end]))
PYEOF

echo
echo "############################################################"
echo "# 8. Imports (primeras 40 lineas) de catalogs/router.py"
echo "############################################################"
sed -n '1,40p' apps/backend/app/modules/catalogs/router.py

echo
echo "############################################################"
echo "# 9. include_router en main.py"
echo "############################################################"
grep -n "include_router\|^from app.modules" apps/backend/app/main.py

echo
echo "############################################################"
echo "# 10. Ultimas 30 lineas de catalogs/router.py (para saber donde termina el archivo)"
echo "############################################################"
tail -30 apps/backend/app/modules/catalogs/router.py

echo
echo "=== FIN discovery ==="
