#!/bin/bash
# ============================================================
# Pantalla "Catalogos de Nomina": consolida 11 configuraciones que
# ya existian en el backend (Mod. 6/7/8/9 de nomina) sin ninguna UI:
# feriados, tramos de renta, creditos de renta, vacaciones, aguinaldo,
# cesantia (config + tabla), plan de cuentas, archivo bancario,
# anomalias de nomina, avisos de turno. Una sola pantalla con secciones
# (decision tomada con el usuario para no saturar el sidebar).
# 100% frontend - el backend de todos estos catalogos ya existe.
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

# ---------- 1. sidebar: nuevo item en grupo "nomina" ----------
python3 << 'PYEOF'
path = "apps/frontend/app/[locale]/dashboard/layout.js"
with open(path, encoding="utf-8") as f:
    src = f.read()

old = '''  {
    key: "nomina",
    icon: Wallet,
    items: [
      { key: "payroll", href: "/nomina", permission: "payroll.view" },
      { key: "payroll_runs", href: "/nomina/corridas", permission: "payroll.view" },
      { key: "concepts", href: "/nomina/conceptos", permission: "catalogs.view" },
    ],
  },'''
new = '''  {
    key: "nomina",
    icon: Wallet,
    items: [
      { key: "payroll", href: "/nomina", permission: "payroll.view" },
      { key: "payroll_runs", href: "/nomina/corridas", permission: "payroll.view" },
      { key: "concepts", href: "/nomina/conceptos", permission: "catalogs.view" },
      { key: "payroll_catalogs", href: "/nomina/catalogos", permission: "catalogs.view" },
    ],
  },'''

assert old in src, "ANCHOR NOT FOUND: grupo nomina (con concepts)"
assert src.count(old) == 1, "ANCHOR NOT UNIQUE: grupo nomina (con concepts)"
src = src.replace(old, new, 1)
with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("OK: layout.js - item payroll_catalogs agregado al sidebar")
PYEOF

# ---------- 2. pantalla nueva: nomina/catalogos/page.js ----------
mkdir -p "apps/frontend/app/[locale]/dashboard/nomina/catalogos"
cat > "apps/frontend/app/[locale]/dashboard/nomina/catalogos/page.js" << 'PYEOF'
"use client";

import { useEffect, useState } from "react";
import { useTranslations } from "next-intl";
import {
  CalendarDays,
  Landmark,
  Plane,
  Gift,
  Briefcase,
  BookOpen,
  Building2,
  AlertTriangle,
  AlarmClock,
} from "lucide-react";
import { apiFetch } from "../../../../../lib/api";
import { useToast } from "../../../../../lib/toast";
import { usePermissions } from "../../../../../lib/permissions";
import { LoadingState, EmptyState } from "../../../../../lib/ui";

const PAYMENT_TYPES = ["obligatorio", "no_obligatorio"];
const ACCOUNT_TYPES = ["activo", "pasivo", "patrimonio", "ingreso", "gasto"];

const SECTIONS = [
  { key: "holidays", icon: CalendarDays },
  { key: "tax_brackets", icon: Landmark },
  { key: "renta_credits", icon: Landmark },
  { key: "vacation", icon: Plane },
  { key: "aguinaldo", icon: Gift },
  { key: "cesantia_config", icon: Briefcase },
  { key: "cesantia_scale", icon: Briefcase },
  { key: "chart_of_accounts", icon: BookOpen },
  { key: "bank_file", icon: Building2 },
  { key: "anomaly", icon: AlertTriangle },
  { key: "shift_alert", icon: AlarmClock },
];

function Field({ label, children }) {
  return (
    <div>
      <label className="block text-xs font-medium text-bk-brown/70 mb-1">{label}</label>
      {children}
    </div>
  );
}

function SaveButton({ children, disabled }) {
  return (
    <button
      type="submit"
      disabled={disabled}
      className="text-xs font-semibold text-white rounded-lg px-4 py-2 disabled:opacity-50"
      style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}
    >
      {children}
    </button>
  );
}

