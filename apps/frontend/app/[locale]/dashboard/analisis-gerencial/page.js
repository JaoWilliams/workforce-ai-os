"use client";
import { useEffect, useState } from "react";
import { useTranslations } from "next-intl";
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid } from "recharts";
import { apiFetch } from "../../../../lib/api";
import { LoadingState } from "../../../../lib/ui";

function isoDaysAgo(days) {
  const d = new Date();
  d.setDate(d.getDate() - days);
  return d.toISOString().slice(0, 10);
}
function todayIso() {
  return new Date().toISOString().slice(0, 10);
}
function formatMoney(n) {
  return new Intl.NumberFormat("es-CR", { style: "currency", currency: "CRC", maximumFractionDigits: 0 }).format(n || 0);
}

function KpiCard({ label, value, sub, highlight }) {
  return (
    <div className={"bg-white rounded-xl shadow-sm border p-4 " + (highlight ? "border-bk-orange/40" : "border-bk-brown/10")}>
      <p className="text-xs text-bk-brown/60 mb-1">{label}</p>
      <p className="text-xl font-heading font-extrabold text-bk-brown">{value}</p>
      {sub && <p className="text-[11px] text-bk-brown/50 mt-1">{sub}</p>}
    </div>
  );
}

function HighlightCard({ title, dept, metric, money, suffix }) {
  if (!dept) {
    return (
      <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-4">
        <p className="text-xs text-bk-brown/60">{title}</p>
        <p className="text-sm text-bk-brown/40 mt-1">-</p>
      </div>
    );
  }
  const value = dept[metric];
  const display = money ? formatMoney(value) : value + (suffix || "");
  return (
    <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-4">
      <p className="text-xs text-bk-brown/60">{title}</p>
      <p className="text-sm font-semibold text-bk-brown mt-1">{dept.department_name}</p>
      <p className="text-lg font-heading font-extrabold text-bk-orange">{display}</p>
    </div>
  );
}

