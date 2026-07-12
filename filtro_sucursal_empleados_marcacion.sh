#!/bin/bash
# ============================================================
# Filtro de sucursal - Empleados + Marcacion (#166, parte 1/2)
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

# ---------- 1. empleados/page.js ----------
python3 << 'PYEOF'
path = "apps/frontend/app/[locale]/dashboard/empleados/page.js"
with open(path, encoding="utf-8") as f:
    src = f.read()

edits = []

edits.append(("branchFilter state", '''  const [searchQuery, setSearchQuery] = useState("");''',
'''  const [searchQuery, setSearchQuery] = useState("");
  const [branchFilter, setBranchFilter] = useState("");'''))

edits.append(("filteredEmployees con sucursal", '''  const filteredEmployees = employees.filter((emp) => {
    const q = searchQuery.trim().toLowerCase();
    if (!q) return true;
    return (
      emp.first_name.toLowerCase().includes(q) ||
      emp.last_name.toLowerCase().includes(q) ||
      emp.id_number.toLowerCase().includes(q) ||
      emp.position.toLowerCase().includes(q)
    );
  });''',
'''  const filteredEmployees = employees
    .filter((emp) => (branchFilter ? emp.branch_id === branchFilter : true))
    .filter((emp) => {
      const q = searchQuery.trim().toLowerCase();
      if (!q) return true;
      return (
        emp.first_name.toLowerCase().includes(q) ||
        emp.last_name.toLowerCase().includes(q) ||
        emp.id_number.toLowerCase().includes(q) ||
        emp.position.toLowerCase().includes(q)
      );
    });'''))

edits.append(("dropdown sucursal en header lista", '''          <div className="p-3 border-b border-bk-brown/10">
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder={t("search_placeholder")}
              className="w-full border border-bk-brown/20 rounded-md px-3 py-1.5 text-sm"
            />
          </div>''',
'''          <div className="p-3 border-b border-bk-brown/10 flex flex-col gap-2 sm:flex-row">
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder={t("search_placeholder")}
              className="w-full border border-bk-brown/20 rounded-md px-3 py-1.5 text-sm"
            />
            <select
              value={branchFilter}
              onChange={(e) => setBranchFilter(e.target.value)}
              className="border border-bk-brown/20 rounded-md px-3 py-1.5 text-sm sm:w-48"
            >
              <option value="">{t("filter_all_branches")}</option>
              {branches.map((b) => (
                <option key={b.id} value={b.id}>
                  {b.name}
                </option>
              ))}
            </select>
          </div>'''))

for label, old, new in edits:
    assert old in src, f"ANCHOR NOT FOUND ({label})"
    assert src.count(old) == 1, f"ANCHOR NOT UNIQUE ({label})"
    src = src.replace(old, new, 1)
    print(f"OK edicion aplicada (empleados): {label}")

with open(path, "w", encoding="utf-8") as f:
    f.write(src)

with open(path, encoding="utf-8") as f:
    check = f.read()
problemas = []
if check.count("{") != check.count("}"):
    problemas.append(f"llaves desbalanceadas: {{ {check.count('{')} vs }} {check.count('}')}")
if check.count("(") != check.count(")"):
    problemas.append(f"parentesis desbalanceados: ( {check.count('(')} vs ) {check.count(')')}")
for marker in ["branchFilter", "filter_all_branches"]:
    if marker not in check:
        problemas.append(f"falta: {marker}")
if problemas:
    print("XXX VERIFICACION FALLO XXX")
    for p in problemas:
        print(" -", p)
    raise SystemExit(1)
print("OK: empleados/page.js verificado correctamente")
PYEOF

# ---------- 2. marcacion/page.js ----------
python3 << 'PYEOF'
path = "apps/frontend/app/[locale]/dashboard/marcacion/page.js"
with open(path, encoding="utf-8") as f:
    src = f.read()

edits = []

edits.append(("branches state", '''  const [devices, setDevices] = useState([]);''',
'''  const [devices, setDevices] = useState([]);
  const [branches, setBranches] = useState([]);'''))

edits.append(("branchFilter state", '''  const [searchQuery, setSearchQuery] = useState("");''',
'''  const [searchQuery, setSearchQuery] = useState("");
  const [branchFilter, setBranchFilter] = useState("");'''))

