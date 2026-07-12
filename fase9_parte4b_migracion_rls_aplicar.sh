#!/bin/bash
# ============================================================
# Fase 9 (Asientos contables) - Parte 4b: inyectar RLS + aplicar migración
# ============================================================
# Inyecta RLS en chart_of_accounts, journal_entries, journal_entry_lines
# (payroll_concepts ya tenia RLS desde mod.6, el ALTER TABLE de la
# columna nueva no lo afecta). Split por "def downgrade() -> None:"
# (no por lineas en blanco).
# Ejecutar: cd /opt/workforce-ai-os && bash fase9_parte4b_migracion_rls_aplicar.sh
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"
set -a
source .env 2>/dev/null || true
set +a

MIGRATION_FILE="apps/backend/alembic/versions/df26253754a1_asientos_contables.py"

python3 << PYEOF
path = "$MIGRATION_FILE"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

marker = "def downgrade() -> None:"
assert marker in src, "ANCHOR NOT FOUND: def downgrade() -> None:"
assert "tenant_isolation" not in src, "El archivo ya tiene RLS inyectado - no se toca de nuevo"

idx = src.index(marker)
before = src[:idx]
after = src[idx:]

rls_block = '''
    for _table in ("chart_of_accounts", "journal_entries", "journal_entry_lines"):
        op.execute(f"ALTER TABLE {_table} ENABLE ROW LEVEL SECURITY")
        op.execute(f"ALTER TABLE {_table} FORCE ROW LEVEL SECURITY")
        op.execute(f"""
            CREATE POLICY tenant_isolation ON {_table}
            USING (tenant_id = current_setting('app.current_tenant', true)::uuid)
            WITH CHECK (tenant_id = current_setting('app.current_tenant', true)::uuid)
        """)


'''

new_src = before.rstrip("\\n") + "\\n" + rls_block + after

with open(path, "w", encoding="utf-8") as f:
    f.write(new_src)

print("OK: RLS inyectado en", path)
PYEOF

echo "=== verificando sintaxis (host python3) ==="
python3 -m py_compile "$MIGRATION_FILE" && echo "SYNTAX OK: migracion asientos_contables"

echo "=== contenido final de la migración (revisar) ==="
cat "$MIGRATION_FILE"

echo "=== rebuild (para meter la migración editada dentro del contenedor) ==="
docker compose build --no-cache api
docker compose up -d api
sleep 5
docker compose logs api --tail 30

echo "=== aplicando migración ==="
docker compose exec -T api alembic upgrade head

echo "=== verificando RLS en Postgres ==="
PGUSER="${POSTGRES_USER:-postgres}"
PGDB="${POSTGRES_DB:-workforce_ai_os}"
echo "(usando usuario=$PGUSER db=$PGDB)"
docker compose exec -T postgres psql -U "$PGUSER" -d "$PGDB" -c "
SELECT relname, relrowsecurity, relforcerowsecurity
FROM pg_class
WHERE relname IN ('chart_of_accounts', 'journal_entries', 'journal_entry_lines');
"
docker compose exec -T postgres psql -U "$PGUSER" -d "$PGDB" -c "
SELECT schemaname, tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('chart_of_accounts', 'journal_entries', 'journal_entry_lines');
"

echo "=== confirmando columna nueva en payroll_concepts ==="
docker compose exec -T postgres psql -U "$PGUSER" -d "$PGDB" -c "\\d payroll_concepts" | grep -i accounting

echo "=== FIN Parte 4b ==="