export default function CatalogosNominaPage() {
  const t = useTranslations("payroll_catalogs");
  const { hasPermission } = usePermissions();
  const { showToast } = useToast();
  const canManage = hasPermission("catalogs.manage");

  const [activeSection, setActiveSection] = useState("holidays");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  // --- feriados ---
  const [holidays, setHolidays] = useState([]);
  const [holidayForm, setHolidayForm] = useState({ date: "", name: "", payment_type: "obligatorio" });
  const [savingHoliday, setSavingHoliday] = useState(false);

  // --- tramos de renta ---
  const [taxBrackets, setTaxBrackets] = useState([]);
  const [bracketForm, setBracketForm] = useState({ year: new Date().getFullYear(), bracket_order: 1, lower_bound: "", upper_bound: "", rate: "" });
  const [savingBracket, setSavingBracket] = useState(false);

  // --- creditos de renta ---
  const [rentaCredits, setRentaCredits] = useState(null);
  const [creditsYear, setCreditsYear] = useState(new Date().getFullYear());
  const [creditsForm, setCreditsForm] = useState({ spouse_credit: "", child_credit: "" });
  const [savingCredits, setSavingCredits] = useState(false);

  // --- vacaciones ---
  const [vacationConfig, setVacationConfig] = useState(null);
  const [vacationForm, setVacationForm] = useState({ cycle_weeks: "" });
  const [savingVacation, setSavingVacation] = useState(false);

  // --- aguinaldo ---
  const [aguinaldoConfig, setAguinaldoConfig] = useState(null);
  const [aguinaldoForm, setAguinaldoForm] = useState({
    period_start_month: 12, period_start_day: 1, period_end_month: 11, period_end_day: 30,
  });
  const [savingAguinaldo, setSavingAguinaldo] = useState(false);

  // --- cesantia config ---
  const [cesantiaConfig, setCesantiaConfig] = useState(null);
  const [cesantiaForm, setCesantiaForm] = useState({
    max_years_cap: 8, fraction_round_months: 6, days_3to6_months: 7,
    days_6to12_months: 14, daily_divisor: 30, months_for_average: 6,
  });
  const [savingCesantia, setSavingCesantia] = useState(false);

  // --- tabla de cesantia ---
  const [cesantiaScale, setCesantiaScale] = useState([]);
  const [savingScale, setSavingScale] = useState(false);

  // --- plan de cuentas ---
  const [chartAccounts, setChartAccounts] = useState([]);
  const [accountForm, setAccountForm] = useState({ code: "", name: "", account_type: "gasto" });
  const [savingAccount, setSavingAccount] = useState(false);

  // --- archivo bancario ---
  const [bankFileConfig, setBankFileConfig] = useState(null);
  const [bankFileForm, setBankFileForm] = useState({ glosa: "" });
  const [savingBankFile, setSavingBankFile] = useState(false);

  // --- anomalias ---
  const [anomalyConfig, setAnomalyConfig] = useState(null);
  const [anomalyForm, setAnomalyForm] = useState({
    net_deviation_pct_threshold: "", overtime_hours_multiplier_threshold: "",
    bank_account_change_window_days: "", branch_net_deviation_pct_threshold: "",
  });
  const [savingAnomaly, setSavingAnomaly] = useState(false);

  // --- avisos de turno ---
  const [shiftAlertConfig, setShiftAlertConfig] = useState(null);
  const [shiftAlertForm, setShiftAlertForm] = useState({ no_show_grace_minutes: 15, not_closed_grace_minutes: 15 });
  const [savingShiftAlert, setSavingShiftAlert] = useState(false);

  useEffect(() => {
    loadAll();
  }, []);

  function loadAll() {
    setLoading(true);
    Promise.all([
      apiFetch("/api/catalogs/holidays").catch(() => []),
      apiFetch("/api/catalogs/tax-brackets").catch(() => []),
      apiFetch("/api/catalogs/renta-credits").catch(() => null),
      apiFetch("/api/catalogs/vacation-config").catch(() => null),
      apiFetch("/api/catalogs/aguinaldo-config").catch(() => null),
      apiFetch("/api/catalogs/cesantia-config").catch(() => null),
      apiFetch("/api/catalogs/cesantia-scale").catch(() => []),
      apiFetch("/api/catalogs/chart-of-accounts").catch(() => []),
      apiFetch("/api/catalogs/bank-file-config").catch(() => null),
      apiFetch("/api/catalogs/payroll-anomaly-config").catch(() => null),
      apiFetch("/api/catalogs/shift-alert-config").catch(() => null),
    ])
      .then(([hol, tb, rc, vc, ac, cc, cs, ca, bf, an, sa]) => {
        setHolidays(hol || []);
        setTaxBrackets(tb || []);
        setRentaCredits(rc);
        if (rc) setCreditsForm({ spouse_credit: rc.spouse_credit, child_credit: rc.child_credit });
        setVacationConfig(vc);
        if (vc) setVacationForm({ cycle_weeks: vc.cycle_weeks });
        setAguinaldoConfig(ac);
        if (ac) setAguinaldoForm(ac);
        setCesantiaConfig(cc);
        if (cc) setCesantiaForm(cc);
        const scale = cs && cs.length > 0 ? cs : Array.from({ length: 8 }, (_, i) => ({ year_number: i + 1, days: 0 }));
        setCesantiaScale(scale);
        setChartAccounts(ca || []);
        setBankFileConfig(bf);
        if (bf) setBankFileForm({ glosa: bf.glosa });
        setAnomalyConfig(an);
        if (an) setAnomalyForm(an);
        setShiftAlertConfig(sa);
        if (sa) setShiftAlertForm(sa);
      })
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }

  async function handleCreateHoliday(e) {
    e.preventDefault();
    setSavingHoliday(true);
    try {
      await apiFetch("/api/catalogs/holidays", { method: "POST", body: JSON.stringify(holidayForm) });
      setHolidayForm({ date: "", name: "", payment_type: "obligatorio" });
      showToast(t("saved_ok"));
      loadAll();
    } catch (err) {
      showToast(err.message, "error");
    } finally {
      setSavingHoliday(false);
    }
  }

  async function handleCreateBracket(e) {
    e.preventDefault();
    setSavingBracket(true);
    try {
      const payload = {
        year: parseInt(bracketForm.year, 10),
        bracket_order: parseInt(bracketForm.bracket_order, 10),
        lower_bound: parseFloat(bracketForm.lower_bound),
        upper_bound: bracketForm.upper_bound !== "" ? parseFloat(bracketForm.upper_bound) : null,
        rate: parseFloat(bracketForm.rate),
      };
      await apiFetch("/api/catalogs/tax-brackets", { method: "POST", body: JSON.stringify(payload) });
      setBracketForm({ year: bracketForm.year, bracket_order: bracketForm.bracket_order + 1, lower_bound: "", upper_bound: "", rate: "" });
      showToast(t("saved_ok"));
      loadAll();
    } catch (err) {
      showToast(err.message, "error");
    } finally {
      setSavingBracket(false);
    }
  }

  async function handleSaveCredits(e) {
    e.preventDefault();
    setSavingCredits(true);
    try {
      const payload = {
        spouse_credit: parseFloat(creditsForm.spouse_credit),
        child_credit: parseFloat(creditsForm.child_credit),
      };
      await apiFetch("/api/catalogs/renta-credits/" + creditsYear, { method: "PUT", body: JSON.stringify(payload) });
      showToast(t("saved_ok"));
      loadAll();
    } catch (err) {
      showToast(err.message, "error");
    } finally {
      setSavingCredits(false);
    }
  }

  async function handleSaveVacation(e) {
    e.preventDefault();
    setSavingVacation(true);
    try {
      await apiFetch("/api/catalogs/vacation-config", {
        method: "PUT",
        body: JSON.stringify({ cycle_weeks: parseFloat(vacationForm.cycle_weeks) }),
      });
      showToast(t("saved_ok"));
      loadAll();
    } catch (err) {
      showToast(err.message, "error");
    } finally {
      setSavingVacation(false);
    }
  }

  async function handleSaveAguinaldo(e) {
    e.preventDefault();
    setSavingAguinaldo(true);
    try {
      const payload = {
        period_start_month: parseInt(aguinaldoForm.period_start_month, 10),
        period_start_day: parseInt(aguinaldoForm.period_start_day, 10),
        period_end_month: parseInt(aguinaldoForm.period_end_month, 10),
        period_end_day: parseInt(aguinaldoForm.period_end_day, 10),
      };
      await apiFetch("/api/catalogs/aguinaldo-config", { method: "PUT", body: JSON.stringify(payload) });
      showToast(t("saved_ok"));
      loadAll();
    } catch (err) {
      showToast(err.message, "error");
    } finally {
      setSavingAguinaldo(false);
    }
  }

  async function handleSaveCesantiaConfig(e) {
    e.preventDefault();
    setSavingCesantia(true);
    try {
      const payload = {
        max_years_cap: parseInt(cesantiaForm.max_years_cap, 10),
        fraction_round_months: parseInt(cesantiaForm.fraction_round_months, 10),
        days_3to6_months: parseFloat(cesantiaForm.days_3to6_months),
        days_6to12_months: parseFloat(cesantiaForm.days_6to12_months),
        daily_divisor: parseFloat(cesantiaForm.daily_divisor),
        months_for_average: parseInt(cesantiaForm.months_for_average, 10),
      };
      await apiFetch("/api/catalogs/cesantia-config", { method: "PUT", body: JSON.stringify(payload) });
      showToast(t("saved_ok"));
      loadAll();
    } catch (err) {
      showToast(err.message, "error");
    } finally {
      setSavingCesantia(false);
    }
  }

  function updateScaleRow(year_number, days) {
    setCesantiaScale((rows) => rows.map((r) => (r.year_number === year_number ? { ...r, days } : r)));
  }

  async function handleSaveScale() {
    setSavingScale(true);
    try {
      const payload = {
        rows: cesantiaScale.map((r) => ({ year_number: r.year_number, days: parseFloat(r.days) || 0 })),
      };
      await apiFetch("/api/catalogs/cesantia-scale", { method: "PUT", body: JSON.stringify(payload) });
      showToast(t("saved_ok"));
      loadAll();
    } catch (err) {
      showToast(err.message, "error");
    } finally {
      setSavingScale(false);
    }
  }

  async function handleCreateAccount(e) {
    e.preventDefault();
    setSavingAccount(true);
    try {
      await apiFetch("/api/catalogs/chart-of-accounts", { method: "POST", body: JSON.stringify(accountForm) });
      setAccountForm({ code: "", name: "", account_type: "gasto" });
      showToast(t("saved_ok"));
      loadAll();
    } catch (err) {
      showToast(err.message, "error");
    } finally {
      setSavingAccount(false);
    }
  }

  async function handleSaveBankFile(e) {
    e.preventDefault();
    setSavingBankFile(true);
    try {
      await apiFetch("/api/catalogs/bank-file-config", { method: "PUT", body: JSON.stringify(bankFileForm) });
      showToast(t("saved_ok"));
      loadAll();
    } catch (err) {
      showToast(err.message, "error");
    } finally {
      setSavingBankFile(false);
    }
  }

  async function handleSaveAnomaly(e) {
    e.preventDefault();
    setSavingAnomaly(true);
    try {
      const payload = {
        net_deviation_pct_threshold: parseFloat(anomalyForm.net_deviation_pct_threshold),
        overtime_hours_multiplier_threshold: parseFloat(anomalyForm.overtime_hours_multiplier_threshold),
        bank_account_change_window_days: parseInt(anomalyForm.bank_account_change_window_days, 10),
        branch_net_deviation_pct_threshold: parseFloat(anomalyForm.branch_net_deviation_pct_threshold),
      };
      await apiFetch("/api/catalogs/payroll-anomaly-config", { method: "PUT", body: JSON.stringify(payload) });
      showToast(t("saved_ok"));
      loadAll();
    } catch (err) {
      showToast(err.message, "error");
    } finally {
      setSavingAnomaly(false);
    }
  }

  async function handleSaveShiftAlert(e) {
    e.preventDefault();
    setSavingShiftAlert(true);
    try {
      const payload = {
        no_show_grace_minutes: parseInt(shiftAlertForm.no_show_grace_minutes, 10),
        not_closed_grace_minutes: parseInt(shiftAlertForm.not_closed_grace_minutes, 10),
      };
      await apiFetch("/api/catalogs/shift-alert-config", { method: "PUT", body: JSON.stringify(payload) });
      showToast(t("saved_ok"));
      loadAll();
    } catch (err) {
      showToast(err.message, "error");
    } finally {
      setSavingShiftAlert(false);
    }
  }

  function renderSection() {
    if (activeSection === "holidays") {
      return (
        <div className="space-y-6">
          <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 overflow-hidden">
            {holidays.length === 0 ? (
              <EmptyState icon={CalendarDays} message={t("no_holidays")} />
            ) : (
              <ul className="divide-y divide-bk-brown/10">
                {holidays.map((h) => (
                  <li key={h.id} className="px-5 py-3 flex items-center justify-between">
                    <div>
                      <p className="font-semibold text-bk-brown text-sm">{h.name}</p>
                      <p className="text-xs text-bk-brown/60">{h.date}</p>
                    </div>
                    <span className="inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-bk-brown/10 text-bk-brown/70">
                      {t("payment_type_" + h.payment_type)}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </div>
          {canManage && (
            <form onSubmit={handleCreateHoliday} className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 space-y-3 text-sm">
              <h3 className="font-heading font-bold text-bk-brown">{t("new_holiday")}</h3>
              <div className="grid grid-cols-2 gap-3">
                <Field label={t("date")}>
                  <input required type="date" value={holidayForm.date} onChange={(e) => setHolidayForm({ ...holidayForm, date: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5" />
                </Field>
                <Field label={t("name")}>
                  <input required value={holidayForm.name} onChange={(e) => setHolidayForm({ ...holidayForm, name: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5" />
                </Field>
              </div>
              <Field label={t("payment_type")}>
                <select value={holidayForm.payment_type} onChange={(e) => setHolidayForm({ ...holidayForm, payment_type: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5">
                  {PAYMENT_TYPES.map((p) => (
                    <option key={p} value={p}>{t("payment_type_" + p)}</option>
                  ))}
                </select>
              </Field>
              <SaveButton disabled={savingHoliday}>{t("create")}</SaveButton>
            </form>
          )}
        </div>
      );
    }

    if (activeSection === "tax_brackets") {
      return (
        <div className="space-y-6">
          <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 overflow-hidden">
            {taxBrackets.length === 0 ? (
              <EmptyState icon={Landmark} message={t("no_brackets")} />
            ) : (
              <table className="w-full text-sm">
                <thead className="bg-bk-cream2 text-left text-xs text-bk-brown/60">
                  <tr>
                    <th className="px-4 py-2 font-medium">{t("year")}</th>
                    <th className="px-4 py-2 font-medium">{t("bracket_order")}</th>
                    <th className="px-4 py-2 font-medium">{t("lower_bound")}</th>
                    <th className="px-4 py-2 font-medium">{t("upper_bound")}</th>
                    <th className="px-4 py-2 font-medium">{t("rate")}</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-bk-brown/10">
                  {taxBrackets.map((b) => (
                    <tr key={b.id}>
                      <td className="px-4 py-2">{b.year}</td>
                      <td className="px-4 py-2">{b.bracket_order}</td>
                      <td className="px-4 py-2">{b.lower_bound}</td>
                      <td className="px-4 py-2">{b.upper_bound != null ? b.upper_bound : "∞"}</td>
                      <td className="px-4 py-2">{(b.rate * 100).toFixed(2)}%</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
          {canManage && (
            <form onSubmit={handleCreateBracket} className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 space-y-3 text-sm">
              <h3 className="font-heading font-bold text-bk-brown">{t("new_bracket")}</h3>
              <div className="grid grid-cols-2 gap-3">
                <Field label={t("year")}>
                  <input required type="number" value={bracketForm.year} onChange={(e) => setBracketForm({ ...bracketForm, year: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5" />
                </Field>
                <Field label={t("bracket_order")}>
                  <input required type="number" value={bracketForm.bracket_order} onChange={(e) => setBracketForm({ ...bracketForm, bracket_order: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5" />
                </Field>
                <Field label={t("lower_bound")}>
                  <input required type="number" step="0.01" value={bracketForm.lower_bound} onChange={(e) => setBracketForm({ ...bracketForm, lower_bound: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5" />
                </Field>
                <Field label={t("upper_bound")}>
                  <input type="number" step="0.01" value={bracketForm.upper_bound} onChange={(e) => setBracketForm({ ...bracketForm, upper_bound: e.target.value })} placeholder={t("upper_bound_hint")} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5" />
                </Field>
                <Field label={t("rate")}>
                  <input required type="number" step="0.0001" value={bracketForm.rate} onChange={(e) => setBracketForm({ ...bracketForm, rate: e.target.value })} placeholder="0.10" className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5" />
                </Field>
              </div>
              <SaveButton disabled={savingBracket}>{t("create")}</SaveButton>
            </form>
          )}
        </div>
      );
    }

    if (activeSection === "renta_credits") {
      return (
        <form onSubmit={handleSaveCredits} className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 space-y-3 text-sm max-w-md">
          <h3 className="font-heading font-bold text-bk-brown">{t("renta_credits_title")}</h3>
          <Field label={t("year")}>
            <input type="number" value={creditsYear} onChange={(e) => setCreditsYear(e.target.value)} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5" />
          </Field>
          <Field label={t("spouse_credit")}>
            <input required type="number" step="0.01" value={creditsForm.spouse_credit} onChange={(e) => setCreditsForm({ ...creditsForm, spouse_credit: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5" />
          </Field>
          <Field label={t("child_credit")}>
            <input required type="number" step="0.01" value={creditsForm.child_credit} onChange={(e) => setCreditsForm({ ...creditsForm, child_credit: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5" />
          </Field>
          {canManage && <SaveButton disabled={savingCredits}>{t("save_changes")}</SaveButton>}
        </form>
      );
    }

    if (activeSection === "vacation") {
      return (
        <form onSubmit={handleSaveVacation} className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 space-y-3 text-sm max-w-md">
          <h3 className="font-heading font-bold text-bk-brown">{t("vacation_title")}</h3>
          <Field label={t("cycle_weeks")}>
            <input required type="number" step="0.1" value={vacationForm.cycle_weeks} onChange={(e) => setVacationForm({ cycle_weeks: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5" />
          </Field>
          <p className="text-xs text-bk-brown/50">{t("vacation_hint")}</p>
          {canManage && <SaveButton disabled={savingVacation}>{t("save_changes")}</SaveButton>}
        </form>
      );
    }

    if (activeSection === "aguinaldo") {
      return (
        <form onSubmit={handleSaveAguinaldo} className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 space-y-3 text-sm max-w-md">
          <h3 className="font-heading font-bold text-bk-brown">{t("aguinaldo_title")}</h3>
          <div className="grid grid-cols-2 gap-3">
            <Field label={t("period_start_month")}>
              <input required type="number" min="1" max="12" value={aguinaldoForm.period_start_month} onChange={(e) => setAguinaldoForm({ ...aguinaldoForm, period_start_month: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5" />
            </Field>
            <Field label={t("period_start_day")}>
              <input required type="number" min="1" max="31" value={aguinaldoForm.period_start_day} onChange={(e) => setAguinaldoForm({ ...aguinaldoForm, period_start_day: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5" />
            </Field>
            <Field label={t("period_end_month")}>
              <input required type="number" min="1" max="12" value={aguinaldoForm.period_end_month} onChange={(e) => setAguinaldoForm({ ...aguinaldoForm, period_end_month: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5" />
            </Field>
            <Field label={t("period_end_day")}>
              <input required type="number" min="1" max="31" value={aguinaldoForm.period_end_day} onChange={(e) => setAguinaldoForm({ ...aguinaldoForm, period_end_day: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5" />
            </Field>
          </div>
          <p className="text-xs text-bk-brown/50">{t("aguinaldo_hint")}</p>
          {canManage && <SaveButton disabled={savingAguinaldo}>{t("save_changes")}</SaveButton>}
        </form>
      );
    }

    if (activeSection === "cesantia_config") {
      return (
        <form onSubmit={handleSaveCesantiaConfig} className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 space-y-3 text-sm max-w-md">
          <h3 className="font-heading font-bold text-bk-brown">{t("cesantia_config_title")}</h3>
          <div className="grid grid-cols-2 gap-3">
            <Field label={t("max_years_cap")}>
              <input required type="number" value={cesantiaForm.max_years_cap} onChange={(e) => setCesantiaForm({ ...cesantiaForm, max_years_cap: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5" />
            </Field>
            <Field label={t("fraction_round_months")}>
              <input required type="number" value={cesantiaForm.fraction_round_months} onChange={(e) => setCesantiaForm({ ...cesantiaForm, fraction_round_months: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5" />
            </Field>
            <Field label={t("days_3to6_months")}>
              <input required type="number" step="0.1" value={cesantiaForm.days_3to6_months} onChange={(e) => setCesantiaForm({ ...cesantiaForm, days_3to6_months: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5" />
            </Field>
            <Field label={t("days_6to12_months")}>
              <input required type="number" step="0.1" value={cesantiaForm.days_6to12_months} onChange={(e) => setCesantiaForm({ ...cesantiaForm, days_6to12_months: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5" />
            </Field>
            <Field label={t("daily_divisor")}>
              <input required type="number" step="0.1" value={cesantiaForm.daily_divisor} onChange={(e) => setCesantiaForm({ ...cesantiaForm, daily_divisor: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5" />
            </Field>
            <Field label={t("months_for_average")}>
              <input required type="number" value={cesantiaForm.months_for_average} onChange={(e) => setCesantiaForm({ ...cesantiaForm, months_for_average: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5" />
            </Field>
          </div>
          {canManage && <SaveButton disabled={savingCesantia}>{t("save_changes")}</SaveButton>}
        </form>
      );
    }

    if (activeSection === "cesantia_scale") {
      return (
        <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 max-w-md">
          <h3 className="font-heading font-bold text-bk-brown mb-1">{t("cesantia_scale_title")}</h3>
          <p className="text-xs text-bk-brown/50 mb-4">{t("cesantia_scale_hint")}</p>
          <div className="space-y-2">
            {cesantiaScale.map((row) => (
              <div key={row.year_number} className="flex items-center gap-3 text-sm">
                <span className="w-24 text-bk-brown/70">{t("year_number_label")} {row.year_number}</span>
                <input
                  type="number"
                  step="0.01"
                  disabled={!canManage}
                  value={row.days}
                  onChange={(e) => updateScaleRow(row.year_number, e.target.value)}
                  className="w-28 border border-bk-brown/20 rounded-md px-2 py-1.5"
                />
                <span className="text-xs text-bk-brown/50">{t("days_label")}</span>
              </div>
            ))}
          </div>
          {canManage && (
            <button
              type="button"
              onClick={handleSaveScale}
              disabled={savingScale}
              className="mt-4 text-xs font-semibold text-white rounded-lg px-4 py-2 disabled:opacity-50"
              style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}
            >
              {t("save_changes")}
            </button>
          )}
        </div>
      );
    }

    if (activeSection === "chart_of_accounts") {
      return (
        <div className="space-y-6">
          <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 overflow-hidden">
            {chartAccounts.length === 0 ? (
              <EmptyState icon={BookOpen} message={t("no_accounts")} />
            ) : (
              <ul className="divide-y divide-bk-brown/10">
                {chartAccounts.map((a) => (
                  <li key={a.id} className="px-5 py-3 flex items-center justify-between">
                    <div>
                      <p className="font-semibold text-bk-brown text-sm">{a.code} · {a.name}</p>
                    </div>
                    <span className="inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-bk-brown/10 text-bk-brown/70">
                      {t("account_type_" + a.account_type)}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </div>
          {canManage && (
            <form onSubmit={handleCreateAccount} className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 space-y-3 text-sm">
              <h3 className="font-heading font-bold text-bk-brown">{t("new_account")}</h3>
              <div className="grid grid-cols-3 gap-3">
                <Field label={t("code")}>
                  <input required value={accountForm.code} onChange={(e) => setAccountForm({ ...accountForm, code: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5" />
                </Field>
                <Field label={t("name")}>
                  <input required value={accountForm.name} onChange={(e) => setAccountForm({ ...accountForm, name: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5" />
                </Field>
                <Field label={t("account_type")}>
                  <select value={accountForm.account_type} onChange={(e) => setAccountForm({ ...accountForm, account_type: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5">
                    {ACCOUNT_TYPES.map((a) => (
                      <option key={a} value={a}>{t("account_type_" + a)}</option>
                    ))}
                  </select>
                </Field>
              </div>
              <SaveButton disabled={savingAccount}>{t("create")}</SaveButton>
            </form>
          )}
        </div>
      );
    }

    if (activeSection === "bank_file") {
      return (
        <form onSubmit={handleSaveBankFile} className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 space-y-3 text-sm max-w-md">
          <h3 className="font-heading font-bold text-bk-brown">{t("bank_file_title")}</h3>
          <Field label={t("glosa")}>
            <input required value={bankFileForm.glosa} onChange={(e) => setBankFileForm({ glosa: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5" />
          </Field>
          {canManage && <SaveButton disabled={savingBankFile}>{t("save_changes")}</SaveButton>}
        </form>
      );
    }

    if (activeSection === "anomaly") {
      return (
        <form onSubmit={handleSaveAnomaly} className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 space-y-3 text-sm max-w-md">
          <h3 className="font-heading font-bold text-bk-brown">{t("anomaly_title")}</h3>
          <Field label={t("net_deviation_pct_threshold")}>
            <input required type="number" step="0.01" value={anomalyForm.net_deviation_pct_threshold} onChange={(e) => setAnomalyForm({ ...anomalyForm, net_deviation_pct_threshold: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5" />
          </Field>
          <Field label={t("overtime_hours_multiplier_threshold")}>
            <input required type="number" step="0.01" value={anomalyForm.overtime_hours_multiplier_threshold} onChange={(e) => setAnomalyForm({ ...anomalyForm, overtime_hours_multiplier_threshold: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5" />
          </Field>
          <Field label={t("bank_account_change_window_days")}>
            <input required type="number" value={anomalyForm.bank_account_change_window_days} onChange={(e) => setAnomalyForm({ ...anomalyForm, bank_account_change_window_days: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5" />
          </Field>
          <Field label={t("branch_net_deviation_pct_threshold")}>
            <input required type="number" step="0.01" value={anomalyForm.branch_net_deviation_pct_threshold} onChange={(e) => setAnomalyForm({ ...anomalyForm, branch_net_deviation_pct_threshold: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5" />
          </Field>
          {canManage && <SaveButton disabled={savingAnomaly}>{t("save_changes")}</SaveButton>}
        </form>
      );
    }

    if (activeSection === "shift_alert") {
      return (
        <form onSubmit={handleSaveShiftAlert} className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 space-y-3 text-sm max-w-md">
          <h3 className="font-heading font-bold text-bk-brown">{t("shift_alert_title")}</h3>
          <Field label={t("no_show_grace_minutes")}>
            <input required type="number" value={shiftAlertForm.no_show_grace_minutes} onChange={(e) => setShiftAlertForm({ ...shiftAlertForm, no_show_grace_minutes: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5" />
          </Field>
          <Field label={t("not_closed_grace_minutes")}>
            <input required type="number" value={shiftAlertForm.not_closed_grace_minutes} onChange={(e) => setShiftAlertForm({ ...shiftAlertForm, not_closed_grace_minutes: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5" />
          </Field>
          {canManage && <SaveButton disabled={savingShiftAlert}>{t("save_changes")}</SaveButton>}
        </form>
      );
    }

    return null;
  }

  return (
    <div>
      <h1 className="font-heading text-2xl font-extrabold text-bk-brown mb-2">{t("title")}</h1>
      <p className="text-sm text-bk-brown/60 mb-6">{t("subtitle")}</p>

      {error && (
        <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-4">{error}</p>
      )}

      {loading ? (
        <LoadingState />
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
          <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 overflow-hidden h-fit">
            <ul className="divide-y divide-bk-brown/10">
              {SECTIONS.map((s) => {
                const Icon = s.icon;
                return (
                  <li key={s.key}>
                    <button
                      type="button"
                      onClick={() => setActiveSection(s.key)}
                      className={
                        "w-full text-left px-4 py-3 text-sm flex items-center gap-2 transition " +
                        (activeSection === s.key ? "bg-bk-orange/10 text-bk-brown font-semibold" : "text-bk-brown/70 hover:bg-bk-cream2")
                      }
                    >
                      <Icon size={15} />
                      {t("section_" + s.key)}
                    </button>
                  </li>
                );
              })}
            </ul>
          </div>
          <div className="md:col-span-3">{renderSection()}</div>
        </div>
      )}
    </div>
  );
}
PYEOF
echo "OK: nomina/catalogos/page.js creado"

# ---------- 3. i18n: nav.payroll_catalogs + namespace payroll_catalogs ----------
python3 << 'PYEOF'
import json

nuevas_nav_es = {"payroll_catalogs": "Catálogos de Nómina"}
nuevas_nav_en = {"payroll_catalogs": "Payroll Catalogs"}

nuevas_pc_es = {
    "title": "Catálogos de Nómina",
    "subtitle": "Todos los insumos que alimentan el cálculo de nómina y la generación del asiento contable, en un solo lugar.",
    "saved_ok": "Guardado correctamente",
    "create": "Crear",
    "save_changes": "Guardar cambios",
    "section_holidays": "Feriados",
    "section_tax_brackets": "Tramos de renta",
    "section_renta_credits": "Créditos de renta",
    "section_vacation": "Vacaciones",
    "section_aguinaldo": "Aguinaldo",
    "section_cesantia_config": "Cesantía",
    "section_cesantia_scale": "Tabla de cesantía",
    "section_chart_of_accounts": "Plan de cuentas",
    "section_bank_file": "Archivo bancario",
    "section_anomaly": "Anomalías de nómina",
    "section_shift_alert": "Avisos de turno",
    "no_holidays": "Sin feriados cargados todavía.",
    "new_holiday": "Nuevo feriado",
    "date": "Fecha",
    "name": "Nombre",
    "payment_type": "Tipo de pago",
    "payment_type_obligatorio": "Obligatorio",
    "payment_type_no_obligatorio": "No obligatorio",
    "no_brackets": "Sin tramos de renta cargados todavía.",
    "new_bracket": "Nuevo tramo",
    "year": "Año",
    "bracket_order": "Orden del tramo",
    "lower_bound": "Límite inferior",
    "upper_bound": "Límite superior",
    "upper_bound_hint": "Vacío = sin límite (último tramo)",
    "rate": "Tasa",
    "renta_credits_title": "Créditos de renta por año",
    "spouse_credit": "Crédito por cónyuge",
    "child_credit": "Crédito por hijo",
    "vacation_title": "Configuración de vacaciones",
    "cycle_weeks": "Semanas del ciclo",
    "vacation_hint": "2 semanas de derecho por cada este número de semanas trabajadas (Art. 153/155 Código de Trabajo).",
    "aguinaldo_title": "Ventana del período de aguinaldo",
    "period_start_month": "Mes de inicio",
    "period_start_day": "Día de inicio",
    "period_end_month": "Mes de fin",
    "period_end_day": "Día de fin",
    "aguinaldo_hint": "Ventana legal: diciembre del año anterior a noviembre del año actual.",
    "cesantia_config_title": "Configuración de cesantía",
    "max_years_cap": "Tope de años (Art. 29)",
    "fraction_round_months": "Meses para redondear fracción de año",
    "days_3to6_months": "Días fijos (3 a 6 meses)",
    "days_6to12_months": "Días fijos (6 a 12 meses)",
    "daily_divisor": "Divisor para salario diario",
    "months_for_average": "Meses para promedio salarial",
    "cesantia_scale_title": "Tabla acumulativa de cesantía (Art. 29)",
    "cesantia_scale_hint": "Días de cesantía por cada año completo trabajado, según la tabla oficial.",
    "year_number_label": "Año",
    "days_label": "días",
    "no_accounts": "Sin cuentas contables cargadas todavía.",
    "new_account": "Nueva cuenta",
    "code": "Código",
    "account_type": "Tipo de cuenta",
    "account_type_activo": "Activo",
    "account_type_pasivo": "Pasivo",
    "account_type_patrimonio": "Patrimonio",
    "account_type_ingreso": "Ingreso",
    "account_type_gasto": "Gasto",
    "bank_file_title": "Glosa del archivo bancario",
    "glosa": "Glosa",
    "anomaly_title": "Umbrales de anomalías de nómina",
    "net_deviation_pct_threshold": "Desviación de neto (%)",
    "overtime_hours_multiplier_threshold": "Multiplicador de horas extra",
    "bank_account_change_window_days": "Ventana de cambio de cuenta bancaria (días)",
    "branch_net_deviation_pct_threshold": "Desviación de neto por sucursal (%)",
    "shift_alert_title": "Minutos de gracia de avisos de turno",
    "no_show_grace_minutes": "Minutos antes de marcar 'sin entrada'",
    "not_closed_grace_minutes": "Minutos antes de marcar 'turno sin cerrar'",
}
nuevas_pc_en = {
    "title": "Payroll Catalogs",
    "subtitle": "Every input that feeds payroll calculation and the accounting entry generation, in one place.",
    "saved_ok": "Saved successfully",
    "create": "Create",
    "save_changes": "Save changes",
    "section_holidays": "Holidays",
    "section_tax_brackets": "Tax brackets",
    "section_renta_credits": "Tax credits",
    "section_vacation": "Vacations",
    "section_aguinaldo": "Bonus (aguinaldo)",
    "section_cesantia_config": "Severance",
    "section_cesantia_scale": "Severance scale",
    "section_chart_of_accounts": "Chart of accounts",
    "section_bank_file": "Bank file",
    "section_anomaly": "Payroll anomalies",
    "section_shift_alert": "Shift alerts",
    "no_holidays": "No holidays loaded yet.",
    "new_holiday": "New holiday",
    "date": "Date",
    "name": "Name",
    "payment_type": "Payment type",
    "payment_type_obligatorio": "Mandatory",
    "payment_type_no_obligatorio": "Non-mandatory",
    "no_brackets": "No tax brackets loaded yet.",
    "new_bracket": "New bracket",
    "year": "Year",
    "bracket_order": "Bracket order",
    "lower_bound": "Lower bound",
    "upper_bound": "Upper bound",
    "upper_bound_hint": "Empty = no upper limit (last bracket)",
    "rate": "Rate",
    "renta_credits_title": "Tax credits by year",
    "spouse_credit": "Spouse credit",
    "child_credit": "Child credit",
    "vacation_title": "Vacation configuration",
    "cycle_weeks": "Cycle weeks",
    "vacation_hint": "2 weeks of entitlement per this many weeks worked (Labor Code Art. 153/155).",
    "aguinaldo_title": "Bonus period window",
    "period_start_month": "Start month",
    "period_start_day": "Start day",
    "period_end_month": "End month",
    "period_end_day": "End day",
    "aguinaldo_hint": "Legal window: December of the previous year through November of the current year.",
    "cesantia_config_title": "Severance configuration",
    "max_years_cap": "Years cap (Art. 29)",
    "fraction_round_months": "Months to round up a year fraction",
    "days_3to6_months": "Fixed days (3 to 6 months)",
    "days_6to12_months": "Fixed days (6 to 12 months)",
    "daily_divisor": "Divisor for daily wage",
    "months_for_average": "Months for wage average",
    "cesantia_scale_title": "Severance cumulative scale (Art. 29)",
    "cesantia_scale_hint": "Severance days per full year worked, per the official scale.",
    "year_number_label": "Year",
    "days_label": "days",
    "no_accounts": "No accounts loaded yet.",
    "new_account": "New account",
    "code": "Code",
    "account_type": "Account type",
    "account_type_activo": "Asset",
    "account_type_pasivo": "Liability",
    "account_type_patrimonio": "Equity",
    "account_type_ingreso": "Income",
    "account_type_gasto": "Expense",
    "bank_file_title": "Bank file description",
    "glosa": "Description",
    "anomaly_title": "Payroll anomaly thresholds",
    "net_deviation_pct_threshold": "Net deviation (%)",
    "overtime_hours_multiplier_threshold": "Overtime multiplier",
    "bank_account_change_window_days": "Bank account change window (days)",
    "branch_net_deviation_pct_threshold": "Branch net deviation (%)",
    "shift_alert_title": "Shift alert grace minutes",
    "no_show_grace_minutes": "Minutes before marking 'no clock-in'",
    "not_closed_grace_minutes": "Minutes before marking 'shift not closed'",
}

for path, nav_v, pc_v in [
    ("apps/frontend/messages/es.json", nuevas_nav_es, nuevas_pc_es),
    ("apps/frontend/messages/en.json", nuevas_nav_en, nuevas_pc_en),
]:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    added = 0
    data.setdefault("nav", {})
    for k, v in nav_v.items():
        if k not in data["nav"]:
            data["nav"][k] = v
            added += 1
    data.setdefault("payroll_catalogs", {})
    for k, v in pc_v.items():
        if k not in data["payroll_catalogs"]:
            data["payroll_catalogs"][k] = v
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

echo "=== FIN catalogos de nomina ==="
