#!/bin/bash
# ============================================================
# Onboarding incompleto - Parte B (v2): frontend
# v2: anchors de una sola linea donde antes asumia lineas adyacentes
# sin blanco entre medio (eso rompio v1 en PAY_FREQUENCIES/emptyForm).
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

edits.append(("BANK_ACCOUNT_TYPES const", '''const PAY_FREQUENCIES = ["semanal", "quincenal", "bisemanal", "mensual"];''',
'''const PAY_FREQUENCIES = ["semanal", "quincenal", "bisemanal", "mensual"];
const BANK_ACCOUNT_TYPES = ["Cuenta de Ahorro", "Cuenta Corriente"];'''))

edits.append(("checkingOnboarding state", '''  const [contractError, setContractError] = useState(null);''',
'''  const [contractError, setContractError] = useState(null);
  const [checkingOnboarding, setCheckingOnboarding] = useState(false);'''))

edits.append(("selectEmployee editForm init", '''    setEditForm({
      email: emp.email || "",
      phone: emp.phone || "",
      position: emp.position,
      active: emp.active,
    });''',
'''    setEditForm({
      email: emp.email || "",
      phone: emp.phone || "",
      position: emp.position,
      active: emp.active,
      bank_account_type: emp.bank_account_type || "",
      bank_account_number: emp.bank_account_number || "",
    });'''))

edits.append(("handleUpdateEmployee payload", '''      const payload = {
        email: editForm.email || null,
        phone: editForm.phone || null,
        position: editForm.position,
        active: editForm.active,
      };''',
'''      const payload = {
        email: editForm.email || null,
        phone: editForm.phone || null,
        position: editForm.position,
        active: editForm.active,
        bank_account_type: editForm.bank_account_type || null,
        bank_account_number: editForm.bank_account_number || null,
      };'''))

edits.append(("handleOnboardingCheck fn + return", '''  return (
    <div>''',
'''  async function handleOnboardingCheck() {
    setCheckingOnboarding(true);
    try {
      const result = await apiFetch("/api/employees/onboarding-check", { method: "POST" });
      showToast(t("onboarding_check_ok_toast", { checked: result.checked, with_gaps: result.with_gaps }));
      loadEmployees();
    } catch (err) {
      showToast(err.message, "error");
    } finally {
      setCheckingOnboarding(false);
    }
  }
  return (
    <div>'''))

edits.append(("titulo + boton verificar onboarding", '''      <h1 className="font-heading text-2xl font-extrabold text-bk-brown mb-6">
        {t("title")}
      </h1>''',
'''      <div className="flex items-center justify-between mb-6">
        <h1 className="font-heading text-2xl font-extrabold text-bk-brown">
          {t("title")}
        </h1>
        {hasPermission("employees.manage") && (
          <button
            onClick={handleOnboardingCheck}
            disabled={checkingOnboarding}
            className="text-xs font-semibold text-bk-brown border border-bk-brown/20 rounded-lg px-3 py-1.5 hover:bg-bk-cream2 disabled:opacity-50"
          >
            {checkingOnboarding ? "..." : t("onboarding_check_button")}
          </button>
        )}
      </div>'''))

edits.append(("badge onboarding en lista", '''                    <p className="text-xs mt-1">
                      <span
                        className={
                          emp.active
                            ? "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-green-100 text-green-700"
                            : "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-bk-brown/10 text-bk-brown/60"
                        }
                      >
                        {emp.active ? t("active") : t("inactive")}
                      </span>
                    </p>''',
'''                    <p className="text-xs mt-1">
                      <span
                        className={
                          emp.active
                            ? "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-green-100 text-green-700"
                            : "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-bk-brown/10 text-bk-brown/60"
                        }
                      >
                        {emp.active ? t("active") : t("inactive")}
                      </span>
                      {emp.onboarding_missing && emp.onboarding_missing.length > 0 && (
                        <span className="inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-orange-100 text-orange-700 ml-1">
                          {t("onboarding_incomplete")} ({emp.onboarding_missing.length})
                        </span>
                      )}
                    </p>'''))

edits.append(("warning box en panel detalle", '''                <h2 className="font-heading font-bold text-bk-brown mb-4">
                  {t("edit_employee")} — {selected.first_name} {selected.last_name}
                </h2>''',
'''                <h2 className="font-heading font-bold text-bk-brown mb-4">
                  {t("edit_employee")} — {selected.first_name} {selected.last_name}
                </h2>
                {selected.onboarding_missing && selected.onboarding_missing.length > 0 && (
                  <div className="bg-orange-50 border border-orange-200 rounded-lg px-4 py-3 mb-4">
                    <p className="text-xs font-semibold text-orange-700 mb-1">{t("onboarding_incomplete")}</p>
                    <ul className="text-xs text-orange-700 list-disc list-inside">
                      {selected.onboarding_missing.map((m) => (
                        <li key={m}>{t("onboarding_missing_" + m)}</li>
                      ))}
                    </ul>
                  </div>
                )}'''))

