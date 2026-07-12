#!/bin/bash
# ============================================================
# UI/UX Nomina - Parte 4: fix em-dash literal + status legado
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

# ---------- 1. fixes en corridas/page.js (5 ediciones ancladas) ----------
python3 << 'PYEOF'
path = "apps/frontend/app/[locale]/dashboard/nomina/corridas/page.js"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

edits = []

# A: agregar constante DASH
a_old = '''const PAY_FREQUENCIES = ["semanal", "quincenal", "bisemanal", "mensual"];

function emptyDraft() {'''
a_new = '''const PAY_FREQUENCIES = ["semanal", "quincenal", "bisemanal", "mensual"];
const DASH = "\\u2014";

function emptyDraft() {'''
edits.append(("A: const DASH", a_old, a_new))

# B: fix dash en la lista de corridas
b_old = '''                    <p className="text-sm font-semibold text-bk-brown">
                      {p.period_start} \\u2014 {p.period_end}
                    </p>'''
b_new = '''                    <p className="text-sm font-semibold text-bk-brown">
                      {p.period_start} {DASH} {p.period_end}
                    </p>'''
edits.append(("B: dash en lista", b_old, b_new))

# C: fix dash en el header de detalle
c_old = '''              <h1 className="font-heading text-xl font-extrabold text-bk-brown">
                {selectedPeriod.period_start} \\u2014 {selectedPeriod.period_end}
              </h1>'''
c_new = '''              <h1 className="font-heading text-xl font-extrabold text-bk-brown">
                {selectedPeriod.period_start} {DASH} {selectedPeriod.period_end}
              </h1>'''
edits.append(("C: dash en detalle", c_old, c_new))

# D: statusBadge con fallback para status desconocido
d_old = '''    const label = STATUS_ORDER.includes(status) ? t(`status_${status}`) : status;
    return (
      <span className={"inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[11px] font-semibold " + (colors[status] || "bg-bk-brown/10 text-bk-brown/70")}>
        {label}
      </span>
    );
  }'''
d_old_original = '''    return (
      <span className={"inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[11px] font-semibold " + (colors[status] || "bg-bk-brown/10 text-bk-brown/70")}>
        {t(`status_${status}`)}
      </span>
    );
  }'''
d_new = '''    const label = STATUS_ORDER.includes(status) ? t(`status_${status}`) : status;
    return (
      <span className={"inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[11px] font-semibold " + (colors[status] || "bg-bk-brown/10 text-bk-brown/70")}>
        {label}
      </span>
    );
  }'''
edits.append(("D: statusBadge fallback", d_old_original, d_new))

# E: renderActionPanel con guard para status legado
e_old = '''  function renderActionPanel() {
    if (!selectedPeriod) return null;
    const status = selectedPeriod.status;
    const canManage = hasPermission("payroll.manage");
    const unresolvedCount = flags.filter((f) => !f.resolved).length;

    return (
      <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5">
        <h2 className="font-heading font-bold text-bk-brown mb-1">{t(`step_${status}_title`)}</h2>
        <p className="text-xs text-bk-brown/60 mb-4">{t(`step_${status}_desc`)}</p>'''
e_new = '''  function renderActionPanel() {
    if (!selectedPeriod) return null;
    const status = selectedPeriod.status;
    const canManage = hasPermission("payroll.manage");
    const unresolvedCount = flags.filter((f) => !f.resolved).length;

    if (!STATUS_ORDER.includes(status)) {
      return (
        <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5">
          <h2 className="font-heading font-bold text-bk-brown mb-1">{t("legacy_status_title")}</h2>
          <p className="text-xs text-bk-brown/60">{t("legacy_status_desc", { status })}</p>
        </div>
      );
    }

    return (
      <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5">
        <h2 className="font-heading font-bold text-bk-brown mb-1">{t(`step_${status}_title`)}</h2>
        <p className="text-xs text-bk-brown/60 mb-4">{t(`step_${status}_desc`)}</p>'''
edits.append(("E: renderActionPanel guard", e_old, e_new))

for label, old, new in edits:
    assert old in src, f"ANCHOR NOT FOUND ({label})"
    assert src.count(old) == 1, f"ANCHOR NOT UNIQUE ({label})"
    src = src.replace(old, new, 1)
    print(f"OK edicion aplicada: {label}")

with open(path, "w", encoding="utf-8") as f:
    f.write(src)

# verificacion rapida: ya no debe quedar ningun — suelto fuera de comillas o de DASH
with open(path, encoding="utf-8") as f:
    check = f.read()
assert check.count("DASH") >= 3, "la constante DASH no se uso donde se esperaba"
assert check.count("\\u2014") == 2, f"esperaba 2 ocurrencias de \\\\u2014 (definicion + el string del guion en la tabla), encontre {check.count(chr(92)+'u2014')}"
print("OK: verificacion de corridas/page.js paso")
PYEOF

# ---------- 2. i18n: legacy_status_title / legacy_status_desc ----------
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

# ---------- 3. resetear el periodo legado 'closed' a 'draft' ----------
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

# ---------- 4. rebuild ----------
echo "=== rebuild frontend ==="
docker compose build --no-cache frontend
docker compose up -d frontend
sleep 5
docker compose logs frontend --tail 20

echo "=== FIN Parte 4 ==="
