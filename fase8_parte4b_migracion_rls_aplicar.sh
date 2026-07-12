#!/bin/bash
# ============================================================
# Fase 8 (Cesantía) - Parte 4b: inyectar RLS + aplicar migración
# ============================================================
# CAMBIOS:
#   - Inyecta RLS (ENABLE + FORCE + CREATE POLICY tenant_isolation)
#     en las 3 tablas nuevas (cesantia_configs, cesantia_scale_rows,
#     terminations) dentro de alembic/versions/b36b15cd58ab_cesantia.py,
#     usando el split por "def downgrade() -> None:" (no por conteo de
#     líneas en blanco, que la terminal suele comerse al pegar).
#   - Rebuildea la imagen (para meter el archivo de migración editado
#     dentro del contenedor - recordar: no hay bind-mount de código).
#   - Aplica la migración con alembic upgrade head.
#   - Verifica en Postgres que RLS quedó activo en las 3 tablas.
# Ejecutar: cd /opt/workforce-ai-os && bash fase8_parte4b_migracion_rls_aplicar.sh
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"
set -a
source .env 2>/dev/null || true
set +a

MIGRATION_FILE="apps/backend/alembic/versions/b36b15cd58ab_cesantia.py"

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
    for _table in ("cesantia_configs", "cesantia_scale_rows", "terminations"):
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
python3 -m py_compile "$MIGRATION_FILE" && echo "SYNTAX OK: migracion cesantia"

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
echo "(usando usuario=$PGUSER db=$PGDB - si falla, decime cual es el POSTGRES_USER real)"
docker compose exec -T postgres psql -U "$PGUSER" -d "$PGDB" -c "
SELECT relname, relrowsecurity, relforcerowsecurity
FROM pg_class
WHERE relname IN ('cesantia_configs', 'cesantia_scale_rows', 'terminations');
"
docker compose exec -T postgres psql -U "$PGUSER" -d "$PGDB" -c "
SELECT schemaname, tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('cesantia_configs', 'cesantia_scale_rows', 'terminations');
"

echo "=== FIN Parte 4b ==="
