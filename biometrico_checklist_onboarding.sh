#!/bin/bash
# ============================================================
# #102 - Biometrico: rediseñar enrolamiento como checklist de
# onboarding (no pantalla libre). Reutiliza onboarding_missing
# (ya existente) para mostrar por defecto solo empleados pendientes
# de biometrico, con filtro de sucursal (estandar), toggle "ver
# todos" para re-enrolar en dispositivo nuevo, barra de progreso,
# y auto-desaparicion del checklist al enrolar exitosamente.
# Ademas conecta el deep-link desde Centro de Onboarding: si lo
# unico que falta es biometrico, "Resolver" manda a Dispositivos
# en vez de Empleados.
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

# ---------- 1. dispositivos/page.js ----------
python3 << 'PYEOF'
path = "apps/frontend/app/[locale]/dashboard/dispositivos/page.js"
with open(path, encoding="utf-8") as f:
    src = f.read()

edits = []

edits.append(("import icono CheckCircle2", '''import { Router, Fingerprint } from "lucide-react";''',
'''import { Router, Fingerprint, CheckCircle2 } from "lucide-react";'''))

edits.append(("import useSearchParams", '''import { usePermissions } from "../../../../lib/permissions";''',
'''import { usePermissions } from "../../../../lib/permissions";
import { useSearchParams } from "next/navigation";'''))

edits.append(("nuevos states checklist", '''  const [bioError, setBioError] = useState(null);''',
'''  const [bioError, setBioError] = useState(null);
  const [branchFilter, setBranchFilter] = useState("");
  const [showAllEmployees, setShowAllEmployees] = useState(false);
  const searchParams = useSearchParams();'''))

edits.append(("loadDevices + loadEmployees", '''  function loadDevices() {
    setDevicesLoading(true);
    apiFetch("/api/devices")
      .then(setDevices)
      .catch((err) => setDevicesError(err.message))
      .finally(() => setDevicesLoading(false));
  }''',
'''  function loadDevices() {
    setDevicesLoading(true);
    apiFetch("/api/devices")
      .then(setDevices)
      .catch((err) => setDevicesError(err.message))
      .finally(() => setDevicesLoading(false));
  }

  function loadEmployees() {
    return apiFetch("/api/employees").then(setEmployees).catch(() => {});
  }'''))

edits.append(("effect mount + effect highlight", '''  useEffect(() => {
    loadDevices();
    apiFetch("/api/branches").then(setBranches).catch(() => {});
    apiFetch("/api/employees").then(setEmployees).catch(() => {});
  }, []);''',
'''  useEffect(() => {
    loadDevices();
    apiFetch("/api/branches").then(setBranches).catch(() => {});
    loadEmployees();
  }, []);

  useEffect(() => {
    const hi = searchParams.get("highlight");
    if (hi && employees.length > 0 && !selectedEmployee) {
      const emp = employees.find((e) => e.id === hi);
      if (emp) selectEmployee(emp);
    }
  }, [searchParams, employees]);'''))

edits.append(("computados checklist biometrico", '''  const filteredDevices = devices.filter((d) => {
    const q = searchQuery.trim().toLowerCase();
    if (!q) return true;
    return (
      d.brand.toLowerCase().includes(q) ||
      d.model.toLowerCase().includes(q) ||
      d.serial_number.toLowerCase().includes(q) ||
      branchName(d.branch_id).toLowerCase().includes(q)
    );
  });''',
'''  const filteredDevices = devices.filter((d) => {
    const q = searchQuery.trim().toLowerCase();
    if (!q) return true;
    return (
      d.brand.toLowerCase().includes(q) ||
      d.model.toLowerCase().includes(q) ||
      d.serial_number.toLowerCase().includes(q) ||
      branchName(d.branch_id).toLowerCase().includes(q)
    );
  });

  const activeEmployees = employees.filter((e) => e.active);
  const branchFilteredEmployees = activeEmployees.filter(
    (e) => !branchFilter || e.branch_id === branchFilter
  );
  const pendingBioEmployees = branchFilteredEmployees.filter(
    (e) => e.onboarding_missing && e.onboarding_missing.includes("biometric")
  );
  const bioChecklist = showAllEmployees ? branchFilteredEmployees : pendingBioEmployees;
  const bioTotal = branchFilteredEmployees.length;
  const bioPending = pendingBioEmployees.length;'''))

