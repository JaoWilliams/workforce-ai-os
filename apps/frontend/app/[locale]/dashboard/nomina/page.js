"use client";

import { useEffect, useState } from "react";
import { useTranslations } from "next-intl";
import { FileSpreadsheet, FileText, Save } from "lucide-react";
import { apiFetch, apiFetchBlob } from "../../../../lib/api";
import { useToast } from "../../../../lib/toast";
import { usePermissions } from "../../../../lib/permissions";
import { LoadingState, EmptyState } from "../../../../lib/ui";

const PAY_FREQUENCIES = ["semanal", "quincenal", "bisemanal", "mensual"];

function defaultStartDate() {
  const d = new Date();
  d.setDate(d.getDate() - 30);
  return d.toISOString().slice(0, 10);
}
function defaultEndDate() {
  return new Date().toISOString().slice(0, 10);
}

export default function NominaPage() {
  const t = useTranslations("payroll");
  const { showToast } = useToast();
  const { hasPermission } = usePermissions();

  const [branches, setBranches] = useState([]);
  const [rows, setRows] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [startDate, setStartDate] = useState(defaultStartDate());
  const [endDate, setEndDate] = useState(defaultEndDate());
  const [branchId, setBranchId] = useState("");
  const [searchQuery, setSearchQuery] = useState("");
  const [exporting, setExporting] = useState(null);

  const [hoursConfig, setHoursConfig] = useState([]);
  const [hoursDraft, setHoursDraft] = useState({});
  const [savingFreq, setSavingFreq] = useState(null);

  useEffect(() => {
    apiFetch("/api/branches").then(setBranches).catch(() => {});
    loadHoursConfig();
  }, []);

  useEffect(() => {
    loadPayroll();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [startDate, endDate, branchId]);

  function loadHoursConfig() {
    apiFetch("/api/catalogs/payroll-hours")
      .then((data) => {
        setHoursConfig(data);
        const draft = {};
        data.forEach((c) => {
          draft[c.pay_frequency] = c.standard_hours != null ? String(c.standard_hours) : "";
        });
        setHoursDraft(draft);
      })
      .catch(() => {});
  }

  function buildQuery() {
    let q = `start_date=${startDate}&end_date=${endDate}`;
    if (branchId) q += `&branch_id=${branchId}`;
    return q;
  }

  function loadPayroll() {
    if (!startDate || !endDate) return;
    setLoading(true);
    setError(null);
    apiFetch("/api/payroll?" + buildQuery())
      .then(setRows)
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }

  async function handleSaveHours(freq) {
    const value = parseFloat(hoursDraft[freq]);
    if (!value || value <= 0) {
      showToast(t("standard_hours_label"), "error");
      return;
    }
    setSavingFreq(freq);
    try {
      await apiFetch(`/api/catalogs/payroll-hours/${freq}`, {
        method: "PUT",
        body: JSON.stringify({ standard_hours: value }),
      });
      showToast(t("hours_saved_toast"));
      loadHoursConfig();
      loadPayroll();
    } catch (err) {
      showToast(err.message, "error");
    } finally {
      setSavingFreq(null);
    }
  }

  const filteredRows = rows.filter((r) => {
    const q = searchQuery.trim().toLowerCase();
    if (!q) return true;
    return r.employee_name.toLowerCase().includes(q) || r.branch_name.toLowerCase().includes(q);
  });

  const currencyTotals = {};
  filteredRows.forEach((r) => {
    if (r.currency && r.gross_pay != null) {
      currencyTotals[r.currency] = (currencyTotals[r.currency] || 0) + r.gross_pay;
    }
  });

  const missingContractCount = filteredRows.filter((r) => !r.has_contract).length;
  const missingConfigCount = filteredRows.filter((r) => r.has_contract && r.hours_config_missing).length;

  function freqLabel(freq) {
    if (!freq) return "—";
    const key = "freq_" + freq;
    const translated = t(key);
    return translated === key ? freq : translated;
  }

  function formatMoney(amount, currency) {
    if (amount == null) return "—";
    return new Intl.NumberFormat("es-CR", {
      style: "currency",
      currency: currency || "CRC",
      maximumFractionDigits: 2,
    }).format(amount);
  }

  async function handleExport(format) {
    setExporting(format);
    try {
      const blob = await apiFetchBlob(`/api/payroll/export-${format}?` + buildQuery());
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `nomina_bruta_${startDate}_${endDate}.${format === "xlsx" ? "xlsx" : "pdf"}`;
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
        <h2 className="font-heading font-bold text-bk-brown mb-2">{t("hours_config_title")}</h2>
        <p className="text-xs text-bk-brown/60 mb-4">{t("hours_config_hint")}</p>
        <div className="grid grid-cols-1 md:grid-cols-4 gap-3">
          {PAY_FREQUENCIES.map((freq) => {
            const configured = hoursConfig.find((c) => c.pay_frequency === freq);
            const isConfigured = configured && configured.standard_hours != null;
            return (
              <div key={freq} className="border border-bk-brown/10 rounded-lg p-3">
                <p className="text-xs font-semibold text-bk-brown mb-1">{freqLabel(freq)}</p>
                <p className={isConfigured ? "text-[11px] text-green-700 mb-2" : "text-[11px] text-bk-red mb-2"}>
                  {isConfigured ? `${configured.standard_hours}h` : t("not_configured")}
                </p>
                {hasPermission("catalogs.manage") && (
                  <div className="flex gap-1.5">
                    <input
                      type="number"
                      step="0.01"
                      min="0"
                      value={hoursDraft[freq] || ""}
                      onChange={(e) => setHoursDraft({ ...hoursDraft, [freq]: e.target.value })}
                      placeholder={t("standard_hours_label")}
                      className="w-full border border-bk-brown/20 rounded-md px-2 py-1 text-sm"
                    />
                    <button
                      type="button"
                      disabled={savingFreq === freq}
                      onClick={() => handleSaveHours(freq)}
                      className="shrink-0 rounded-md px-2 py-1 text-white disabled:opacity-50"
                      style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}
                    >
                      <Save size={14} />
                    </button>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </div>

      <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 mb-6">
        <div className="grid grid-cols-1 md:grid-cols-4 gap-3 items-end">
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
      {missingContractCount > 0 && (
        <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-3">
          {t("missing_contract_warning", { count: missingContractCount })}
        </p>
      )}
      {missingConfigCount > 0 && (
        <p className="text-sm text-orange-700 bg-orange-50 rounded-lg px-3 py-2 mb-4">
          {t("missing_config_warning", { count: missingConfigCount })}
        </p>
      )}

      <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 overflow-hidden">
        {loading ? (
          <LoadingState />
        ) : filteredRows.length === 0 ? (
          <EmptyState icon={FileSpreadsheet} message={t("no_data")} />
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-bk-brown/10 bg-bk-cream2/60">
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-bk-brown/70">{t("col_employee")}</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-bk-brown/70">{t("col_branch")}</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-bk-brown/70">{t("col_accounting_account")}</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-bk-brown/70">{t("col_frequency")}</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-bk-brown/70">{t("col_base_salary")}</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-bk-brown/70">{t("col_hours")}</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-bk-brown/70">{t("col_hourly_rate")}</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-bk-brown/70">{t("col_gross")}</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-bk-brown/10">
              {filteredRows.map((r) => (
                <tr key={r.employee_id}>
                  <td className="px-4 py-2.5 font-medium text-bk-brown">{r.employee_name}</td>
                  <td className="px-4 py-2.5 text-bk-brown/70">{r.branch_name}</td>
                  <td className="px-4 py-2.5 text-bk-brown/70">{r.branch_accounting_account || "—"}</td>
                  <td className="px-4 py-2.5 text-bk-brown/70">{freqLabel(r.pay_frequency)}</td>
                  <td className="px-4 py-2.5 text-right text-bk-brown/70">
                    {r.base_salary != null ? formatMoney(r.base_salary, r.currency) : "—"}
                  </td>
                  <td className="px-4 py-2.5 text-right text-bk-brown/70">{r.total_hours.toFixed(2)}</td>
                  <td className="px-4 py-2.5 text-right text-bk-brown/70">
                    {r.hourly_rate != null ? formatMoney(r.hourly_rate, r.currency) : "—"}
                  </td>
                  <td className="px-4 py-2.5 text-right font-semibold">
                    {!r.has_contract ? (
                      <span className="text-bk-red">{t("no_contract")}</span>
                    ) : r.hours_config_missing ? (
                      <span className="text-orange-600">{t("config_pending")}</span>
                    ) : (
                      <span className="text-bk-brown">{formatMoney(r.gross_pay, r.currency)}</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
            <tfoot>
              <tr className="border-t-2 border-bk-brown/20 bg-bk-cream2/40">
                <td className="px-4 py-2.5 font-bold text-bk-brown" colSpan={7}>
                  {t("total_label")}
                </td>
                <td className="px-4 py-2.5 text-right font-bold text-bk-brown">
                  {Object.entries(currencyTotals).map(([cur, tot]) => (
                    <div key={cur}>{formatMoney(tot, cur)}</div>
                  ))}
                </td>
              </tr>
            </tfoot>
          </table>
        )}
      </div>
    </div>
  );
}
