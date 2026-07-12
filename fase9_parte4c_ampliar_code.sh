#!/bin/bash
# ============================================================
# Fase 9 (Asientos contables) - Parte 4c: ampliar ChartOfAccount.code
# ============================================================
# ChartOfAccount.code era String(20) - muy corto para codigos contables
# descriptivos reales (ej. "PASIVO-SALARIOS-POR-PAGAR" = 25 caracteres).
# Se amplia a String(50) en vez de forzar abreviaturas crípticas.
# Ejecutar: cd /opt/workforce-ai-os && bash fase9_parte4c_ampliar_code.sh
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"
set -a
source .env 2>/dev/null || true
set +a

python3 << 'PYEOF'
path = "apps/backend/app/db/models.py"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

anchor = '''    code: Mapped[str] = mapped_column(String(20), nullable=False)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    # activo | pasivo | patrimonio | ingreso | gasto
    account_type: Mapped[str] = mapped_column(String(20), nullable=False)'''
assert anchor in src, "ANCHOR NOT FOUND: ChartOfAccount.code"
assert src.count(anchor) == 1, "ANCHOR NOT UNIQUE"
src = src.replace(anchor, anchor.replace("String(20), nullable=False)\n    name", "String(50), nullable=False)\n    name"))

with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("OK: ChartOfAccount.code ampliado a String(50)")
PYEOF

python3 -m py_compile apps/backend/app/db/models.py && echo "SYNTAX OK: models.py"

echo "=== rebuild ==="
docker compose build --no-cache api
docker compose up -d api
sleep 5
docker compose logs api --tail 30

echo "=== generando migracion ==="
docker compose exec -T api alembic revision --autogenerate -m "widen_chart_of_account_code"
NEW_FILE=$(docker compose exec -T api bash -c "ls -t alembic/versions/*.py | head -1" | tr -d '\r')
echo "Archivo generado: $NEW_FILE"
docker compose cp "api:/app/$NEW_FILE" "apps/backend/$NEW_FILE"
echo "=== contenido ==="
cat "apps/backend/$NEW_FILE"

echo "=== rebuild (meter la migracion) + aplicar ==="
docker compose build --no-cache api
docker compose up -d api
sleep 5
docker compose logs api --tail 20
docker compose exec -T api alembic upgrade head

echo "=== verificando columna ==="
PGUSER="${POSTGRES_USER:-postgres}"
PGDB="${POSTGRES_DB:-workforce_ai_os}"
docker compose exec -T postgres psql -U "$PGUSER" -d "$PGDB" -c "\\d chart_of_accounts" | grep -i code

echo "=== FIN Parte 4c ==="
