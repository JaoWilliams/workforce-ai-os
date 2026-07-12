#!/bin/bash
# ============================================================
# Fase 10 (Archivo bancario) - Parte 5b: inyectar RLS + aplicar
# ============================================================
# Inyecta RLS en las 3 tablas nuevas (bank_file_configs,
# bank_transfer_files, bank_transfer_file_lines). employees ya tenia
# RLS desde mod.9 -- solo se le agregaron columnas, no hace falta
# volver a activarlo.
# Ejecutar: cd /opt/workforce-ai-os && bash fase10_parte5b_rls_apply.sh
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"
set -a
source .env 2>/dev/null || true
set +a

MIGRATION_FILE="apps/backend/alembic/versions/a372cffde918_archivo_bancario.py"

python3 << PYEOF
path = "$MIGRATION_FILE"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

marker = "def downgrade() -> None:"
assert marker in src, "ANCHOR NOT FOUND: def downgrade()"
assert src.count(marker) == 1, "ANCHOR NOT UNIQUE: def downgrade()"

if "ENABLE ROW LEVEL SECURITY" in src:
    print("SKIP: la migracion ya tiene RLS inyectado (idempotente)")
else:
    rls_block = '''    for _table in ("bank_file_configs", "bank_transfer_files", "bank_transfer_file_lines"):
        op.execute(f"ALTER TABLE {_table} ENABLE ROW LEVEL SECURITY")
        op.execute(f"ALTER TABLE {_table} FORCE ROW LEVEL SECURITY")
        op.execute(f"""
            CREATE POLICY tenant_isolation ON {_table}
            USING (tenant_id = current_setting('app.current_tenant', true)::uuid)
            WITH CHECK (tenant_id = current_setting('app.current_tenant', true)::uuid)
        """)

'''
    parts = src.split(marker)
    assert len(parts) == 2, "SPLIT FAILED"
    src = parts[0] + rls_block + marker + parts[1]
    with open(path, "w", encoding="utf-8") as f:
        f.write(src)
    print("OK: RLS inyectado en", path)
PYEOF

python3 -m py_compile "$MIGRATION_FILE" && echo "SYNTAX OK: migracion con RLS"

echo "=== contenido final (verificacion visual) ==="
cat "$MIGRATION_FILE"

echo "=== rebuild (para meter la migracion con RLS dentro de la imagen) ==="
docker compose build --no-cache api
docker compose up -d api
sleep 5
docker compose logs api --tail 20

echo "=== aplicando migracion ==="
docker compose exec -T api alembic upgrade head

echo "=== verificando RLS en Postgres ==="
PGUSER="${POSTGRES_USER:-postgres}"
PGDB="${POSTGRES_DB:-workforce_ai_os}"
docker compose exec -T postgres psql -U "$PGUSER" -d "$PGDB" -c \
  "SELECT relname, relrowsecurity, relforcerowsecurity FROM pg_class WHERE relname IN ('bank_file_configs','bank_transfer_files','bank_transfer_file_lines');"
docker compose exec -T postgres psql -U "$PGUSER" -d "$PGDB" -c \
  "SELECT tablename, policyname FROM pg_policies WHERE tablename IN ('bank_file_configs','bank_transfer_files','bank_transfer_file_lines');"

echo "=== verificando columnas nuevas en employees ==="
docker compose exec -T postgres psql -U "$PGUSER" -d "$PGDB" -c "\d employees" | grep -i bank

echo "=== FIN Parte 5b ==="
