#!/bin/bash
# ============================================================
# Renombrar "Corridas de Nomina" -> "Calendario de Nominas": la
# pantalla ya gestiona los periodos de pago (crear, listar, avanzar
# por sus 7 etapas) - solo el nombre no lo reflejaba. Cambio de
# i18n puro, sin tocar codigo/logica.
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

python3 << 'PYEOF'
import json

cambios_es = {
    ("nav", "payroll_runs"): "Calendario de Nóminas",
    ("payroll_run", "title"): "Calendario de Nóminas",
    ("payroll_run", "new_run"): "Nuevo período de pago",
}
cambios_en = {
    ("nav", "payroll_runs"): "Payroll Calendar",
    ("payroll_run", "title"): "Payroll Calendar",
    ("payroll_run", "new_run"): "New pay period",
}

for path, cambios in [
    ("apps/frontend/messages/es.json", cambios_es),
    ("apps/frontend/messages/en.json", cambios_en),
]:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    for (namespace, key), value in cambios.items():
        antes = data.get(namespace, {}).get(key)
        assert antes is not None, f"ANCHOR NOT FOUND: {namespace}.{key} en {path}"
        data[namespace][key] = value
        print(f"OK: {path} - {namespace}.{key}: '{antes}' -> '{value}'")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
PYEOF

echo "=== rebuild frontend ==="
docker compose build --no-cache frontend
docker compose up -d frontend
sleep 6
docker compose logs frontend --tail 30

echo "=== FIN renombrar calendario de nominas ==="