edits.append(("campos cuenta bancaria en form edicion", '''                  <div>
                    <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("position")}</label>
                    <input
                      required
                      value={editForm.position}
                      onChange={(e) => setEditForm({ ...editForm, position: e.target.value })}
                      className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                    />
                  </div>''',
'''                  <div>
                    <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("position")}</label>
                    <input
                      required
                      value={editForm.position}
                      onChange={(e) => setEditForm({ ...editForm, position: e.target.value })}
                      className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                    />
                  </div>
                  <div className="grid grid-cols-2 gap-3">
                    <div>
                      <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("bank_account_type")}</label>
                      <select
                        value={editForm.bank_account_type}
                        onChange={(e) => setEditForm({ ...editForm, bank_account_type: e.target.value })}
                        className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                      >
                        <option value="">{t("select_bank_account_type")}</option>
                        {BANK_ACCOUNT_TYPES.map((bt) => (
                          <option key={bt} value={bt}>
                            {bt}
                          </option>
                        ))}
                      </select>
                    </div>
                    <div>
                      <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("bank_account_number")}</label>
                      <input
                        value={editForm.bank_account_number}
                        onChange={(e) => setEditForm({ ...editForm, bank_account_number: e.target.value })}
                        className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                      />
                    </div>
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
for marker in ["BANK_ACCOUNT_TYPES", "handleOnboardingCheck", "onboarding_incomplete", "bank_account_type"]:
    if marker not in check:
        problemas.append(f"falta: {marker}")
if problemas:
    print("XXX VERIFICACION FALLO XXX")
    for p in problemas:
        print(" -", p)
    raise SystemExit(1)
print("OK: empleados/page.js verificado correctamente")
PYEOF

# ---------- 2. dashboard page.js (Inicio) ----------
python3 << 'PYEOF'
path = "apps/frontend/app/[locale]/dashboard/page.js"
with open(path, encoding="utf-8") as f:
    src = f.read()

edits = []

edits.append(("import ClipboardList", '''import {
  Users,
  Wifi,
  Clock,
  AlertTriangle,
  ShieldAlert,
  Flame,
  CalendarClock,
} from "lucide-react";''',
'''import {
  Users,
  Wifi,
  Clock,
  AlertTriangle,
  ShieldAlert,
  Flame,
  CalendarClock,
  ClipboardList,
} from "lucide-react";'''))

edits.append(("onboardingIncomplete calc", '''  const flagsHigh = flags.filter((f) => !f.resolved && f.severity === "high").length;''',
'''  const flagsHigh = flags.filter((f) => !f.resolved && f.severity === "high").length;
  const onboardingIncomplete = employees.filter(
    (e) => e.active && e.onboarding_missing && e.onboarding_missing.length > 0
  ).length;'''))

edits.append(("7ma tarjeta KPI onboarding", '''    { label: t("stat_flags_high"), value: flagsHigh, icon: Flame, color: COLOR_RED },
  ];''',
'''    { label: t("stat_flags_high"), value: flagsHigh, icon: Flame, color: COLOR_RED },
    { label: t("stat_onboarding_incomplete"), value: onboardingIncomplete, icon: ClipboardList, color: COLOR_ORANGE },
  ];'''))

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
for marker in ["ClipboardList", "onboardingIncomplete", "stat_onboarding_incomplete"]:
    if marker not in check:
        problemas.append(f"falta: {marker}")
if problemas:
    print("XXX VERIFICACION FALLO XXX")
    for p in problemas:
        print(" -", p)
    raise SystemExit(1)
print("OK: dashboard page.js verificado correctamente")
PYEOF

# ---------- 3. i18n: employees + dashboard ----------
python3 << 'PYEOF'
import json

employees_es = {
    "onboarding_incomplete": "Onboarding incompleto",
    "onboarding_missing_bank_account": "Falta cuenta bancaria",
    "onboarding_missing_contract": "Falta contrato",
    "onboarding_missing_biometric": "Falta enrolamiento biométrico",
    "bank_account_type": "Tipo de cuenta bancaria",
    "bank_account_number": "Número de cuenta bancaria",
    "select_bank_account_type": "Seleccionar tipo de cuenta",
    "onboarding_check_button": "Verificar onboarding",
    "onboarding_check_ok_toast": "Verificación completa: {checked} empleados revisados, {with_gaps} con onboarding incompleto",
}
employees_en = {
    "onboarding_incomplete": "Incomplete onboarding",
    "onboarding_missing_bank_account": "Missing bank account",
    "onboarding_missing_contract": "Missing contract",
    "onboarding_missing_biometric": "Missing biometric enrollment",
    "bank_account_type": "Bank account type",
    "bank_account_number": "Bank account number",
    "select_bank_account_type": "Select account type",
    "onboarding_check_button": "Check onboarding",
    "onboarding_check_ok_toast": "Check complete: {checked} employees checked, {with_gaps} with incomplete onboarding",
}
dashboard_es = {"stat_onboarding_incomplete": "Onboarding incompleto"}
dashboard_en = {"stat_onboarding_incomplete": "Incomplete onboarding"}

for path, emp_vals, dash_vals in [
    ("apps/frontend/messages/es.json", employees_es, dashboard_es),
    ("apps/frontend/messages/en.json", employees_en, dashboard_en),
]:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    data.setdefault("employees", {})
    added = 0
    for k, v in emp_vals.items():
        if k not in data["employees"]:
            data["employees"][k] = v
            added += 1
    print(f"OK: {path} - employees +{added}")
    data.setdefault("dashboard", {})
    added2 = 0
    for k, v in dash_vals.items():
        if k not in data["dashboard"]:
            data["dashboard"][k] = v
            added2 += 1
    print(f"OK: {path} - dashboard +{added2}")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
PYEOF

# ---------- 4. rebuild frontend ----------
echo "=== rebuild frontend ==="
docker compose build --no-cache frontend
docker compose up -d frontend
sleep 5
docker compose logs frontend --tail 30

echo "=== FIN Parte B v2 (frontend) ==="
