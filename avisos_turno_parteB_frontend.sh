#!/bin/bash
# ============================================================
# #138 - Avisos de seguimiento al cierre/inicio de turno - PARTE B (frontend)
# Tarjeta resumen en Dashboard + entrada en sidebar (grupo "asistencia",
# junto a Marcacion/Excepciones/Reportes) + pantalla dedicada
# "Avisos de Turno" (busqueda, filtro sucursal, refresh manual - cumple
# el estandar de CLAUDE.md salvo toast/autorefresh que no aplican porque
# esta pantalla no tiene mutaciones, es solo lectura en vivo).
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

# ---------- 1. sidebar: nuevo item en grupo "asistencia" ----------
python3 << 'PYEOF'
path = "apps/frontend/app/[locale]/dashboard/layout.js"
with open(path, encoding="utf-8") as f:
    src = f.read()

old = '''  {
    key: "asistencia",
    icon: Clock,
    items: [
      { key: "attendance", href: "/marcacion", permission: "attendance.view" },
      { key: "exceptions", href: "/excepciones", permission: "exceptions.view" },
      { key: "requests", href: "/solicitudes", permission: null, disabled: true },
      { key: "reports", href: "/reportes", permission: "attendance.view" },
    ],
  },'''
new = '''  {
    key: "asistencia",
    icon: Clock,
    items: [
      { key: "attendance", href: "/marcacion", permission: "attendance.view" },
      { key: "exceptions", href: "/excepciones", permission: "exceptions.view" },
      { key: "requests", href: "/solicitudes", permission: null, disabled: true },
      { key: "reports", href: "/reportes", permission: "attendance.view" },
      { key: "shift_alerts", href: "/avisos-turno", permission: "shifts.view" },
    ],
  },'''

assert old in src, "ANCHOR NOT FOUND: grupo asistencia"
assert src.count(old) == 1, "ANCHOR NOT UNIQUE: grupo asistencia"
src = src.replace(old, new, 1)
with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("OK: layout.js - item shift_alerts agregado al sidebar")
PYEOF

# ---------- 2. dashboard/page.js: KPI + fetch ----------
python3 << 'PYEOF'
path = "apps/frontend/app/[locale]/dashboard/page.js"
with open(path, encoding="utf-8") as f:
    src = f.read()

edits = []

edits.append(("import icono AlarmClock", '''import {
  Users,
  Wifi,
  Clock,
  AlertTriangle,
  ShieldAlert,
  Flame,
  CalendarClock,
  ClipboardList,
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
  AlarmClock,
} from "lucide-react";'''))

edits.append(("state shiftAlerts", '''  const [shiftTemplates, setShiftTemplates] = useState([]);
  const [shiftAssignments, setShiftAssignments] = useState([]);''',
'''  const [shiftTemplates, setShiftTemplates] = useState([]);
  const [shiftAssignments, setShiftAssignments] = useState([]);
  const [shiftAlerts, setShiftAlerts] = useState([]);'''))

edits.append(("fetch + destructure shiftAlerts", '''    Promise.all([
      apiFetch("/api/employees"),
      apiFetch("/api/branches"),
      apiFetch("/api/devices"),
      apiFetch("/api/attendance"),
      apiFetch("/api/exceptions?status=pending"),
      apiFetch("/api/confianza-operativa/flags"),
      apiFetch("/api/shifts"),
      apiFetch("/api/shifts/assignments"),
    ])
      .then(([emp, br, dev, att, exc, fl, st, sa]) => {
        setEmployees(emp);
        setBranches(br);
        setDevices(dev);
        setAttendance(att);
        setPendingExceptions(exc);
        setFlags(fl);
        setShiftTemplates(st);
        setShiftAssignments(sa);
      })''',
'''    Promise.all([
      apiFetch("/api/employees"),
      apiFetch("/api/branches"),
      apiFetch("/api/devices"),
      apiFetch("/api/attendance"),
      apiFetch("/api/exceptions?status=pending"),
      apiFetch("/api/confianza-operativa/flags"),
      apiFetch("/api/shifts"),
      apiFetch("/api/shifts/assignments"),
      apiFetch("/api/shifts/alerts").catch(() => []),
    ])
      .then(([emp, br, dev, att, exc, fl, st, sa, sal]) => {
        setEmployees(emp);
        setBranches(br);
        setDevices(dev);
        setAttendance(att);
        setPendingExceptions(exc);
        setFlags(fl);
        setShiftTemplates(st);
        setShiftAssignments(sa);
        setShiftAlerts(sal);
      })'''))

