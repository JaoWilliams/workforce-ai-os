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
