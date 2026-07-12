#!/bin/bash
# ============================================================
# Filtro de sucursal - Excepciones + Confianza Operativa (#166, parte 2/2, v2)
# v2: anchor del dropdown ahora es autocontenido (solo el <input>, sin
# depender de lo que viene despues - habia una linea en blanco antes
# de {error && que v1 no esperaba).
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

# ---------- 1. excepciones/page.js ----------
python3 << 'PYEOF'
path = "apps/frontend/app/[locale]/dashboard/excepciones/page.js"
with open(path, encoding="utf-8") as f:
    src = f.read()

edits = []

edits.append(("branches state", '''  const [trustFlags, setTrustFlags] = useState([]);''',
'''  const [trustFlags, setTrustFlags] = useState([]);
  const [branches, setBranches] = useState([]);'''))

edits.append(("branchFilter state", '''  const [searchQuery, setSearchQuery] = useState("");''',
'''  const [searchQuery, setSearchQuery] = useState("");
  const [branchFilter, setBranchFilter] = useState("");'''))

edits.append(("fetch branches", '''  useEffect(() => {
    load();
    apiFetch("/api/employees").then(setEmployees).catch(() => {});
    apiFetch("/api/attendance").then(setAttendanceRecords).catch(() => {});
    apiFetch("/api/confianza-operativa/flags").then(setTrustFlags).catch(() => {});
  }, []);''',
'''  useEffect(() => {
    load();
    apiFetch("/api/employees").then(setEmployees).catch(() => {});
    apiFetch("/api/attendance").then(setAttendanceRecords).catch(() => {});
    apiFetch("/api/confianza-operativa/flags").then(setTrustFlags).catch(() => {});
    apiFetch("/api/branches").then(setBranches).catch(() => {});
  }, []);'''))

edits.append(("displayed con sucursal", '''  const displayed = exceptions
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
    });''',
'''  const displayed = exceptions
    .filter((exc) => {
      if (filter === "all") return true;
      return exc.status === filter;
    })
    .filter((exc) => {
      if (!branchFilter) return true;
      const emp = employees.find((x) => x.id === exc.employee_id);
      return emp && emp.branch_id === branchFilter;
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

edits.append(("dropdown sucursal autocontenido", '''        <input
          type="text"
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          placeholder={t("search_placeholder")}
          className="border border-bk-brown/20 rounded-md px-3 py-1.5 text-sm ml-auto w-56"
        />''',
'''        <select
          value={branchFilter}
          onChange={(e) => setBranchFilter(e.target.value)}
          className="border border-bk-brown/20 rounded-md px-3 py-1.5 text-sm ml-auto sm:w-44"
        >
          <option value="">{t("filter_all_branches")}</option>
          {branches.map((b) => (
            <option key={b.id} value={b.id}>
              {b.name}
            </option>
          ))}
        </select>
        <input
          type="text"
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          placeholder={t("search_placeholder")}
          className="border border-bk-brown/20 rounded-md px-3 py-1.5 text-sm w-56"
        />'''))

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
for marker in ["branchFilter", "filter_all_branches", "setBranches"]:
    if marker not in check:
        problemas.append(f"falta: {marker}")
if problemas:
    print("XXX VERIFICACION FALLO XXX")
    for p in problemas:
        print(" -", p)
    raise SystemExit(1)
print("OK: excepciones/page.js verificado correctamente")
PYEOF

# ---------- 2. confianza/page.js ----------
python3 << 'PYEOF'
path = "apps/frontend/app/[locale]/dashboard/confianza/page.js"
with open(path, encoding="utf-8") as f:
    src = f.read()

edits = []

edits.append(("branches state", '''  const [employees, setEmployees] = useState([]);''',
'''  const [employees, setEmployees] = useState([]);
  const [branches, setBranches] = useState([]);'''))

edits.append(("branchFilter state", '''  const [searchQuery, setSearchQuery] = useState("");''',
'''  const [searchQuery, setSearchQuery] = useState("");
  const [branchFilter, setBranchFilter] = useState("");'''))

edits.append(("fetch branches", '''  useEffect(() => {
    load();
    apiFetch("/api/employees").then(setEmployees).catch(() => {});
  }, []);''',
'''  useEffect(() => {
    load();
    apiFetch("/api/employees").then(setEmployees).catch(() => {});
    apiFetch("/api/branches").then(setBranches).catch(() => {});
  }, []);'''))

edits.append(("displayed con sucursal", '''  const displayed = flags
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
    });''',
'''  const displayed = flags
    .filter((f) => {
      if (filter === "pending") return !f.resolved;
      if (filter === "resolved") return f.resolved;
      return true;
    })
    .filter((f) => {
      if (!branchFilter) return true;
      const emp = employees.find((x) => x.id === f.employee_id);
      return emp && emp.branch_id === branchFilter;
    })
    .filter((f) => {
      const q = searchQuery.trim().toLowerCase();
      if (!q) return true;
      return (
        employeeName(f.employee_id).toLowerCase().includes(q) ||
        ruleLabel(f.rule_code).toLowerCase().includes(q)
      );
    });'''))

edits.append(("dropdown sucursal autocontenido", '''        <input
          type="text"
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          placeholder={t("search_placeholder")}
          className="border border-bk-brown/20 rounded-md px-3 py-1.5 text-sm ml-auto w-56"
        />''',
'''        <select
          value={branchFilter}
          onChange={(e) => setBranchFilter(e.target.value)}
          className="border border-bk-brown/20 rounded-md px-3 py-1.5 text-sm ml-auto sm:w-44"
        >
          <option value="">{t("filter_all_branches")}</option>
          {branches.map((b) => (
            <option key={b.id} value={b.id}>
              {b.name}
            </option>
          ))}
        </select>
        <input
          type="text"
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          placeholder={t("search_placeholder")}
          className="border border-bk-brown/20 rounded-md px-3 py-1.5 text-sm w-56"
        />'''))

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
for marker in ["branchFilter", "filter_all_branches", "setBranches"]:
    if marker not in check:
        problemas.append(f"falta: {marker}")
if problemas:
    print("XXX VERIFICACION FALLO XXX")
    for p in problemas:
        print(" -", p)
    raise SystemExit(1)
print("OK: confianza/page.js verificado correctamente")
PYEOF

# ---------- 3. i18n: filter_all_branches en exceptions_page + confianza ----------
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
    for ns in ("exceptions_page", "confianza"):
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

echo "=== FIN filtro sucursal excepciones+confianza v2 ==="