edits.append(("KPI card avisos de turno", '''    { label: t("stat_onboarding_incomplete"), value: onboardingIncomplete, icon: ClipboardList, color: COLOR_ORANGE },
  ];''',
'''    { label: t("stat_onboarding_incomplete"), value: onboardingIncomplete, icon: ClipboardList, color: COLOR_ORANGE },
    { label: t("stat_shift_alerts"), value: shiftAlerts.length, icon: AlarmClock, color: COLOR_ORANGE },
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
for marker in ["shiftAlerts", "AlarmClock", "stat_shift_alerts"]:
    if marker not in check:
        problemas.append(f"falta: {marker}")
if problemas:
    print("XXX VERIFICACION FALLO XXX")
    for p in problemas:
        print(" -", p)
    raise SystemExit(1)
print("OK: dashboard/page.js verificado correctamente")
PYEOF

# ---------- 3. pantalla nueva: avisos-turno/page.js ----------
mkdir -p "apps/frontend/app/[locale]/dashboard/avisos-turno"
cat > "apps/frontend/app/[locale]/dashboard/avisos-turno/page.js" << 'PYEOF'
"use client";

import { useEffect, useMemo, useState } from "react";
import { useTranslations } from "next-intl";
import { useParams } from "next/navigation";
import { AlarmClock, LogOut, UserX } from "lucide-react";
import { apiFetch } from "../../../../lib/api";
import { LoadingState, EmptyState } from "../../../../lib/ui";

export default function AvisosTurnoPage() {
  const t = useTranslations("shift_alerts");
  const params = useParams();
  const locale = params.locale;

  const [alerts, setAlerts] = useState([]);
  const [branches, setBranches] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [branchFilter, setBranchFilter] = useState("");
  const [typeFilter, setTypeFilter] = useState("");
  const [searchQuery, setSearchQuery] = useState("");

  useEffect(() => {
    load();
    apiFetch("/api/branches").then(setBranches).catch(() => {});
  }, []);

  function load() {
    setLoading(true);
    apiFetch("/api/shifts/alerts")
      .then(setAlerts)
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }

  function branchName(id) {
    const b = branches.find((br) => br.id === id);
    return b ? b.name : id;
  }

  const noShowCount = alerts.filter((a) => a.type === "no_show").length;
  const notClosedCount = alerts.filter((a) => a.type === "not_closed").length;

  const filtered = useMemo(() => {
    const q = searchQuery.trim().toLowerCase();
    return alerts
      .filter((a) => (branchFilter ? a.branch_id === branchFilter : true))
      .filter((a) => (typeFilter ? a.type === typeFilter : true))
      .filter((a) =>
        q
          ? a.employee_name.toLowerCase().includes(q) || a.shift_name.toLowerCase().includes(q)
          : true
      )
      .sort((a, b) => b.minutes_late - a.minutes_late);
  }, [alerts, branchFilter, typeFilter, searchQuery]);

  return (
    <div>
      <div className="flex items-center gap-2 mb-2">
        <AlarmClock size={20} className="text-bk-brown/60" />
        <h1 className="font-heading text-2xl font-extrabold text-bk-brown">{t("title")}</h1>
      </div>
      <p className="text-sm text-bk-brown/60 mb-6">{t("subtitle")}</p>

      {error && (
        <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-4">{error}</p>
      )}

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-6">
        <button
          type="button"
          onClick={() => setTypeFilter("")}
          className={
            "text-left bg-white rounded-xl shadow-sm border p-4 transition " +
            (typeFilter === "" ? "border-bk-orange" : "border-bk-brown/10 hover:border-bk-brown/30")
          }
        >
          <p className="text-2xl font-extrabold text-bk-brown">{alerts.length}</p>
          <p className="text-xs text-bk-brown/60 mt-1">{t("stat_total")}</p>
        </button>
        <button
          type="button"
          onClick={() => setTypeFilter("no_show")}
          className={
            "text-left bg-white rounded-xl shadow-sm border p-4 transition " +
            (typeFilter === "no_show" ? "border-bk-orange" : "border-bk-brown/10 hover:border-bk-brown/30")
          }
        >
          <div className="flex items-center gap-2">
            <UserX size={16} className="text-bk-red" />
            <p className="text-2xl font-extrabold text-bk-brown">{noShowCount}</p>
          </div>
          <p className="text-xs text-bk-brown/60 mt-1">{t("stat_no_show")}</p>
        </button>
        <button
          type="button"
          onClick={() => setTypeFilter("not_closed")}
          className={
            "text-left bg-white rounded-xl shadow-sm border p-4 transition " +
            (typeFilter === "not_closed" ? "border-bk-orange" : "border-bk-brown/10 hover:border-bk-brown/30")
          }
        >
          <div className="flex items-center gap-2">
            <LogOut size={16} className="text-bk-orange" />
            <p className="text-2xl font-extrabold text-bk-brown">{notClosedCount}</p>
          </div>
          <p className="text-xs text-bk-brown/60 mt-1">{t("stat_not_closed")}</p>
        </button>
      </div>

      <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 overflow-hidden">
        <div className="p-3 border-b border-bk-brown/10 flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder={t("search_placeholder")}
              className="border border-bk-brown/20 rounded-md px-3 py-1.5 text-sm"
            />
            <select
              value={branchFilter}
              onChange={(e) => setBranchFilter(e.target.value)}
              className="border border-bk-brown/20 rounded-md px-2 py-1.5 text-sm"
            >
              <option value="">{t("filter_all_branches")}</option>
              {branches.map((b) => (
                <option key={b.id} value={b.id}>
                  {b.name}
                </option>
              ))}
            </select>
          </div>
          <div className="flex items-center gap-3">
            <button
              type="button"
              onClick={load}
              className="text-xs font-semibold text-bk-brown border border-bk-brown/30 rounded-lg px-3 py-1.5"
            >
              {t("refresh")}
            </button>
            <p className="text-xs text-bk-brown/50">
              {filtered.length} {t("results_count")}
            </p>
          </div>
        </div>
        {loading ? (
          <LoadingState />
        ) : filtered.length === 0 ? (
          <EmptyState icon={AlarmClock} message={t("no_alerts")} />
        ) : (
          <table className="w-full text-sm">
            <thead className="bg-bk-cream2 text-left text-xs text-bk-brown/60">
              <tr>
                <th className="px-5 py-3 font-medium">{t("col_employee")}</th>
                <th className="px-5 py-3 font-medium">{t("col_branch")}</th>
                <th className="px-5 py-3 font-medium">{t("col_shift")}</th>
                <th className="px-5 py-3 font-medium">{t("col_type")}</th>
                <th className="px-5 py-3 font-medium">{t("col_minutes_late")}</th>
                <th className="px-5 py-3 font-medium text-right">{t("col_action")}</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-bk-brown/10">
              {filtered.map((a, idx) => (
                <tr key={a.employee_id + "-" + a.type + "-" + idx}>
                  <td className="px-5 py-3 font-semibold text-bk-brown">{a.employee_name}</td>
                  <td className="px-5 py-3 text-bk-brown/70">{branchName(a.branch_id)}</td>
                  <td className="px-5 py-3 text-bk-brown/70">{a.shift_name}</td>
                  <td className="px-5 py-3">
                    <span
                      className={
                        "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold " +
                        (a.type === "no_show" ? "bg-bk-red/10 text-bk-red" : "bg-bk-orange/10 text-bk-orange")
                      }
                    >
                      {a.type === "no_show" ? t("type_no_show") : t("type_not_closed")}
                    </span>
                  </td>
                  <td className="px-5 py-3 text-bk-brown/70">
                    {a.minutes_late} {t("minutes")}
                  </td>
                  <td className="px-5 py-3 text-right">
                    <a
                      href={"/" + locale + "/dashboard/marcacion"}
                      className="text-xs font-semibold text-white rounded-lg px-3 py-1.5 inline-block"
                      style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}
                    >
                      {t("resolve_button")}
                    </a>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
PYEOF
echo "OK: avisos-turno/page.js creado"

# ---------- 4. i18n: nav + dashboard + namespace nuevo shift_alerts ----------
python3 << 'PYEOF'
import json

nuevas_nav_es = {"shift_alerts": "Avisos de Turno"}
nuevas_nav_en = {"shift_alerts": "Shift Alerts"}

nuevas_dashboard_es = {"stat_shift_alerts": "Avisos de turno activos"}
nuevas_dashboard_en = {"stat_shift_alerts": "Active shift alerts"}

nuevas_shift_alerts_es = {
    "title": "Avisos de Turno",
    "subtitle": "Empleados con turno programado que no marcaron entrada o no cerraron la salida — se actualiza en vivo.",
    "stat_total": "Avisos activos",
    "stat_no_show": "Sin marcar entrada",
    "stat_not_closed": "Turno sin cerrar",
    "filter_all_branches": "Todas las sucursales",
    "search_placeholder": "Buscar empleado o turno...",
    "refresh": "Actualizar",
    "results_count": "resultados",
    "no_alerts": "Sin avisos activos en este momento.",
    "col_employee": "Empleado",
    "col_branch": "Sucursal",
    "col_shift": "Turno",
    "col_type": "Tipo",
    "col_minutes_late": "Minutos",
    "col_action": "Acción",
    "type_no_show": "Sin marcar entrada",
    "type_not_closed": "Turno sin cerrar",
    "minutes": "min",
    "resolve_button": "Ir a Marcación",
}
nuevas_shift_alerts_en = {
    "title": "Shift Alerts",
    "subtitle": "Employees with a scheduled shift who did not clock in or did not clock out — updates live.",
    "stat_total": "Active alerts",
    "stat_no_show": "No clock-in",
    "stat_not_closed": "Shift not closed",
    "filter_all_branches": "All branches",
    "search_placeholder": "Search employee or shift...",
    "refresh": "Refresh",
    "results_count": "results",
    "no_alerts": "No active alerts right now.",
    "col_employee": "Employee",
    "col_branch": "Branch",
    "col_shift": "Shift",
    "col_type": "Type",
    "col_minutes_late": "Minutes",
    "col_action": "Action",
    "type_no_show": "No clock-in",
    "type_not_closed": "Shift not closed",
    "minutes": "min",
    "resolve_button": "Go to Attendance",
}

for path, nav_v, dash_v, sa_v in [
    ("apps/frontend/messages/es.json", nuevas_nav_es, nuevas_dashboard_es, nuevas_shift_alerts_es),
    ("apps/frontend/messages/en.json", nuevas_nav_en, nuevas_dashboard_en, nuevas_shift_alerts_en),
]:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    added = 0
    for namespace, values in [("nav", nav_v), ("dashboard", dash_v), ("shift_alerts", sa_v)]:
        data.setdefault(namespace, {})
        for k, v in values.items():
            if k not in data[namespace]:
                data[namespace][k] = v
                added += 1
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"OK: {path} - +{added} claves nuevas")
PYEOF

echo "=== rebuild frontend ==="
docker compose build --no-cache frontend
docker compose up -d frontend
sleep 6
docker compose logs frontend --tail 40

echo "=== FIN avisos de turno - parte B frontend ==="
