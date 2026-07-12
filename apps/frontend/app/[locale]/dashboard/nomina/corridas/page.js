"use client";
import { useEffect, useState, useCallback } from "react";
import { useTranslations } from "next-intl";
import {
  Plus,
  FileEdit,
  ShieldCheck,
  Calculator,
  ThumbsUp,
  Banknote,
  BookOpen,
  Landmark,
  CheckCircle2,
  AlertTriangle,
  ChevronRight,
  ChevronLeft,
  RefreshCw,
  Download,
  MinusCircle,
  UserX,
  Percent,
  Clock3,
  Building2,
  X,
} from "lucide-react";
import { apiFetch, apiFetchBlob } from "../../../../../lib/api";
import { useToast } from "../../../../../lib/toast";
import { usePermissions } from "../../../../../lib/permissions";
import { LoadingState, EmptyState } from "../../../../../lib/ui";

const STATUS_ORDER = ["draft", "validado", "calculado", "aprobado", "pagado", "contabilizado", "archivo_bancario"];

const STATUS_ICONS = {
  draft: FileEdit,
  validado: ShieldCheck,
  calculado: Calculator,
  aprobado: ThumbsUp,
  pagado: Banknote,
  contabilizado: BookOpen,
  archivo_bancario: Landmark,
};

const RULE_ICONS = {
  payroll_net_zero_or_negative: MinusCircle,
  payroll_paid_after_termination: UserX,
  payroll_net_deviation: Percent,
  payroll_overtime_outlier: Clock3,
  payroll_branch_net_outlier: Building2,
  payroll_bank_account_changed_before_payment: Landmark,
};

const PAY_FREQUENCIES = ["semanal", "quincenal", "bisemanal", "mensual"];
const DASH = "\u2014";

function emptyDraft() {
  return { pay_frequency: "mensual", period_start: "", period_end: "", pay_date: "", notes: "" };
}

function formatMoney(amount, currency) {
  if (amount == null) return "\u2014";
  return new Intl.NumberFormat("es-CR", {
    style: "currency",
    currency: currency || "CRC",
    maximumFractionDigits: 2,
  }).format(amount);
}