edits.append(("handleEnroll refetch + auto-desaparicion", '''  async function handleEnroll(e) {
    e.preventDefault();
    if (!selectedEmployee || !enrollDeviceId) return;
    setEnrolling(true);
    setBioError(null);
    try {
      await apiFetch("/api/employees/" + selectedEmployee.id + "/biometric-enrollments", {
        method: "POST",
        body: JSON.stringify({ device_id: enrollDeviceId, biometric_type: enrollType }),
      });
      showToast(tb("enroll_ok"));
      const data = await apiFetch("/api/employees/" + selectedEmployee.id + "/biometric-enrollments");
      setEnrollments(data);
    } catch (err) {
      setBioError(err.message);
      showToast(err.message, "error");
    } finally {
      setEnrolling(false);
    }
  }''',
'''  async function handleEnroll(e) {
    e.preventDefault();
    if (!selectedEmployee || !enrollDeviceId) return;
    setEnrolling(true);
    setBioError(null);
    try {
      await apiFetch("/api/employees/" + selectedEmployee.id + "/biometric-enrollments", {
        method: "POST",
        body: JSON.stringify({ device_id: enrollDeviceId, biometric_type: enrollType }),
      });
      showToast(tb("enroll_ok"));
      const data = await apiFetch("/api/employees/" + selectedEmployee.id + "/biometric-enrollments");
      setEnrollments(data);
      await loadEmployees();
      if (!showAllEmployees) {
        setSelectedEmployee(null);
        setEnrollments([]);
      }
    } catch (err) {
      setBioError(err.message);
      showToast(err.message, "error");
    } finally {
      setEnrolling(false);
    }
  }'''))

edits.append(("JSX checklist biometrico", '''      <div className="flex items-center gap-2 mb-6">
        <Fingerprint size={20} className="text-bk-brown/60" />
        <h1 className="font-heading text-2xl font-extrabold text-bk-brown">{tb("title")}</h1>
      </div>
      {bioError && (
        <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-4">{bioError}</p>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 overflow-hidden">
          {employees.length === 0 ? (
            <LoadingState compact />
          ) : (
            <ul className="divide-y divide-bk-brown/10">
              {employees.map((emp) => (
                <li key={emp.id}>
                  <button
                    onClick={() => selectEmployee(emp)}
                    className={
                      selectedEmployee && selectedEmployee.id === emp.id
                        ? "w-full text-left px-5 py-4 transition bg-bk-orange/10"
                        : "w-full text-left px-5 py-4 transition hover:bg-bk-cream2"
                    }
                  >
                    <p className="font-semibold text-bk-brown">
                      {emp.first_name} {emp.last_name}
                    </p>
                    <p className="text-xs text-bk-brown/60 mt-0.5">{emp.position}</p>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>''',
'''      <div className="flex items-center justify-between mb-2 flex-wrap gap-3">
        <div className="flex items-center gap-2">
          <Fingerprint size={20} className="text-bk-brown/60" />
          <h1 className="font-heading text-2xl font-extrabold text-bk-brown">{tb("title")}</h1>
        </div>
        <div className="flex items-center gap-3">
          <select
            value={branchFilter}
            onChange={(e) => setBranchFilter(e.target.value)}
            className="border border-bk-brown/20 rounded-md px-2 py-1.5 text-xs"
          >
            <option value="">{tb("filter_all_branches")}</option>
            {branches.map((b) => (
              <option key={b.id} value={b.id}>
                {b.name}
              </option>
            ))}
          </select>
          <button
            type="button"
            onClick={() => setShowAllEmployees((v) => !v)}
            className="text-xs font-semibold text-bk-brown border border-bk-brown/30 rounded-lg px-3 py-1.5"
          >
            {showAllEmployees ? tb("show_pending_only") : tb("show_all_employees")}
          </button>
        </div>
      </div>
      <p className="text-sm text-bk-brown/60 mb-2">
        {tb("checklist_pending_prefix")} <strong className="text-bk-brown">{bioPending}</strong> {tb("checklist_of")} {bioTotal}
      </p>
      <div className="w-full h-1.5 bg-bk-brown/10 rounded-full overflow-hidden mb-6">
        <div
          className="h-full bg-green-500 transition-all"
          style={{ width: (bioTotal > 0 ? ((bioTotal - bioPending) / bioTotal) * 100 : 0) + "%" }}
        />
      </div>
      {bioError && (
        <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-4">{bioError}</p>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 overflow-hidden">
          {employees.length === 0 ? (
            <LoadingState compact />
          ) : bioChecklist.length === 0 ? (
            <EmptyState icon={CheckCircle2} message={tb("all_enrolled")} />
          ) : (
            <ul className="divide-y divide-bk-brown/10">
              {bioChecklist.map((emp) => {
                const isPending = emp.onboarding_missing && emp.onboarding_missing.includes("biometric");
                return (
                  <li key={emp.id}>
                    <button
                      onClick={() => selectEmployee(emp)}
                      className={
                        (selectedEmployee && selectedEmployee.id === emp.id
                          ? "w-full text-left px-5 py-4 transition bg-bk-orange/10 "
                          : "w-full text-left px-5 py-4 transition hover:bg-bk-cream2 ") +
                        "flex items-center justify-between gap-2"
                      }
                    >
                      <div>
                        <p className="font-semibold text-bk-brown">
                          {emp.first_name} {emp.last_name}
                        </p>
                        <p className="text-xs text-bk-brown/60 mt-0.5">{emp.position}</p>
                      </div>
                      {isPending ? (
                        <span className="inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-bk-orange/10 text-bk-orange shrink-0">
                          {tb("pending_badge")}
                        </span>
                      ) : (
                        <CheckCircle2 size={16} className="text-green-600 shrink-0" />
                      )}
                    </button>
                  </li>
                );
              })}
            </ul>
          )}
        </div>'''))

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
for marker in ["bioChecklist", "loadEmployees", "CheckCircle2", "useSearchParams", "branchFilter"]:
    if marker not in check:
        problemas.append(f"falta: {marker}")
