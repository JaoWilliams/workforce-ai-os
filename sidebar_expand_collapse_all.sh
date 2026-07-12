#!/bin/bash
# ============================================================
# Sidebar: boton expandir/contraer todas las categorias (#159)
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

python3 << 'PYEOF'
path = "apps/frontend/app/[locale]/dashboard/layout.js"
with open(path, encoding="utf-8") as f:
    src = f.read()

edits = []

edits.append(("toggleAllGroups fn", '''  function toggleGroup(key) {
    setExpanded((prev) => {
      const next = { ...prev, [key]: !prev[key] };
      try {
        const collapsedKeys = Object.keys(next).filter((k) => !next[k]);
        window.localStorage.setItem(SIDEBAR_STORAGE_KEY, JSON.stringify(collapsedKeys));
      } catch (e) {
        // localStorage no disponible - se ignora, el estado igual cambia en memoria
      }
      return next;
    });
  }''',
'''  function toggleGroup(key) {
    setExpanded((prev) => {
      const next = { ...prev, [key]: !prev[key] };
      try {
        const collapsedKeys = Object.keys(next).filter((k) => !next[k]);
        window.localStorage.setItem(SIDEBAR_STORAGE_KEY, JSON.stringify(collapsedKeys));
      } catch (e) {
        // localStorage no disponible - se ignora, el estado igual cambia en memoria
      }
      return next;
    });
  }
  function toggleAllGroups() {
    setExpanded((prev) => {
      const shouldExpand = !visibleGroups.every((g) => prev[g.key]);
      const next = { ...prev };
      visibleGroups.forEach((g) => {
        next[g.key] = shouldExpand;
      });
      try {
        const collapsedKeys = Object.keys(next).filter((k) => !next[k]);
        window.localStorage.setItem(SIDEBAR_STORAGE_KEY, JSON.stringify(collapsedKeys));
      } catch (e) {
        // localStorage no disponible - se ignora, el estado igual cambia en memoria
      }
      return next;
    });
  }'''))

edits.append(("allExpanded const", '''  const visibleGroups = NAV_GROUPS.map((g) => ({
    ...g,
    items: g.items.filter(isVisible),
  })).filter((g) => g.items.length > 0);''',
'''  const visibleGroups = NAV_GROUPS.map((g) => ({
    ...g,
    items: g.items.filter(isVisible),
  })).filter((g) => g.items.length > 0);
  const allExpanded = visibleGroups.length > 0 && visibleGroups.every((g) => expanded[g.key]);'''))

edits.append(("boton en JSX", '''            })()}
          </div>
          <div className="space-y-1">''',
'''            })()}
          </div>
          <div className="flex justify-end px-1 pb-2">
            <button
              type="button"
              onClick={toggleAllGroups}
              className="text-[10px] font-semibold uppercase tracking-wide text-bk-cream/40 hover:text-bk-cream/70 transition"
            >
              {allExpanded ? t("collapse_all") : t("expand_all")}
            </button>
          </div>
          <div className="space-y-1">'''))

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
for marker in ["toggleAllGroups", "allExpanded", "collapse_all", "expand_all"]:
    if marker not in check:
        problemas.append(f"falta: {marker}")
if problemas:
    print("XXX VERIFICACION FALLO XXX")
    for p in problemas:
        print(" -", p)
    raise SystemExit(1)
print("OK: layout.js verificado correctamente")
PYEOF

# ---------- i18n: nav.expand_all / nav.collapse_all ----------
python3 << 'PYEOF'
import json

nuevas_es = {"expand_all": "Expandir todo", "collapse_all": "Contraer todo"}
nuevas_en = {"expand_all": "Expand all", "collapse_all": "Collapse all"}

for path, nuevas in [
    ("apps/frontend/messages/es.json", nuevas_es),
    ("apps/frontend/messages/en.json", nuevas_en),
]:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    data.setdefault("nav", {})
    added = 0
    for k, v in nuevas.items():
        if k not in data["nav"]:
            data["nav"][k] = v
            added += 1
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"OK: {path} - nav +{added}")
PYEOF

echo "=== rebuild frontend ==="
docker compose build --no-cache frontend
docker compose up -d frontend
sleep 5
docker compose logs frontend --tail 30

echo "=== FIN sidebar expand/collapse all ==="
