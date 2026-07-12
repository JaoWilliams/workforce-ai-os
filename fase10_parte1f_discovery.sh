#!/bin/bash
# ============================================================
# Fase 10 - Parte 1f: DISCOVERY micro (boilerplate de test_accounting_e2e.py)
# ============================================================
# Solo lectura. Necesito el arranque exacto (imports, conexion DB,
# como se obtiene tenant/branch/usuario real) para armar el test de
# fase 10 con el mismo patron -- no quiero adivinar la URL de conexion.
# Ejecutar: cd /opt/workforce-ai-os && bash fase10_parte1f_discovery.sh
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

if [ -f test_accounting_e2e.py ]; then
    echo "=== primeras 70 lineas de test_accounting_e2e.py ==="
    sed -n '1,70p' test_accounting_e2e.py
else
    echo "test_accounting_e2e.py no esta en el directorio actual"
    find / -maxdepth 4 -iname "test_accounting_e2e.py" 2>/dev/null
fi

echo
echo "=== FIN discovery 1f ==="
