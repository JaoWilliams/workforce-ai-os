#!/bin/bash
# ============================================================
# Fase 9 (Asientos contables) - Parte 4a: rebuild + generar migración
# ============================================================
# Mismo proceso que fase 8: rebuild (sin bind-mount de codigo) -> logs
# limpios -> alembic revision --autogenerate DENTRO del contenedor ->
# copiar el archivo generado AL HOST con docker compose cp.
# Ejecutar: cd /opt/workforce-ai-os && bash fase9_parte4a_migracion_generar.sh
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

echo "=== 1. Rebuild (sin cache) ==="
docker compose build --no-cache api

echo "=== 2. Up -d ==="
docker compose up -d api

echo "=== 3. Esperando arranque (5s) ==="
sleep 5

echo "=== 4. Logs recientes (buscando errores de arranque) ==="
docker compose logs api --tail 60

echo "=== 5. Generando migración autogenerate ==="
docker compose exec -T api alembic revision --autogenerate -m "asientos_contables"

echo "=== 6. Ubicando el archivo generado dentro del contenedor ==="
NEW_FILE=$(docker compose exec -T api bash -c "ls -t alembic/versions/*.py | head -1" | tr -d '\r')
echo "Archivo generado dentro del contenedor: $NEW_FILE"

echo "=== 7. Copiando al host ==="
docker compose cp "api:/app/$NEW_FILE" "apps/backend/$NEW_FILE"

echo "=== 8. Contenido del archivo copiado (revisar antes de aplicar) ==="
cat "apps/backend/$NEW_FILE"

echo "=== FIN Parte 4a — pega el contenido de arriba en el chat antes de aplicar la migración ==="