export default function PayrollRunsPage() {
  const t = useTranslations("payroll_run");
  const tp = useTranslations("payroll");
  const { showToast } = useToast();
  const { hasPermission } = usePermissions();

  const [periods, setPeriods] = useState([]);
  const [loadingPeriods, setLoadingPeriods] = useState(true);
  const [selectedId, setSelectedId] = useState(null);
  const [showCreate, setShowCreate] = useState(false);
  const [draft, setDraft] = useState(emptyDraft());
  const [creating, setCreating] = useState(false);

  const [detailLoading, setDetailLoading] = useState(false);
  const [netRows, setNetRows] = useState([]);
  const [snapshotRows, setSnapshotRows] = useState([]);
  const [flags, setFlags] = useState([]);
  const [journalEntry, setJournalEntry] = useState(null);
  const [bankFile, setBankFile] = useState(null);
  const [transitioning, setTransitioning] = useState(false);
  const [generating, setGenerating] = useState(false);

  const selectedPeriod = periods.find((p) => p.id === selectedId) || null;

  const loadPeriods = useCallback(() => {
    setLoadingPeriods(true);
    apiFetch("/api/payroll/periods")
      .then(setPeriods)
      .catch((err) => showToast(err.message, "error"))
      .finally(() => setLoadingPeriods(false));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    loadPeriods();
  }, [loadPeriods]);

  const loadDetail = useCallback(async (period) => {
    if (!period) return;
    setDetailLoading(true);
    try {
      const net = await apiFetch(`/api/payroll/net?period_id=${period.id}`);
      setNetRows(net);
    } catch (err) {
      showToast(err.message, "error");
    }
    try {
      const flagsData = await apiFetch(`/api/confianza-operativa/flags?payroll_period_id=${period.id}`);
      setFlags(flagsData);
    } catch (err) {
      setFlags([]);
    }
    if (STATUS_ORDER.indexOf(period.status) >= STATUS_ORDER.indexOf("calculado")) {
      try {
        const snap = await apiFetch(`/api/payroll/periods/${period.id}/snapshot`);
        setSnapshotRows(snap);
      } catch (err) {
        setSnapshotRows([]);
      }
    } else {
      setSnapshotRows([]);
    }
    if (STATUS_ORDER.indexOf(period.status) >= STATUS_ORDER.indexOf("pagado")) {
      try {
        const entries = await apiFetch("/api/accounting/journal-entries?entry_type=planilla");
        const found = entries.find((e) => e.payroll_period_id === period.id) || null;
        setJournalEntry(found);
      } catch (err) {
        setJournalEntry(null);
      }
    } else {
      setJournalEntry(null);
    }
    if (STATUS_ORDER.indexOf(period.status) >= STATUS_ORDER.indexOf("contabilizado")) {
      try {
        const files = await apiFetch(`/api/bank-file?payroll_period_id=${period.id}`);
        setBankFile(files[0] || null);
      } catch (err) {
        setBankFile(null);
      }
    } else {
      setBankFile(null);
    }
    setDetailLoading(false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (selectedPeriod) {
      loadDetail(selectedPeriod);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedId]);

  function openPeriod(id) {
    setSelectedId(id);
  }

  function backToList() {
    setSelectedId(null);
    loadPeriods();
  }

  async function handleCreate() {
    if (!draft.period_start || !draft.period_end) {
      showToast(t("field_period_start"), "error");
      return;
    }
    setCreating(true);
    try {
      const created = await apiFetch("/api/payroll/periods", {
        method: "POST",
        body: JSON.stringify({
          pay_frequency: draft.pay_frequency,
          period_start: draft.period_start,
          period_end: draft.period_end,
          pay_date: draft.pay_date || null,
          notes: draft.notes || null,
        }),
      });
      showToast(t("create_ok_toast"));
      setShowCreate(false);
      setDraft(emptyDraft());
      loadPeriods();
      setSelectedId(created.id);
    } catch (err) {
      showToast(err.message, "error");
    } finally {
      setCreating(false);
    }
  }

  function extractErrorDetail(err) {
    if (err && err.detail && typeof err.detail === "object" && err.detail.detail) {
      return err.detail.detail;
    }
    try {
      return JSON.parse(err.message);
    } catch {
      return { error: "generic" };
    }
  }

  function describeError(errObj) {
    if (!errObj || !errObj.error) return t("error_generic");
    switch (errObj.error) {
      case "invalid_transition":
        return t("error_invalid_transition");
      case "missing_catalogs":
        return t("error_missing_catalogs") + " " + (errObj.missing || []).join(", ");
      case "blocked_rows":
        return t("error_blocked_rows", { count: errObj.count || 0 });
      case "unresolved_flags":
        return t("error_unresolved_flags", { count: errObj.count || 0 });
      case "accounting_entry_missing":
        return t("error_accounting_entry_missing");
      case "bank_file_missing":
        return t("error_bank_file_missing");
      case "bank_config_missing":
        return t("error_bank_config_missing");
      case "no_valid_rows":
        return t("error_no_valid_rows");
      case "no_rows":
        return t("error_no_rows");
      case "missing_accounts":
        return t("error_missing_accounts");
      case "zero_amount":
        return t("error_zero_amount");
      case "unbalanced":
        return t("error_unbalanced");
      default:
        return t("error_generic");
    }
  }

  async function handleTransition(targetStatus) {
    if (!selectedPeriod) return;
    setTransitioning(true);
    try {
      await apiFetch(`/api/payroll/periods/${selectedPeriod.id}/status`, {
        method: "PATCH",
        body: JSON.stringify({ status: targetStatus }),
      });
      showToast(t("transition_ok_toast"));
      await loadPeriods();
      await loadDetail({ ...selectedPeriod, status: targetStatus });
    } catch (err) {
      const errObj = extractErrorDetail(err);
      showToast(describeError(errObj), "error");
    } finally {
      setTransitioning(false);
    }
  }

  async function handleResolveFlag(flagId) {
    try {
      await apiFetch(`/api/confianza-operativa/flags/${flagId}`, {
        method: "PATCH",
        body: JSON.stringify({ resolved: true }),
      });
      showToast(t("anomaly_resolved_toast"));
      setFlags((prev) => prev.filter((f) => f.id !== flagId));
    } catch (err) {
      showToast(err.message, "error");
    }
  }

  async function handleGenerateJournalEntry() {
    if (!selectedPeriod) return;
    setGenerating(true);
    try {
      const entry = await apiFetch(`/api/accounting/journal-entries/payroll?payroll_period_id=${selectedPeriod.id}`, {
        method: "POST",
      });
      setJournalEntry(entry);
      showToast(t("transition_ok_toast"));
    } catch (err) {
      const errObj = extractErrorDetail(err);
      showToast(describeError(errObj), "error");
    } finally {
      setGenerating(false);
    }
  }

  async function handleGenerateBankFile() {
    if (!selectedPeriod) return;
    setGenerating(true);
    try {
      const file = await apiFetch(`/api/bank-file/generate/${selectedPeriod.id}`, { method: "POST" });
      setBankFile(file);
      showToast(t("transition_ok_toast"));
    } catch (err) {
      const errObj = extractErrorDetail(err);
      showToast(describeError(errObj), "error");
    } finally {
      setGenerating(false);
    }
  }

  async function handleDownloadBankFile() {
    if (!bankFile) return;
    try {
      const blob = await apiFetchBlob(`/api/bank-file/${bankFile.id}/export-txt`);
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `planilla_bancaria_${selectedPeriod.id}.txt`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      window.URL.revokeObjectURL(url);
    } catch (err) {
      showToast(err.message, "error");
    }
  }

  function freqLabel(freq) {
    const key = "freq_" + freq;
    const translated = tp(key);
    return translated === key ? freq : translated;
  }

  function statusBadge(status) {
    const colors = {
      draft: "bg-bk-brown/10 text-bk-brown/70",
      validado: "bg-blue-50 text-blue-700",
      calculado: "bg-purple-50 text-purple-700",
      aprobado: "bg-amber-50 text-amber-700",
      pagado: "bg-teal-50 text-teal-700",
      contabilizado: "bg-indigo-50 text-indigo-700",
      archivo_bancario: "bg-green-50 text-green-700",
    };
    const label = STATUS_ORDER.includes(status) ? t(`status_${status}`) : status;
    return (
      <span className={"inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[11px] font-semibold " + (colors[status] || "bg-bk-brown/10 text-bk-brown/70")}>
        {label}
      </span>
    );
  }

  function renderStepper(status) {
    const currentIndex = STATUS_ORDER.indexOf(status);
    return (
      <div className="flex items-center overflow-x-auto pb-2">
        {STATUS_ORDER.map((key, idx) => {
          const Icon = STATUS_ICONS[key];
          const done = idx < currentIndex;
          const active = idx === currentIndex;
          return (
            <div key={key} className="flex items-center shrink-0">
              <div className="flex flex-col items-center gap-1.5 w-24">
                <div
                  className={
                    "w-11 h-11 rounded-full flex items-center justify-center border-2 transition-all duration-500 " +
                    (done
                      ? "bg-bk-orange border-bk-orange text-white"
                      : active
                      ? "bg-white border-bk-orange text-bk-orange scale-110"
                      : "bg-white border-bk-brown/15 text-bk-brown/30")
                  }
                  style={active ? { boxShadow: "0 0 0 4px rgba(255,135,50,0.18)" } : undefined}
                >
                  {done ? <CheckCircle2 size={20} /> : <Icon size={18} />}
                </div>
                <span
                  className={
                    "text-[10px] font-semibold text-center leading-tight " +
                    (active ? "text-bk-orange" : done ? "text-bk-brown" : "text-bk-brown/35")
                  }
                >
                  {t(`status_${key}`)}
                </span>
              </div>
              {idx < STATUS_ORDER.length - 1 && (
                <div className={"h-0.5 w-6 md:w-10 -mt-5 transition-colors duration-500 " + (idx < currentIndex ? "bg-bk-orange" : "bg-bk-brown/15")} />
              )}
            </div>
          );
        })}
      </div>
    );
  }

  function renderAnomalyQueue() {
    if (flags.length === 0) {
      return <EmptyState icon={ShieldCheck} message={t("anomaly_none")} />;
    }
    return (
      <div className="space-y-2">
        {flags.map((f) => {
          const Icon = RULE_ICONS[f.rule_code] || AlertTriangle;
          const high = f.severity === "high";
          return (
            <div
              key={f.id}
              className={
                "flex items-start gap-3 rounded-lg border-l-4 p-3 " +
                (high ? "border-bk-red bg-bk-red/5" : "border-bk-orange bg-bk-orange/5")
              }
            >
              <Icon size={18} className={high ? "text-bk-red mt-0.5 shrink-0" : "text-bk-orange mt-0.5 shrink-0"} />
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="text-sm font-semibold text-bk-brown">{t(`rule_${f.rule_code}`)}</span>
                  <span className={"text-[10px] font-semibold uppercase px-1.5 py-0.5 rounded " + (high ? "bg-bk-red/10 text-bk-red" : "bg-bk-orange/10 text-bk-orange")}>
                    {t(high ? "severity_high" : "severity_medium")}
                  </span>
                </div>
                <p className="text-xs text-bk-brown/70 mt-0.5">{f.details && f.details.reason}</p>
              </div>
              {hasPermission("confianza.manage") && (
                <button
                  type="button"
                  onClick={() => handleResolveFlag(f.id)}
                  className="shrink-0 text-xs font-semibold text-white rounded-lg px-3 py-1.5"
                  style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}
                >
                  {t("anomaly_resolve")}
                </button>
              )}
            </div>
          );
        })}
      </div>
    );
  }

  function renderEmployeeTable(rowsSource) {
    if (rowsSource.length === 0) {
      return <EmptyState icon={Calculator} message={t("no_data")} />;
    }
    return (
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-bk-brown/10 bg-bk-cream2/60">
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-bk-brown/70">{t("col_employee")}</th>
              <th className="text-right px-4 py-2.5 text-xs font-semibold text-bk-brown/70">{t("col_gross")}</th>
              <th className="text-right px-4 py-2.5 text-xs font-semibold text-bk-brown/70">{t("col_ccss")}</th>
              <th className="text-right px-4 py-2.5 text-xs font-semibold text-bk-brown/70">{t("col_renta")}</th>
              <th className="text-right px-4 py-2.5 text-xs font-semibold text-bk-brown/70">{t("col_net")}</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-bk-brown/10">
            {rowsSource.map((r) => (
              <tr key={r.employee_id}>
                <td className="px-4 py-2.5 font-medium text-bk-brown">{r.employee_name || "\u2014"}</td>
                <td className="px-4 py-2.5 text-right text-bk-brown/70">{formatMoney(r.gross_pay)}</td>
                <td className="px-4 py-2.5 text-right text-bk-brown/70">{formatMoney(r.ccss_deduction)}</td>
                <td className="px-4 py-2.5 text-right text-bk-brown/70">{formatMoney(r.renta_amount)}</td>
                <td className="px-4 py-2.5 text-right font-semibold text-bk-brown">{formatMoney(r.net_pay)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    );
  }

  function renderActionPanel() {
    if (!selectedPeriod) return null;
    const status = selectedPeriod.status;
    const canManage = hasPermission("payroll.manage");
    const unresolvedCount = flags.filter((f) => !f.resolved).length;

    if (!STATUS_ORDER.includes(status)) {
      return (
        <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5">
          <h2 className="font-heading font-bold text-bk-brown mb-1">{t("legacy_status_title")}</h2>
          <p className="text-xs text-bk-brown/60">{t("legacy_status_desc", { status })}</p>
        </div>
      );
    }

    return (
      <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5">
        <h2 className="font-heading font-bold text-bk-brown mb-1">{t(`step_${status}_title`)}</h2>
        <p className="text-xs text-bk-brown/60 mb-4">{t(`step_${status}_desc`)}</p>

        {status === "draft" && canManage && (
          <button type="button" disabled={transitioning} onClick={() => handleTransition("validado")} className="flex items-center gap-2 text-sm font-semibold text-white rounded-lg px-4 py-2 disabled:opacity-50" style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}>
            <ShieldCheck size={16} />
            {t("step_draft_action")}
            <ChevronRight size={16} />
          </button>
        )}

        {status === "validado" && (
          <>
            <h3 className="text-xs font-bold uppercase tracking-wide text-bk-brown/50 mb-2">{t("net_preview_title")}</h3>
            <div className="mb-4">{renderEmployeeTable(netRows)}</div>
            {canManage && (
              <button type="button" disabled={transitioning} onClick={() => handleTransition("calculado")} className="flex items-center gap-2 text-sm font-semibold text-white rounded-lg px-4 py-2 disabled:opacity-50" style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}>
                <Calculator size={16} />
                {t("step_validado_action")}
                <ChevronRight size={16} />
              </button>
            )}
          </>
        )}

        {status === "calculado" && (
          <>
            <h3 className="text-xs font-bold uppercase tracking-wide text-bk-brown/50 mb-2">{t("anomaly_queue_title")}</h3>
            <div className="mb-5">{renderAnomalyQueue()}</div>
            <h3 className="text-xs font-bold uppercase tracking-wide text-bk-brown/50 mb-2">{t("snapshot_title")}</h3>
            <div className="mb-4">{renderEmployeeTable(snapshotRows)}</div>
            {canManage && (
              <button type="button" disabled={transitioning || unresolvedCount > 0} onClick={() => handleTransition("aprobado")} className="flex items-center gap-2 text-sm font-semibold text-white rounded-lg px-4 py-2 disabled:opacity-50" style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}>
                <ThumbsUp size={16} />
                {t("step_calculado_action")}
                <ChevronRight size={16} />
              </button>
            )}
            {unresolvedCount > 0 && (
              <p className="text-xs text-bk-red mt-2">{t("step_calculado_blocked", { count: unresolvedCount })}</p>
            )}
          </>
        )}

        {status === "aprobado" && canManage && (
          <button type="button" disabled={transitioning} onClick={() => handleTransition("pagado")} className="flex items-center gap-2 text-sm font-semibold text-white rounded-lg px-4 py-2 disabled:opacity-50" style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}>
            <Banknote size={16} />
            {t("step_aprobado_action")}
            <ChevronRight size={16} />
          </button>
        )}

        {status === "pagado" && (
          <>
            {journalEntry ? (
              <div className="mb-4 border border-bk-brown/10 rounded-lg p-3">
                <p className="text-xs font-semibold text-bk-brown mb-1">{t("journal_entry_title")}</p>
                <p className="text-sm text-bk-brown/70">{t("journal_entry_total")}: {formatMoney(journalEntry.total_debit)}</p>
              </div>
            ) : (
              canManage && (
                <button type="button" disabled={generating} onClick={handleGenerateJournalEntry} className="flex items-center gap-2 text-sm font-semibold text-bk-brown border border-bk-brown/30 rounded-lg px-4 py-2 mb-3 disabled:opacity-50">
                  <BookOpen size={16} />
                  {generating ? t("generating") : t("step_pagado_action_generate")}
                </button>
              )
            )}
            {journalEntry && canManage && (
              <button type="button" disabled={transitioning} onClick={() => handleTransition("contabilizado")} className="flex items-center gap-2 text-sm font-semibold text-white rounded-lg px-4 py-2 disabled:opacity-50" style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}>
                {t("step_pagado_action_next")}
                <ChevronRight size={16} />
              </button>
            )}
          </>
        )}

        {status === "contabilizado" && (
          <>
            {bankFile ? (
              <div className="mb-4 border border-bk-brown/10 rounded-lg p-3">
                <p className="text-xs font-semibold text-bk-brown mb-1">{t("bank_file_title")}</p>
                <p className="text-sm text-bk-brown/70">{t("bank_file_rows", { count: bankFile.row_count })}</p>
                {bankFile.missing_count > 0 && (
                  <p className="text-sm text-orange-600">{t("bank_file_missing", { count: bankFile.missing_count })}</p>
                )}
              </div>
            ) : (
              canManage && (
                <button type="button" disabled={generating} onClick={handleGenerateBankFile} className="flex items-center gap-2 text-sm font-semibold text-bk-brown border border-bk-brown/30 rounded-lg px-4 py-2 mb-3 disabled:opacity-50">
                  <Landmark size={16} />
                  {generating ? t("generating") : t("step_contabilizado_action_generate")}
                </button>
              )
            )}
            {bankFile && canManage && (
              <button type="button" disabled={transitioning} onClick={() => handleTransition("archivo_bancario")} className="flex items-center gap-2 text-sm font-semibold text-white rounded-lg px-4 py-2 disabled:opacity-50" style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}>
                {t("step_contabilizado_action_next")}
                <ChevronRight size={16} />
              </button>
            )}
          </>
        )}

        {status === "archivo_bancario" && (
          <>
            <div className="flex items-center gap-2 text-green-700 mb-4">
              <CheckCircle2 size={20} />
              <span className="text-sm font-semibold">{t("step_archivo_bancario_desc")}</span>
            </div>
            {bankFile && (
              <button type="button" onClick={handleDownloadBankFile} className="flex items-center gap-2 text-sm font-semibold text-bk-brown border border-bk-brown/30 rounded-lg px-4 py-2 mb-5">
                <Download size={16} />
                {t("step_archivo_bancario_download")}
              </button>
            )}
            <h3 className="text-xs font-bold uppercase tracking-wide text-bk-brown/50 mb-2">{t("snapshot_title")}</h3>
            {renderEmployeeTable(snapshotRows)}
          </>
        )}
      </div>
    );
  }

  if (!selectedId) {
    return (
      <div>
        <div className="flex items-center justify-between mb-6">
          <div>
            <h1 className="font-heading text-2xl font-extrabold text-bk-brown">{t("title")}</h1>
            <p className="text-xs text-bk-brown/60 mt-1">{t("subtitle")}</p>
          </div>
          {hasPermission("payroll.manage") && (
            <button
              type="button"
              onClick={() => setShowCreate((s) => !s)}
              className="flex items-center gap-1.5 text-sm font-semibold text-white rounded-lg px-4 py-2"
              style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}
            >
              {showCreate ? <X size={16} /> : <Plus size={16} />}
              {t("new_run")}
            </button>
          )}
        </div>

        {showCreate && (
          <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 mb-6">
            <h2 className="font-heading font-bold text-bk-brown mb-4">{t("create_title")}</h2>
            <div className="grid grid-cols-1 md:grid-cols-4 gap-3">
              <div>
                <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("field_frequency")}</label>
                <select
                  value={draft.pay_frequency}
                  onChange={(e) => setDraft({ ...draft, pay_frequency: e.target.value })}
                  className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5 text-sm"
                >
                  {PAY_FREQUENCIES.map((f) => (
                    <option key={f} value={f}>
                      {freqLabel(f)}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("field_period_start")}</label>
                <input type="date" value={draft.period_start} onChange={(e) => setDraft({ ...draft, period_start: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5 text-sm" />
              </div>
              <div>
                <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("field_period_end")}</label>
                <input type="date" value={draft.period_end} onChange={(e) => setDraft({ ...draft, period_end: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5 text-sm" />
              </div>
              <div>
                <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("field_pay_date")}</label>
                <input type="date" value={draft.pay_date} onChange={(e) => setDraft({ ...draft, pay_date: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5 text-sm" />
              </div>
            </div>
            <div className="mt-3">
              <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("field_notes")}</label>
              <input type="text" value={draft.notes} onChange={(e) => setDraft({ ...draft, notes: e.target.value })} className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5 text-sm" />
            </div>
            <div className="flex gap-2 mt-4">
              <button type="button" disabled={creating} onClick={handleCreate} className="text-sm font-semibold text-white rounded-lg px-4 py-2 disabled:opacity-50" style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}>
                {t("create_submit")}
              </button>
              <button type="button" onClick={() => setShowCreate(false)} className="text-sm font-semibold text-bk-brown border border-bk-brown/30 rounded-lg px-4 py-2">
                {t("create_cancel")}
              </button>
            </div>
          </div>
        )}

        <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 overflow-hidden">
          {loadingPeriods ? (
            <LoadingState />
          ) : periods.length === 0 ? (
            <EmptyState icon={Calculator} message={t("no_periods")} />
          ) : (
            <div className="divide-y divide-bk-brown/10">
              {periods.map((p) => (
                <button
                  key={p.id}
                  type="button"
                  onClick={() => openPeriod(p.id)}
                  className="w-full flex items-center justify-between px-5 py-4 text-left hover:bg-bk-cream2/40 transition"
                >
                  <div>
                    <p className="text-sm font-semibold text-bk-brown">
                      {p.period_start} {DASH} {p.period_end}
                    </p>
                    <p className="text-xs text-bk-brown/60 mt-0.5">{freqLabel(p.pay_frequency)}</p>
                  </div>
                  <div className="flex items-center gap-3">
                    {statusBadge(p.status)}
                    <ChevronRight size={16} className="text-bk-brown/30" />
                  </div>
                </button>
              ))}
            </div>
          )}
        </div>
      </div>
    );
  }

  return (
    <div>
      <button type="button" onClick={backToList} className="flex items-center gap-1.5 text-sm font-semibold text-bk-brown/70 hover:text-bk-brown mb-4">
        <ChevronLeft size={16} />
        {t("back_to_list")}
      </button>

      {selectedPeriod && (
        <>
          <div className="flex items-center justify-between mb-5 flex-wrap gap-3">
            <div>
              <h1 className="font-heading text-xl font-extrabold text-bk-brown">
                {selectedPeriod.period_start} {DASH} {selectedPeriod.period_end}
              </h1>
              <p className="text-xs text-bk-brown/60 mt-1">{freqLabel(selectedPeriod.pay_frequency)}</p>
            </div>
            <div className="flex items-center gap-2">
              {statusBadge(selectedPeriod.status)}
              <button type="button" onClick={() => loadDetail(selectedPeriod)} className="p-2 rounded-lg border border-bk-brown/20 text-bk-brown/60 hover:text-bk-brown">
                <RefreshCw size={14} />
              </button>
            </div>
          </div>

          <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 mb-6">
            {renderStepper(selectedPeriod.status)}
          </div>

          {detailLoading ? <LoadingState /> : renderActionPanel()}
        </>
      )}
    </div>
  );
}
