#!/bin/bash
# ============================================================
# Retrofit busqueda/#127 - Feature Flags (v2: anchor de h1 aislado,
# habia una linea en blanco entre </h1> y {error && que v1 no esperaba)
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

python3 << 'PYEOF'
path = "apps/frontend/app/[locale]/dashboard/feature-flags/page.js"
with open(path, encoding="utf-8") as f:
    src = f.read()

edits = []

edits.append(("searchQuery state", '''  const [message, setMessage] = useState(null);''',
'''  const [message, setMessage] = useState(null);
  const [searchQuery, setSearchQuery] = useState("");'''))

edits.append(("filteredFlags + categories", '''  const categories = [...new Set(flags.map((f) => f.category))];''',
'''  const filteredFlags = flags.filter((f) => {
    const q = searchQuery.trim().toLowerCase();
    if (!q) return true;
    return f.name.toLowerCase().includes(q) || f.code.toLowerCase().includes(q);
  });
  const categories = [...new Set(filteredFlags.map((f) => f.category))];'''))

edits.append(("titulo + input busqueda", '''      <h1 className="font-heading text-2xl font-extrabold text-bk-brown mb-6">{t("title")}</h1>''',
'''      <div className="flex items-center justify-between mb-6">
        <h1 className="font-heading text-2xl font-extrabold text-bk-brown">{t("title")}</h1>
        <input
          type="text"
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          placeholder={t("search_placeholder")}
          className="border border-bk-brown/20 rounded-md px-3 py-1.5 text-sm w-64"
        />
      </div>'''))

edits.append(("estado sin resultados de busqueda", '''      {loading ? (
        <LoadingState />
      ) : flags.length === 0 ? (
        <EmptyState icon={ToggleLeft} message={t("no_flags")} />
      ) : (
        <div className="space-y-6">
          {categories.map((cat) => (''',
'''      {loading ? (
        <LoadingState />
      ) : flags.length === 0 ? (
        <EmptyState icon={ToggleLeft} message={t("no_flags")} />
      ) : filteredFlags.length === 0 ? (
        <p className="text-sm text-bk-brown/60">{t("no_search_results")}</p>
      ) : (
        <div className="space-y-6">
          {categories.map((cat) => ('''))

edits.append(("usar filteredFlags en el listado", '''              <ul className="divide-y divide-bk-brown/10">
                {flags
                  .filter((f) => f.category === cat)
                  .map((f) => (''',
'''              <ul className="divide-y divide-bk-brown/10">
                {filteredFlags
                  .filter((f) => f.category === cat)
                  .map((f) => ('''))

for label, old, new in edits:
    assert old in src, f"ANCHOR NOT FOUND ({label})"
    assert src.count(old) == 1, f"ANCHOR NOT UNIQUE ({label})"
    src = src.replace(old, new, 1)
    print(f"OK edicion aplicada: {label}")

with open(path, "w", encoding="utf-8") as f:
    f.write(src)

with open(path, encoding="utf-8") as f:
    check = f.read()
problemas = []
if check.count("{") != check.count("}"):
    problemas.append(f"llaves desbalanceadas: {{ {check.count('{')} vs }} {check.count('}')}")
if check.count("(") != check.count(")"):
    problemas.append(f"parentesis desbalanceados: ( {check.count('(')} vs ) {check.count(')')}")
for marker in ["searchQuery", "filteredFlags", "no_search_results"]:
    if marker not in check:
        problemas.append(f"falta: {marker}")
if problemas:
    print("XXX VERIFICACION FALLO XXX")
    for p in problemas:
        print(" -", p)
    raise SystemExit(1)
print("OK: feature-flags/page.js verificado correctamente")
PYEOF

# ---------- i18n: search_placeholder / no_search_results ----------
python3 << 'PYEOF'
import json

nuevas_es = {
    "search_placeholder": "Buscar flag...",
    "no_search_results": "No hay flags que coincidan con la búsqueda.",
}
nuevas_en = {
    "search_placeholder": "Search flag...",
    "no_search_results": "No flags match the search.",
}

for path, nuevas in [
    ("apps/frontend/messages/es.json", nuevas_es),
    ("apps/frontend/messages/en.json", nuevas_en),
]:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    data.setdefault("feature_flags", {})
    added = 0
    for k, v in nuevas.items():
        if k not in data["feature_flags"]:
            data["feature_flags"][k] = v
            added += 1
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"OK: {path} - feature_flags +{added}")
PYEOF

echo "=== rebuild frontend ==="
docker compose build --no-cache frontend
docker compose up -d frontend
sleep 5
docker compose logs frontend --tail 30

echo "=== FIN retrofit busqueda feature-flags v2 ==="