if problemas:
    print("XXX VERIFICACION FALLO XXX")
    for p in problemas:
        print(" -", p)
    raise SystemExit(1)
print("OK: dispositivos/page.js verificado correctamente")
PYEOF

# ---------- 2. onboarding/page.js: resolveHref (biometrico -> Dispositivos) ----------
python3 << 'PYEOF'
path = "apps/frontend/app/[locale]/dashboard/onboarding/page.js"
with open(path, encoding="utf-8") as f:
    src = f.read()

edits = []

edits.append(("nueva funcion resolveHref", '''  function missingLabel(type) {''',
'''  function resolveHref(emp) {
    const missing = emp.onboarding_missing || [];
    if (missing.includes("bank_account") || missing.includes("contract")) {
      return "/" + locale + "/dashboard/empleados?highlight=" + emp.id;
    }
    return "/" + locale + "/dashboard/dispositivos?highlight=" + emp.id;
  }

  function missingLabel(type) {'''))

edits.append(("boton resolver usa resolveHref", '''                          <a
                            href={"/" + locale + "/dashboard/empleados?highlight=" + e.id}
                            className="text-xs font-semibold text-white rounded-lg px-3 py-1.5 inline-block"
                            style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}
                          >
                            {t("resolve_button")}
                          </a>''',
'''                          <a
                            href={resolveHref(e)}
                            className="text-xs font-semibold text-white rounded-lg px-3 py-1.5 inline-block"
                            style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}
                          >
                            {t("resolve_button")}
                          </a>'''))

for label, old, new in edits:
    assert old in src, f"ANCHOR NOT FOUND ({label})"
    assert src.count(old) == 1, f"ANCHOR NOT UNIQUE ({label})"
    src = src.replace(old, new, 1)
    print(f"OK edicion aplicada (onboarding): {label}")

with open(path, "w", encoding="utf-8") as f:
    f.write(src)

with open(path, encoding="utf-8") as f:
    check = f.read()
problemas = []
if check.count("{") != check.count("}"):
    problemas.append(f"llaves desbalanceadas: {{ {check.count('{')} vs }} {check.count('}')}")
if check.count("(") != check.count(")"):
    problemas.append(f"parentesis desbalanceados: ( {check.count('(')} vs ) {check.count(')')}")
if "resolveHref" not in check:
    problemas.append("falta: resolveHref")
if problemas:
    print("XXX VERIFICACION FALLO XXX")
    for p in problemas:
        print(" -", p)
    raise SystemExit(1)
print("OK: onboarding/page.js verificado correctamente")
PYEOF

# ---------- 3. i18n: biometrics.* nuevas claves ----------
python3 << 'PYEOF'
import json

nuevas_es = {
    "filter_all_branches": "Todas las sucursales",
    "show_pending_only": "Ver solo pendientes",
    "show_all_employees": "Ver todos los empleados",
    "checklist_pending_prefix": "Pendientes de enrolamiento biométrico:",
    "checklist_of": "de",
    "pending_badge": "Pendiente",
    "all_enrolled": "Todos los empleados de esta selección ya tienen biométrico enrolado.",
}
nuevas_en = {
    "filter_all_branches": "All branches",
    "show_pending_only": "Show pending only",
    "show_all_employees": "Show all employees",
    "checklist_pending_prefix": "Pending biometric enrollment:",
    "checklist_of": "of",
    "pending_badge": "Pending",
    "all_enrolled": "Every employee in this selection already has biometric enrollment.",
}

for path, nuevas in [
    ("apps/frontend/messages/es.json", nuevas_es),
    ("apps/frontend/messages/en.json", nuevas_en),
]:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    data.setdefault("biometrics", {})
    added = 0
    for k, v in nuevas.items():
        if k not in data["biometrics"]:
            data["biometrics"][k] = v
            added += 1
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"OK: {path} - biometrics +{added}")
PYEOF

echo "=== rebuild frontend ==="
docker compose build --no-cache frontend
docker compose up -d frontend
sleep 5
docker compose logs frontend --tail 30

echo "=== FIN biometrico checklist onboarding ==="
