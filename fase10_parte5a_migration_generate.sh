#!/bin/bash
# ============================================================
# Fase 10 (Archivo bancario) - Parte 5a: build + generar migracion
# ============================================================
# Reconstruye la imagen con el codigo nuevo (modelos + core + modulo
# bank_file + wiring en main.py), confirma arranque limpio, genera la
# migracion autogenerada y la copia al host para inyectarle RLS
# (Docker no tiene bind-mount en vivo -- lo que se genera DENTRO del
# contenedor se pierde si no se copia afuera antes del proximo build).
# Ejecutar: cd /opt/workforce-ai-os && bash fase10_parte5a_migration_generate.sh
# Pegame TODO el output de vuelta (necesito ver el contenido de la
# migracion generada antes de inyectarle RLS).
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

echo "=== build (bakea el codigo nuevo) ==="
docker compose build --no-cache api

echo "=== up ==="
docker compose up -d api
sleep 5

echo "=== logs (confirmar arranque limpio) ==="
docker compose logs api --tail 40

echo "=== generando migracion autogenerada ==="
docker compose exec -T api alembic revision --autogenerate -m "archivo_bancario"

echo "=== localizando el archivo generado ==="
NEW_FILE=$(docker compose exec -T api bash -c "ls -t alembic/versions/*.py | head -1" | tr -d '\r')
echo "Archivo generado: $NEW_FILE"

echo "=== copiando al host ==="
docker compose cp "api:/app/$NEW_FILE" "apps/backend/$NEW_FILE"

echo "=== CONTENIDO (pegame esto completo) ==="
cat "apps/backend/$NEW_FILE"

echo "=== FIN Parte 5a ==="
