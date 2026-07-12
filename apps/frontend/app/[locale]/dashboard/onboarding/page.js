"use client";
import { useEffect, useMemo, useState } from "react";
import { useTranslations } from "next-intl";
import { usePathname } from "next/navigation";
import {
  ResponsiveContainer,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
} from "recharts";
import { AlertTriangle } from "lucide-react";
import { apiFetch } from "../../../../lib/api";

const COLOR_ORANGE = "#FF8732";
const COLOR_RED = "#F5233B";
const COLOR_BROWN = "#502314";
const COLOR_CREAM2 = "#EDE6D6";

const GAP_TYPES = ["bank_account", "contract", "biometric"];

export default function OnboardingCenterPage() {
  const t = useTranslations("onboarding_center");
  const pathname = usePathname();
  const locale = pathname.split("/")[1];

  const [employees, setEmployees] = useState([]);
  const [branches, setBranches] = useState([]);
  const [periods, setPeriods] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [branchFilter, setBranchFilter] = useState("");
  const [typeFilter, setTypeFilter] = useState("");

  useEffect(() => {
    setLoading(true);
    Promise.all([
      apiFetch("/api/employees"),
      apiFetch("/api/branches"),
      apiFetch("/api/payroll/periods").catch(() => []),
    ])
      .then(([emp, br, pe]) => {
        setEmployees(emp);
        setBranches(br);
        setPeriods(pe);
      })
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, []);

  function branchName(id) {
    const b = branches.find((x) => x.id === id);
    return b ? b.name : id;
  }

  function gapDays(emp) {
    if (!emp.hire_date) return 0;
    const hired = new Date(emp.hire_date);
    const now = new Date();
    return Math.max(0, Math.floor((now - hired) / 86400000));
  }

  function gapSeverity(days) {
    if (days > 30) return "high";
    if (days >= 7) return "medium";
    return "low";
  }

  function resolveHref(emp) {
    const missing = emp.onboarding_missing || [];
    if (missing.includes("bank_account") || missing.includes("contract")) {
      return "/" + locale + "/dashboard/empleados?highlight=" + emp.id;
    }
    return "/" + locale + "/dashboard/dispositivos?highlight=" + emp.id;
  }

  function missingLabel(type) {
    const key = "missing_" + type;
    const translated = t(key);
    return translated === key ? type : translated;
  }

  const incompleteEmployees = useMemo(
    () => employees.filter((e) => e.active && e.onboarding_missing && e.onboarding_missing.length > 0),
    [employees]
  );

  const summary = useMemo(() => {
    const counts = { bank_account: 0, contract: 0, biometric: 0 };
    incompleteEmployees.forEach((e) => {
      e.onboarding_missing.forEach((m) => {
        if (counts[m] !== undefined) counts[m] += 1;
      });
    });
    return counts;
  }, [incompleteEmployees]);

  const openPeriod = periods.find((p) => p.status !== "archivo_bancario");
  const bankGapEmployees = incompleteEmployees.filter((e) => e.onboarding_missing.includes("bank_account"));

  const gapsByBranch = useMemo(() => {
    const counts = {};
    incompleteEmployees.forEach((e) => {
      counts[e.branch_id] = (counts[e.branch_id] || 0) + 1;
    });
    return Object.entries(counts)
      .map(([branchId, count]) => ({ name: branchName(branchId), count }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 12);
  }, [incompleteEmployees, branches]);

  const filteredEmployees = useMemo(() => {
    return incompleteEmployees
      .filter((e) => (branchFilter ? e.branch_id === branchFilter : true))
      .filter((e) => (typeFilter ? e.onboarding_missing.includes(typeFilter) : true))
      .map((e) => ({ ...e, _gapDays: gapDays(e) }))
      .sort((a, b) => b._gapDays - a._gapDays);
  }, [incompleteEmployees, branchFilter, typeFilter]);

  return (
    <div>
      <h1 className="font-heading text-2xl font-extrabold text-bk-brown mb-2">{t("title")}</h1>
      <p className="text-bk-brown/70 max-w-2xl leading-relaxed mb-6">{t("subtitle")}</p>
      {error && (
        <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-4">{error}</p>
      )}
      {loading ? (
        <p className="text-sm text-bk-brown/60">...</p>
      ) : (
        <>
          {openPeriod && bankGapEmployees.length > 0 && (
            <div className="flex items-start gap-3 bg-bk-red/10 border border-bk-red/20 rounded-xl px-5 py-4 mb-6">
              <AlertTriangle size={20} color={COLOR_RED} className="mt-0.5 flex-shrink-0" />
              <p className="text-sm text-bk-red font-medium">
                {t("payroll_alert", { count: bankGapEmployees.length })}
              </p>
            </div>
          )}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
            <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5">
              <p className="font-heading text-3xl font-extrabold text-bk-brown">{incompleteEmployees.length}</p>
              <p className="text-xs text-bk-brown/60 mt-1">{t("stat_total")}</p>
            </div>
            <button
              onClick={() => setTypeFilter(typeFilter === "bank_account" ? "" : "bank_account")}
              className={
                "text-left bg-white rounded-xl shadow-sm border p-5 transition " +
                (typeFilter === "bank_account"
                  ? "border-bk-orange ring-2 ring-bk-orange/30"
                  : "border-bk-brown/10 hover:border-bk-orange/40")
              }
            >
              <p className="font-heading text-3xl font-extrabold" style={{ color: COLOR_ORANGE }}>
                {summary.bank_account}
              </p>
              <p className="text-xs text-bk-brown/60 mt-1">{t("stat_bank_account")}</p>
            </button>
            <button
              onClick={() => setTypeFilter(typeFilter === "contract" ? "" : "contract")}
              className={
                "text-left bg-white rounded-xl shadow-sm border p-5 transition " +
                (typeFilter === "contract"
                  ? "border-bk-orange ring-2 ring-bk-orange/30"
                  : "border-bk-brown/10 hover:border-bk-orange/40")
              }
            >
              <p className="font-heading text-3xl font-extrabold" style={{ color: COLOR_ORANGE }}>
                {summary.contract}
              </p>
              <p className="text-xs text-bk-brown/60 mt-1">{t("stat_contract")}</p>
            </button>
            <button
              onClick={() => setTypeFilter(typeFilter === "biometric" ? "" : "biometric")}
              className={
                "text-left bg-white rounded-xl shadow-sm border p-5 transition " +
                (typeFilter === "biometric"
                  ? "border-bk-orange ring-2 ring-bk-orange/30"
                  : "border-bk-brown/10 hover:border-bk-orange/40")
              }
            >
              <p className="font-heading text-3xl font-extrabold" style={{ color: COLOR_ORANGE }}>
                {summary.biometric}
              </p>
              <p className="text-xs text-bk-brown/60 mt-1">{t("stat_biometric")}</p>
            </button>
          </div>
          {gapsByBranch.length > 0 && (
            <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 mb-6">
              <h2 className="font-heading font-bold text-bk-brown mb-4 text-sm">{t("chart_by_branch")}</h2>
              <ResponsiveContainer width="100%" height={Math.max(180, gapsByBranch.length * 28)}>
                <BarChart data={gapsByBranch} layout="vertical" margin={{ left: 20 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke={COLOR_CREAM2} />
                  <XAxis type="number" allowDecimals={false} tick={{ fontSize: 11, fill: COLOR_BROWN }} />
                  <YAxis type="category" dataKey="name" tick={{ fontSize: 11, fill: COLOR_BROWN }} width={140} />
                  <Tooltip />
                  <Bar dataKey="count" fill={COLOR_ORANGE} radius={[0, 4, 4, 0]} />
                </BarChart>
              </ResponsiveContainer>
            </div>
          )}
          <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 overflow-hidden">
            <div className="p-4 border-b border-bk-brown/10 flex flex-wrap items-center gap-3">
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
              <select
                value={typeFilter}
                onChange={(e) => setTypeFilter(e.target.value)}
                className="border border-bk-brown/20 rounded-md px-2 py-1.5 text-sm"
              >
                <option value="">{t("filter_all_types")}</option>
                {GAP_TYPES.map((gt) => (
                  <option key={gt} value={gt}>
                    {missingLabel(gt)}
                  </option>
                ))}
              </select>
              <span className="text-xs text-bk-brown/50 ml-auto">
                {t("results_count", { count: filteredEmployees.length })}
              </span>
            </div>
            {filteredEmployees.length === 0 ? (
              <p className="p-6 text-sm text-bk-brown/60">{t("no_gaps")}</p>
            ) : (
              <table className="w-full text-sm">
                <thead>
                  <tr className="text-left text-xs text-bk-brown/50 border-b border-bk-brown/10">
                    <th className="px-5 py-3 font-medium">{t("col_employee")}</th>
                    <th className="px-5 py-3 font-medium">{t("col_branch")}</th>
                    <th className="px-5 py-3 font-medium">{t("col_gap_days")}</th>
                    <th className="px-5 py-3 font-medium">{t("col_missing")}</th>
                    <th className="px-5 py-3 font-medium"></th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-bk-brown/10">
                  {filteredEmployees.map((e) => {
                    const severity = gapSeverity(e._gapDays);
                    return (
                      <tr key={e.id}>
                        <td className="px-5 py-3 font-medium text-bk-brown">
                          {e.first_name} {e.last_name}
                        </td>
                        <td className="px-5 py-3 text-bk-brown/70">{branchName(e.branch_id)}</td>
                        <td className="px-5 py-3">
                          <span
                            className={
                              "inline-block rounded-full px-2 py-0.5 text-[11px] font-semibold " +
                              (severity === "high"
                                ? "bg-bk-red/10 text-bk-red"
                                : severity === "medium"
                                ? "bg-bk-orange/10 text-bk-orange"
                                : "bg-green-100 text-green-700")
                            }
                          >
                            {e._gapDays} {t("days")}
                          </span>
                        </td>
                        <td className="px-5 py-3">
                          <div className="flex flex-wrap gap-1">
                            {e.onboarding_missing.map((m) => (
                              <span
                                key={m}
                                className="inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-bk-brown/10 text-bk-brown/70"
                              >
                                {missingLabel(m)}
                              </span>
                            ))}
                          </div>
                        </td>
                        <td className="px-5 py-3 text-right">
                          <a
                            href={resolveHref(e)}
                            className="text-xs font-semibold text-white rounded-lg px-3 py-1.5 inline-block"
                            style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}
                          >
                            {t("resolve_button")}
                          </a>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            )}
          </div>
        </>
      )}
    </div>
  );
}
