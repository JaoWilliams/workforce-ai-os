#!/bin/bash
# ============================================================
# Retrofit busqueda/#127 - Confianza Operativa + Excepciones
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

# ---------- 1. confianza/page.js ----------
python3 << 'PYEOF'
path = "apps/frontend/app/[locale]/dashboard/confianza/page.js"
with open(path, encoding="utf-8") as f:
    src = f.read()

edits = []

edits.append(("searchQuery state", '''  const [resolvingId, setResolvingId] = useState(null);''',
'''  const [resolvingId, setResolvingId] = useState(null);
  const [searchQuery, setSearchQuery] = useState("");'''))

edits.append(("displayed con busqueda", '''  const displayed = flags.filter((f) => {
    if (filter === "pending") return !f.resolved;
    if (filter === "resolved") return f.resolved;
    return true;
  });''',
'''  const displayed = flags
    .filter((f) => {
      if (filter === "pending") return !f.resolved;
      if (filter === "resolved") return f.resolved;
      return true;
    })
    .filter((f) => {
      const q = searchQuery.trim().toLowerCase();
      if (!q) return true;
      return (
        employeeName(f.employee_id).toLowerCase().includes(q) ||
        ruleLabel(f.rule_code).toLowerCase().includes(q)
      );
    });'''))

edits.append(("input de busqueda en filtros", '''      <div className="flex gap-2 mb-6">
        {["all", "pending", "resolved"].map((f) => (
          <button
            key={f}
            onClick={() => setFilter(f)}
            className={
              filter === f
                ? "text-xs font-semibold rounded-full px-4 py-1.5 text-white"
                : "text-xs font-semibold rounded-full px-4 py-1.5 border border-bk-brown/20 text-bk-brown/70"
            }
            style={
              filter === f
                ? { background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }
                : {}
            }
          >
            {t("filter_" + f)}
          </button>
        ))}
      </div>''',
'''      <div className="flex flex-wrap items-center gap-2 mb-6">
        {["all", "pending", "resolved"].map((f) => (
          <button
            key={f}
            onClick={() => setFilter(f)}
            className={
              filter === f
                ? "text-xs font-semibold rounded-full px-4 py-1.5 text-white"
                : "text-xs font-semibold rounded-full px-4 py-1.5 border border-bk-brown/20 text-bk-brown/70"
            }
            style={
              filter === f
                ? { background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }
                : {}
            }
          >
            {t("filter_" + f)}
          </button>
        ))}
        <input
          type="text"
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          placeholder={t("search_placeholder")}
          className="border border-bk-brown/20 rounded-md px-3 py-1.5 text-sm ml-auto w-56"
        />
      </div>'''))

for label, old, new in edits:
    assert old in src, f"ANCHOR NOT FOUND ({label})"
    assert src.count(old) == 1, f"ANCHOR NOT UNIQUE ({label})"
    src = src.replace(old, new, 1)
    print(f"OK edicion aplicada (confianza): {label}")

with open(path, "w", encoding="utf-8") as f:
    f.write(src)

with open(path, encoding="utf-8") as f:
    check = f.read()
problemas = []
if check.count("{") != check.count("}"):
    problemas.append(f"llaves desbalanceadas: {{ {check.count('{')} vs }} {check.count('}')}")
if check.count("(") != check.count(")"):
    problemas.append(f"parentesis desbalanceados: ( {check.count('(')} vs ) {check.count(')')}")
for marker in ["searchQuery", "search_placeholder"]:
    if marker not in check:
        problemas.append(f"falta: {marker}")
if problemas:
    print("XXX VERIFICACION FALLO XXX")
    for p in problemas:
        print(" -", p)
    raise SystemExit(1)
print("OK: confianza/page.js verificado correctamente")
PYEOF

# ---------- 2. excepciones/page.js ----------
python3 << 'PYEOF'
path = "apps/frontend/app/[locale]/dashboard/excepciones/page.js"
with open(path, encoding="utf-8") as f:
    src = f.read()

edits = []

edits.append(("searchQuery state", '''  const [reviewNotesMap, setReviewNotesMap] = useState({});''',
'''  const [reviewNotesMap, setReviewNotesMap] = useState({});
  const [searchQuery, setSearchQuery] = useState("");'''))

