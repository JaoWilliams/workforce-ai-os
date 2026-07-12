#!/bin/bash
# ============================================================
# UI/UX Nomina - Parte 4b: continuar (i18n + DB reset + build)
# El archivo corridas/page.js YA quedo bien escrito en la parte 4 -
# solo re-verificamos con el numero correcto (3, no 2) y seguimos.
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

python3 << 'PYEOF'
path = "apps/frontend/app/[locale]/dashboard/nomina/corridas/page.js"
with open(path, encoding="utf-8") as f:
    check = f.read()
assert check.count("DASH") >= 3, "la constante DASH no se uso donde se esperaba"
count = check.count("\\u2014")
assert count == 3, f"esperaba 3 ocurrencias de \\\\u2014 (formatMoney + celda de tabla + definicion de DASH), encontre {count}"
assert "{DASH}" in check, "no se encontro el uso de {DASH} en el JSX"
print("OK: corridas/page.js verificado correctamente (3 ocurrencias de \\\\u2014, {DASH} en uso)")
PYEOF

# ---------- i18n: legacy_status_title / legacy_status_desc ----------
python3 << 'PYEOF'
import json

nuevas_es = {
    "legacy_status_title": "Estado heredado",
    "legacy_status_desc": "Este período tiene un estado de un esquema anterior ('{status}'), previo a la orquestación de fase 11. No se puede continuar el flujo estándar desde acá.",
}
nuevas_en = {
    "legacy_status_title": "Legacy status",
    "legacy_status_desc": "This period has a status from a previous schema ('{status}'), before the fase 11 orchestration. The standard flow can't continue from here.",
}

for path, nuevas in [
    ("apps/frontend/messages/es.json", nuevas_es),
    ("apps/frontend/messages/en.json", nuevas_en),
]:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    data.setdefault("payroll_run", {})
    added = 0
    for k, v in nuevas.items():
        if k not in data["payroll_run"]:
            data["payroll_run"][k] = v
            added += 1
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"OK: {path} - payroll_run +{added}")
PYEOF

# ---------- resetear el periodo legado 'closed' a 'draft' ----------
set -a
source .env 2>/dev/null || true
set +a
PGUSER="${POSTGRES_USER:-postgres}"
PGDB="${POSTGRES_DB:-workforce_ai_os}"

echo "=== antes ==="
docker compose exec -T postgres psql -U "$PGUSER" -d "$PGDB" -c \
  "SELECT id, period_start, period_end, status FROM payroll_periods WHERE status = 'closed';"

docker compose exec -T postgres psql -U "$PGUSER" -d "$PGDB" -c \
  "UPDATE payroll_periods SET status = 'draft' WHERE status = 'closed';"

echo "=== despues ==="
docker compose exec -T postgres psql -U "$PGUSER" -d "$PGDB" -c \
  "SELECT status, count(*) FROM payroll_periods GROUP BY status ORDER BY status;"

# ---------- rebuild ----------
echo "=== rebuild frontend ==="
docker compose build --no-cache frontend
docker compose up -d frontend
sleep 5
docker compose logs frontend --tail 20

echo "=== FIN Parte 4b ==="
