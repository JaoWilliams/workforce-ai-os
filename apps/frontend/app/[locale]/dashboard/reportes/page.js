"use client";

import { Fragment, useEffect, useState } from "react";
import { useTranslations } from "next-intl";
import { ChevronDown, ChevronRight, FileSpreadsheet, FileText } from "lucide-react";
import { apiFetch, apiFetchBlob } from "../../../../lib/api";
import { useToast } from "../../../../lib/toast";
import { LoadingState, EmptyState } from "../../../../lib/ui";

function defaultStartDate() {
  const d = new Date();
  d.setDate(d.getDate() - 30);
  return d.toISOString().slice(0, 10);
}
function defaultEndDate() {
  return new Date().toISOString().slice(0, 10);
}

export default function ReportesPage() {
  const t = useTranslations("reports");
  const { showToast } = useToast();

  const [branches, setBranches] = useState([]);
  const [rows, setRows] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const [startDate, setStartDate] = useState(defaultStartDate());
  const [endDate, setEndDate] = useState(defaultEndDate());
  const [branchId, setBranchId] = useState("");
  const [searchQuery, setSearchQuery] = useState("");
  const [groupBy, setGroupBy] = useState("employee");
  const [exporting, setExporting] = useState(null);
  const [expandedBranches, setExpandedBranches] = useState(new Set());

  useEffect(() => {
    apiFetch("/api/branches").then(setBranches).catch(() => {});
  }, []);

  useEffect(() => {
    loadReport();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [startDate, endDate, branchId]);

  function buildQuery() {
    let q = `start_date=${startDate}&end_date=${endDate}`;
    if (branchId) q += `&branch_id=${branchId}`;
    return q;
  }

  function loadReport() {
    if (!startDate || !endDate) return;
    setLoading(true);
    setError(null);
    apiFetch("/api/attendance/report?" + buildQuery())
      .then(setRows)
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }

  const filteredEmployeeRows = rows.filter((r) => {
    const q = searchQuery.trim().toLowerCase();
    if (!q) return true;
    return r.employee_name.toLowerCase().includes(q) || r.branch_name.toLowerCase().includes(q);
  });

  function aggregateByBranch(list) {
    const map = {};
    for (const r of list) {
      if (!map[r.branch_id]) {
        map[r.branch_id] = {
          branch_id: r.branch_id,
          branch_name: r.branch_name,
          branch_accounting_account: r.branch_accounting_account,
          employee_count: 0,
          total_days: 0,
          total_hours: 0,
        };
      }
      map[r.branch_id].employee_count += 1;
      map[r.branch_id].total_days += r.days_worked;
      map[r.branch_id].total_hours += r.total_hours;
    }
    return Object.values(map)
      .map((b) => ({ ...b, total_hours: Math.round(b.total_hours * 100) / 100 }))
      .sort((a, b) => a.branch_name.localeCompare(b.branch_name));
  }

  function toggleBranch(branchId) {
    setExpandedBranches((prev) => {
      const next = new Set(prev);
      if (next.has(branchId)) next.delete(branchId);
      else next.add(branchId);
      return next;
    });
  }

  const branchRows = aggregateByBranch(filteredEmployeeRows);
  const totalHoursEmployee = filteredEmployeeRows.reduce((sum, r) => sum + r.total_hours, 0);
  const totalHoursBranch = branchRows.reduce((sum, r) => sum + r.total_hours, 0);

  async function handleExport(format) {
    setExporting(format);
    try {
      const blob = await apiFetchBlob(`/api/attendance/report/export-${format}?` + buildQuery());
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `reporte_horas_${startDate}_${endDate}.${format === "xlsx" ? "xlsx" : "pdf"}`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      window.URL.revokeObjectURL(url);
      showToast(t("export_ok_toast"));
    } catch (err) {
      showToast(err.message, "error");
    } finally {
      setExporting(null);
    }
  }

  return (
    <div>
      <h1 className="font-heading text-2xl font-extrabold text-bk-brown mb-6">{t("title")}</h1>

      <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 mb-6">
        <div className="grid grid-cols-1 md:grid-cols-5 gap-3 items-end">
          <div>
            <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("start_date")}</label>
            <input
              type="date"
              value={startDate}
              onChange={(e) => setStartDate(e.target.value)}
              className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5 text-sm"
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("end_date")}</label>
            <input
              type="date"
              value={endDate}
              onChange={(e) => setEndDate(e.target.value)}
              className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5 text-sm"
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("branch")}</label>
            <select
              value={branchId}
              onChange={(e) => setBranchId(e.target.value)}
              className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5 text-sm"
            >
              <option value="">{t("all_branches")}</option>
              {branches.map((b) => (
                <option key={b.id} value={b.id}>
                  {b.name}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("group_by_label")}</label>
            <div className="flex gap-1">
              <button
                type="button"
                onClick={() => setGroupBy("employee")}
                className={
                  groupBy === "employee"
                    ? "flex-1 text-xs font-semibold rounded-md px-2 py-1.5 text-white"
                    : "flex-1 text-xs font-semibold rounded-md px-2 py-1.5 border border-bk-brown/20 text-bk-brown/70"
                }
                style={
                  groupBy === "employee"
                    ? { background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }
                    : {}
                }
              >
                {t("group_by_employee")}
              </button>
              <button
                type="button"
                onClick={() => setGroupBy("branch")}
                className={
                  groupBy === "branch"
                    ? "flex-1 text-xs font-semibold rounded-md px-2 py-1.5 text-white"
                    : "flex-1 text-xs font-semibold rounded-md px-2 py-1.5 border border-bk-brown/20 text-bk-brown/70"
                }
                style={
                  groupBy === "branch"
                    ? { background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }
                    : {}
                }
              >
                {t("group_by_branch")}
              </button>
            </div>
          </div>
          <div>
            <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("search_placeholder")}</label>
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder={t("search_placeholder")}
              className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5 text-sm"
            />
          </div>
        </div>

        <div className="flex gap-2 mt-4">
          <button
            type="button"
            disabled={exporting !== null || loading}
            onClick={() => handleExport("xlsx")}
            className="flex items-center gap-1.5 text-xs font-semibold text-bk-brown border border-bk-brown/30 rounded-lg px-3 py-1.5 disabled:opacity-50"
          >
            <FileSpreadsheet size={14} />
            {t("export_excel")}
          </button>
          <button
            type="button"
            disabled={exporting !== null || loading}
            onClick={() => handleExport("pdf")}
            className="flex items-center gap-1.5 text-xs font-semibold text-bk-brown border border-bk-brown/30 rounded-lg px-3 py-1.5 disabled:opacity-50"
          >
            <FileText size={14} />
            {t("export_pdf")}
          </button>
        </div>
      </div>

      {error && (
        <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-4">{error}</p>
      )}

      <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 overflow-hidden">
        {loading ? (
          <LoadingState />
        ) : groupBy === "employee" ? (
          filteredEmployeeRows.length === 0 ? (
            <EmptyState icon={FileSpreadsheet} message={t("no_data")} />
          ) : (
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-bk-brown/10 bg-bk-cream2/60">
                  <th className="text-left px-4 py-2.5 text-xs font-semibold text-bk-brown/70">{t("col_employee")}</th>
                  <th className="text-left px-4 py-2.5 text-xs font-semibold text-bk-brown/70">{t("col_branch")}</th>
                  <th className="text-left px-4 py-2.5 text-xs font-semibold text-bk-brown/70">{t("col_accounting_account")}</th>
                  <th className="text-right px-4 py-2.5 text-xs font-semibold text-bk-brown/70">{t("col_days")}</th>
                  <th className="text-right px-4 py-2.5 text-xs font-semibold text-bk-brown/70">{t("col_sessions")}</th>
                  <th className="text-right px-4 py-2.5 text-xs font-semibold text-bk-brown/70">{t("col_hours")}</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-bk-brown/10">
                {filteredEmployeeRows.map((r) => (
                  <tr key={r.employee_id}>
                    <td className="px-4 py-2.5 font-medium text-bk-brown">{r.employee_name}</td>
                    <td className="px-4 py-2.5 text-bk-brown/70">{r.branch_name}</td>
                    <td className="px-4 py-2.5 text-bk-brown/70">{r.branch_accounting_account || "—"}</td>
                    <td className="px-4 py-2.5 text-right text-bk-brown/70">{r.days_worked}</td>
                    <td className="px-4 py-2.5 text-right text-bk-brown/70">{r.total_sessions}</td>
                    <td className="px-4 py-2.5 text-right font-semibold text-bk-brown">{r.total_hours.toFixed(2)}</td>
                  </tr>
                ))}
              </tbody>
              <tfoot>
                <tr className="border-t-2 border-bk-brown/20 bg-bk-cream2/40">
                  <td className="px-4 py-2.5 font-bold text-bk-brown" colSpan={5}>
                    {t("total_label")}
                  </td>
                  <td className="px-4 py-2.5 text-right font-bold text-bk-brown">{totalHoursEmployee.toFixed(2)}</td>
                </tr>
              </tfoot>
            </table>
          )
        ) : branchRows.length === 0 ? (
          <EmptyState icon={FileSpreadsheet} message={t("no_data")} />
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-bk-brown/10 bg-bk-cream2/60">
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-bk-brown/70">{t("col_branch")}</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-bk-brown/70">{t("col_accounting_account")}</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-bk-brown/70">{t("col_employees_count")}</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-bk-brown/70">{t("col_days")}</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-bk-brown/70">{t("col_hours")}</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-bk-brown/10">
              {branchRows.map((b) => {
                const isExpanded = expandedBranches.has(b.branch_id);
                const branchEmployees = filteredEmployeeRows.filter((r) => r.branch_id === b.branch_id);
                return (
                  <Fragment key={b.branch_id}>
                    <tr
                      onClick={() => toggleBranch(b.branch_id)}
                      className="cursor-pointer hover:bg-bk-cream2/30"
                    >
                      <td className="px-4 py-2.5 font-medium text-bk-brown">
                        <span className="inline-flex items-center gap-1.5">
                          {isExpanded ? (
                            <ChevronDown size={14} className="text-bk-brown/40 shrink-0" />
                          ) : (
                            <ChevronRight size={14} className="text-bk-brown/40 shrink-0" />
                          )}
                          {b.branch_name}
                        </span>
                      </td>
                      <td className="px-4 py-2.5 text-bk-brown/70">{b.branch_accounting_account || "—"}</td>
                      <td className="px-4 py-2.5 text-right text-bk-brown/70">{b.employee_count}</td>
                      <td className="px-4 py-2.5 text-right text-bk-brown/70">{b.total_days}</td>
                      <td className="px-4 py-2.5 text-right font-semibold text-bk-brown">{b.total_hours.toFixed(2)}</td>
                    </tr>
                    {isExpanded &&
                      branchEmployees.map((r) => (
                        <tr key={r.employee_id} className="bg-bk-cream2/20">
                          <td className="px-4 py-2 pl-11 text-sm text-bk-brown/80">{r.employee_name}</td>
                          <td className="px-4 py-2 text-bk-brown/40">—</td>
                          <td className="px-4 py-2 text-right text-bk-brown/40">—</td>
                          <td className="px-4 py-2 text-right text-bk-brown/60">{r.days_worked}</td>
                          <td className="px-4 py-2 text-right text-bk-brown/70">{r.total_hours.toFixed(2)}</td>
                        </tr>
                      ))}
                  </Fragment>
                );
              })}
            </tbody>
            <tfoot>
              <tr className="border-t-2 border-bk-brown/20 bg-bk-cream2/40">
                <td className="px-4 py-2.5 font-bold text-bk-brown" colSpan={4}>
                  {t("total_label")}
                </td>
                <td className="px-4 py-2.5 text-right font-bold text-bk-brown">{totalHoursBranch.toFixed(2)}</td>
              </tr>
            </tfoot>
          </table>
        )}
      </div>
    </div>
  );
}