export default function AnalisisGerencialPage() {
  const t = useTranslations("labor_analytics_page");
  const [startDate, setStartDate] = useState(isoDaysAgo(90));
  const [endDate, setEndDate] = useState(todayIso());
  const [branches, setBranches] = useState([]);
  const [departments, setDepartments] = useState([]);
  const [branchFilter, setBranchFilter] = useState("");
  const [departmentFilter, setDepartmentFilter] = useState("");
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    apiFetch("/api/branches").then(setBranches).catch(() => {});
    apiFetch("/api/departments").then(setDepartments).catch(() => {});
  }, []);

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [startDate, endDate, branchFilter, departmentFilter]);

  function load() {
    setLoading(true);
    setError(null);
    let url = "/api/analytics/labor-dashboard?start_date=" + startDate + "&end_date=" + endDate;
    if (branchFilter) url += "&branch_id=" + branchFilter;
    if (departmentFilter) url += "&department_id=" + departmentFilter;
    apiFetch(url)
      .then(setData)
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }

  return (
    <div>
      <h1 className="font-heading text-2xl font-extrabold text-bk-brown mb-2">{t("title")}</h1>
      <p className="text-sm text-bk-brown/60 mb-6">{t("subtitle")}</p>

      <div className="flex flex-wrap items-end gap-3 mb-6">
        <div>
          <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("start_date")}</label>
          <input
            type="date"
            value={startDate}
            onChange={(e) => setStartDate(e.target.value)}
            className="text-xs border border-bk-brown/20 rounded-md px-2 py-1.5"
          />
        </div>
        <div>
          <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("end_date")}</label>
          <input
            type="date"
            value={endDate}
            onChange={(e) => setEndDate(e.target.value)}
            className="text-xs border border-bk-brown/20 rounded-md px-2 py-1.5"
          />
        </div>
        <div>
          <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("branch")}</label>
          <select
            value={branchFilter}
            onChange={(e) => setBranchFilter(e.target.value)}
            className="text-xs border border-bk-brown/20 rounded-md px-2 py-1.5"
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
          <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("department")}</label>
          <select
            value={departmentFilter}
            onChange={(e) => setDepartmentFilter(e.target.value)}
            className="text-xs border border-bk-brown/20 rounded-md px-2 py-1.5"
          >
            <option value="">{t("all_departments")}</option>
            {departments.map((d) => (
              <option key={d.id} value={d.id}>
                {d.name}
              </option>
            ))}
          </select>
        </div>
      </div>

      {error && <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-4">{error}</p>}

      {loading || !data ? (
        <LoadingState />
      ) : (
        <div className="space-y-6">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <KpiCard label={t("kpi_total_cost")} value={formatMoney(data.totals.total_gross_pay)} />
            <KpiCard label={t("kpi_headcount")} value={data.totals.headcount} />
            <KpiCard label={t("kpi_avg_cost")} value={formatMoney(data.totals.avg_cost_per_employee)} />
            <KpiCard
              label={t("kpi_overtime_pay")}
              value={formatMoney(data.totals.total_overtime_pay)}
              sub={data.totals.total_overtime_hours + " " + t("hours")}
            />
          </div>

          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <KpiCard label={t("kpi_turnover_rate")} value={data.turnover.turnover_rate_pct + "%"} highlight />
            <KpiCard label={t("kpi_hires")} value={data.turnover.hires} />
            <KpiCard label={t("kpi_departures")} value={data.turnover.departures} />
            <KpiCard label={t("kpi_avg_headcount")} value={data.turnover.avg_headcount} />
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <HighlightCard title={t("highest_cost_department")} dept={data.highest_cost_department} metric="gross_pay" money />
            <HighlightCard title={t("lowest_cost_department")} dept={data.lowest_cost_department} metric="gross_pay" money />
            <HighlightCard
              title={t("most_overtime_department")}
              dept={data.most_overtime_department}
              metric="overtime_hours"
              suffix={" " + t("hours")}
            />
            <HighlightCard
              title={t("least_overtime_department")}
              dept={data.least_overtime_department}
              metric="overtime_hours"
              suffix={" " + t("hours")}
            />
          </div>

          <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5">
            <h2 className="font-heading font-bold text-bk-brown mb-4">{t("chart_title")}</h2>
            <ResponsiveContainer width="100%" height={300}>
              <BarChart data={data.top_departments_by_cost}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="department_name" tick={{ fontSize: 11 }} />
                <YAxis tick={{ fontSize: 11 }} />
                <Tooltip formatter={(v) => formatMoney(v)} />
                <Bar dataKey="gross_pay" fill="#f97316" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </div>

          <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 overflow-hidden">
            <div className="p-4 border-b border-bk-brown/10">
              <h2 className="font-heading font-bold text-bk-brown">{t("top10_departments_title")}</h2>
            </div>
            <table className="min-w-full text-xs">
              <thead>
                <tr className="border-b border-bk-brown/10 text-bk-brown/60">
                  <th className="text-left px-4 py-2">{t("department")}</th>
                  <th className="text-right px-4 py-2">{t("col_cost")}</th>
                  <th className="text-right px-4 py-2">{t("col_headcount")}</th>
                  <th className="text-right px-4 py-2">{t("col_avg_cost")}</th>
                  <th className="text-right px-4 py-2">{t("col_overtime")}</th>
                </tr>
              </thead>
              <tbody>
                {data.top_departments_by_cost.length === 0 ? (
                  <tr>
                    <td colSpan={5} className="px-4 py-6 text-center text-bk-brown/50">
                      {t("no_data")}
                    </td>
                  </tr>
                ) : (
                  data.top_departments_by_cost.map((r, i) => (
                    <tr key={i} className="border-b border-bk-brown/5">
                      <td className="px-4 py-2 font-semibold text-bk-brown">{r.department_name}</td>
                      <td className="px-4 py-2 text-right">{formatMoney(r.gross_pay)}</td>
                      <td className="px-4 py-2 text-right">{r.headcount}</td>
                      <td className="px-4 py-2 text-right">{formatMoney(r.avg_cost_per_employee)}</td>
                      <td className="px-4 py-2 text-right">{formatMoney(r.overtime_pay)}</td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>

          <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 overflow-hidden">
            <div className="p-4 border-b border-bk-brown/10">
              <h2 className="font-heading font-bold text-bk-brown">{t("top10_overtime_title")}</h2>
            </div>
            <table className="min-w-full text-xs">
              <thead>
                <tr className="border-b border-bk-brown/10 text-bk-brown/60">
                  <th className="text-left px-4 py-2">{t("employee")}</th>
                  <th className="text-left px-4 py-2">{t("department")}</th>
                  <th className="text-right px-4 py-2">{t("col_overtime_pay")}</th>
                  <th className="text-right px-4 py-2">{t("col_overtime_hours")}</th>
                </tr>
              </thead>
              <tbody>
                {data.top_overtime_employees.length === 0 ? (
                  <tr>
                    <td colSpan={4} className="px-4 py-6 text-center text-bk-brown/50">
                      {t("no_data")}
                    </td>
                  </tr>
                ) : (
                  data.top_overtime_employees.map((r, i) => (
                    <tr key={i} className="border-b border-bk-brown/5">
                      <td className="px-4 py-2 font-semibold text-bk-brown">{r.employee_name}</td>
                      <td className="px-4 py-2 text-bk-brown/70">{r.department_name}</td>
                      <td className="px-4 py-2 text-right">{formatMoney(r.overtime_pay)}</td>
                      <td className="px-4 py-2 text-right">{r.overtime_hours}</td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>

          <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 overflow-hidden">
            <div className="p-4 border-b border-bk-brown/10">
              <h2 className="font-heading font-bold text-bk-brown">{t("turnover_by_department_title")}</h2>
            </div>
            <table className="min-w-full text-xs">
              <thead>
                <tr className="border-b border-bk-brown/10 text-bk-brown/60">
                  <th className="text-left px-4 py-2">{t("department")}</th>
                  <th className="text-right px-4 py-2">{t("col_departures")}</th>
                  <th className="text-right px-4 py-2">{t("col_avg_headcount")}</th>
                  <th className="text-right px-4 py-2">{t("col_turnover_rate")}</th>
                </tr>
              </thead>
              <tbody>
                {data.turnover.by_department.length === 0 ? (
                  <tr>
                    <td colSpan={4} className="px-4 py-6 text-center text-bk-brown/50">
                      {t("no_data")}
                    </td>
                  </tr>
                ) : (
                  data.turnover.by_department.map((r, i) => (
                    <tr key={i} className="border-b border-bk-brown/5">
                      <td className="px-4 py-2 font-semibold text-bk-brown">{r.department_name}</td>
                      <td className="px-4 py-2 text-right">{r.departures}</td>
                      <td className="px-4 py-2 text-right">{r.avg_headcount}</td>
                      <td className="px-4 py-2 text-right">{r.turnover_rate}%</td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