edits.append(("fetch branches", '''    loadRecords();
    apiFetch("/api/employees").then(setEmployees).catch(() => {});
    apiFetch("/api/devices").then(setDevices).catch(() => {});
  }, []);''',
'''    loadRecords();
    apiFetch("/api/employees").then(setEmployees).catch(() => {});
    apiFetch("/api/devices").then(setDevices).catch(() => {});
    apiFetch("/api/branches").then(setBranches).catch(() => {});
  }, []);'''))

edits.append(("filteredRecords con sucursal", '''  const filteredRecords = records.filter((r) => {
    const q = searchQuery.trim().toLowerCase();
    if (!q) return true;
    return employeeName(r.employee_id).toLowerCase().includes(q);
  });''',
'''  const filteredRecords = records
    .filter((r) => {
      if (!branchFilter) return true;
      const emp = employees.find((x) => x.id === r.employee_id);
      return emp && emp.branch_id === branchFilter;
    })
    .filter((r) => {
      const q = searchQuery.trim().toLowerCase();
      if (!q) return true;
      return employeeName(r.employee_id).toLowerCase().includes(q);
    });'''))

edits.append(("dropdown sucursal en header lista", '''          <div className="p-3 border-b border-bk-brown/10">
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder={t("search_placeholder")}
              className="w-full border border-bk-brown/20 rounded-md px-3 py-1.5 text-sm"
            />
          </div>''',
'''          <div className="p-3 border-b border-bk-brown/10 flex flex-col gap-2 sm:flex-row">
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder={t("search_placeholder")}
              className="w-full border border-bk-brown/20 rounded-md px-3 py-1.5 text-sm"
            />
            <select
              value={branchFilter}
              onChange={(e) => setBranchFilter(e.target.value)}
              className="border border-bk-brown/20 rounded-md px-3 py-1.5 text-sm sm:w-48"
            >
              <option value="">{t("filter_all_branches")}</option>
              {branches.map((b) => (
                <option key={b.id} value={b.id}>
                  {b.name}
                </option>
              ))}
            </select>
          </div>'''))

for label, old, new in edits:
    assert old in src, f"ANCHOR NOT FOUND ({label})"
    assert src.count(old) == 1, f"ANCHOR NOT UNIQUE ({label})"
    src = src.replace(old, new, 1)
    print(f"OK edicion aplicada (marcacion): {label}")

with open(path, "w", encoding="utf-8") as f:
    f.write(src)

with open(path, encoding="utf-8") as f:
    check = f.read()
problemas = []
if check.count("{") != check.count("}"):
    problemas.append(f"llaves desbalanceadas: {{ {check.count('{')} vs }} {check.count('}')}")
if check.count("(") != check.count(")"):
    problemas.append(f"parentesis desbalanceados: ( {check.count('(')} vs ) {check.count(')')}")
for marker in ["branchFilter", "filter_all_branches", "setBranches"]:
    if marker not in check:
        problemas.append(f"falta: {marker}")
if problemas:
    print("XXX VERIFICACION FALLO XXX")
    for p in problemas:
        print(" -", p)
    raise SystemExit(1)
print("OK: marcacion/page.js verificado correctamente")
PYEOF

# ---------- 3. i18n: filter_all_branches en employees + attendance ----------
python3 << 'PYEOF'
import json

es_vals = {"filter_all_branches": "Todas las sucursales"}
en_vals = {"filter_all_branches": "All branches"}

for path, vals in [
    ("apps/frontend/messages/es.json", es_vals),
    ("apps/frontend/messages/en.json", en_vals),
]:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    for ns in ("employees", "attendance"):
        data.setdefault(ns, {})
        added = 0
        for k, v in vals.items():
            if k not in data[ns]:
                data[ns][k] = v
                added += 1
        print(f"OK: {path} - {ns} +{added}")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
PYEOF

echo "=== rebuild frontend ==="
docker compose build --no-cache frontend
docker compose up -d frontend
sleep 5
docker compose logs frontend --tail 30

echo "=== FIN filtro sucursal empleados+marcacion ==="