edits.append(("displayed con busqueda", '''  const displayed = exceptions.filter((exc) => {
    if (filter === "all") return true;
    return exc.status === filter;
  });''',
'''  const displayed = exceptions
    .filter((exc) => {
      if (filter === "all") return true;
      return exc.status === filter;
    })
    .filter((exc) => {
      const q = searchQuery.trim().toLowerCase();
      if (!q) return true;
      return (
        employeeName(exc.employee_id).toLowerCase().includes(q) ||
        typeLabel(exc.exception_type).toLowerCase().includes(q) ||
        exc.justification.toLowerCase().includes(q)
      );
    });'''))

edits.append(("input de busqueda en filtros", '''      <div className="flex gap-2 mb-6">
        {["all", "pending", "approved", "rejected"].map((f) => (
          <button
            key={f}
            onClick={() => setFilter(f)}
            className={
              filter === f
                ? "text-xs font-semibold rounded-full px-4 py-1.5 text-white"
                : "text-xs font-semibold rounded-full px-4 py-1.5 border border-bk-brown/20 text-bk-brown/70"
            }
            style={
              filter === f
                ? { background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }
                : {}
            }
          >
            {t("filter_" + f)}
          </button>
        ))}
      </div>''',
'''      <div className="flex flex-wrap items-center gap-2 mb-6">
        {["all", "pending", "approved", "rejected"].map((f) => (
          <button
            key={f}
            onClick={() => setFilter(f)}
            className={
              filter === f
                ? "text-xs font-semibold rounded-full px-4 py-1.5 text-white"
                : "text-xs font-semibold rounded-full px-4 py-1.5 border border-bk-brown/20 text-bk-brown/70"
            }
            style={
              filter === f
                ? { background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }
                : {}
            }
          >
            {t("filter_" + f)}
          </button>
        ))}
        <input
          type="text"
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          placeholder={t("search_placeholder")}
          className="border border-bk-brown/20 rounded-md px-3 py-1.5 text-sm ml-auto w-56"
        />
      </div>'''))

for label, old, new in edits:
    assert old in src, f"ANCHOR NOT FOUND ({label})"
    assert src.count(old) == 1, f"ANCHOR NOT UNIQUE ({label})"
    src = src.replace(old, new, 1)
    print(f"OK edicion aplicada (excepciones): {label}")

with open(path, "w", encoding="utf-8") as f:
    f.write(src)

with open(path, encoding="utf-8") as f:
    check = f.read()
problemas = []
if check.count("{") != check.count("}"):
    problemas.append(f"llaves desbalanceadas: {{ {check.count('{')} vs }} {check.count('}')}")
if check.count("(") != check.count(")"):
    problemas.append(f"parentesis desbalanceados: ( {check.count('(')} vs ) {check.count(')')}")
for marker in ["searchQuery", "search_placeholder"]:
    if marker not in check:
        problemas.append(f"falta: {marker}")
if problemas:
    print("XXX VERIFICACION FALLO XXX")
    for p in problemas:
        print(" -", p)
    raise SystemExit(1)
print("OK: excepciones/page.js verificado correctamente")
PYEOF

# ---------- 3. i18n: search_placeholder en confianza + exceptions_page ----------
python3 << 'PYEOF'
import json

conf_es = {"search_placeholder": "Buscar por empleado o regla..."}
conf_en = {"search_placeholder": "Search by employee or rule..."}
exc_es = {"search_placeholder": "Buscar por empleado, tipo o justificación..."}
exc_en = {"search_placeholder": "Search by employee, type, or justification..."}

for path, cvals, evals in [
    ("apps/frontend/messages/es.json", conf_es, exc_es),
    ("apps/frontend/messages/en.json", conf_en, exc_en),
]:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    data.setdefault("confianza", {})
    added = 0
    for k, v in cvals.items():
        if k not in data["confianza"]:
            data["confianza"][k] = v
            added += 1
    print(f"OK: {path} - confianza +{added}")
    data.setdefault("exceptions_page", {})
    added2 = 0
    for k, v in evals.items():
        if k not in data["exceptions_page"]:
            data["exceptions_page"][k] = v
            added2 += 1
    print(f"OK: {path} - exceptions_page +{added2}")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
PYEOF

echo "=== rebuild frontend ==="
docker compose build --no-cache frontend
docker compose up -d frontend
sleep 5
docker compose logs frontend --tail 30

echo "=== FIN retrofit busqueda confianza+excepciones ==="
