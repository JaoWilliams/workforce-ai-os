#!/bin/bash
# ============================================================
# UI/UX Nomina - Parte 3: pantalla Payroll Run (wow factor)
# ============================================================
# 1. Nueva pagina: nomina/corridas/page.js (wizard 7 etapas + anomalias)
# 2. Nuevo item en el sidebar (grupo NOMINA)
# 3. i18n: nav.payroll_runs + namespace nuevo payroll_run (ES/EN)
# 4. Verificacion estructural (balance de {}/() + funciones clave)
#    antes de gastar tiempo en el build.
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

mkdir -p "apps/frontend/app/[locale]/dashboard/nomina/corridas"

# ---------- 1. nueva pagina: corridas/page.js ----------
python3 << 'PYEOF'
path = "apps/frontend/app/[locale]/dashboard/nomina/corridas/page.js"

new_content = '''"use client";
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

function emptyDraft() {
  return { pay_frequency: "mensual", period_start: "", period_end: "", pay_date: "", notes: "" };
}

function formatMoney(amount, currency) {
  if (amount == null) return "\\u2014";
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
    return (
      <span className={"inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[11px] font-semibold " + (colors[status] || "bg-bk-brown/10 text-bk-brown/70")}>
        {t(`status_${status}`)}
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
                <td className="px-4 py-2.5 font-medium text-bk-brown">{r.employee_name || "\\u2014"}</td>
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
                      {p.period_start} \\u2014 {p.period_end}
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
                {selectedPeriod.period_start} \\u2014 {selectedPeriod.period_end}
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
'''

with open(path, "w", encoding="utf-8") as f:
    f.write(new_content)

# ---------- verificacion estructural ----------
with open(path, encoding="utf-8") as f:
    check = f.read()

problemas = []
open_braces = check.count("{")
close_braces = check.count("}")
if open_braces != close_braces:
    problemas.append(f"llaves desbalanceadas: {{ {open_braces} vs }} {close_braces}")
open_parens = check.count("(")
close_parens = check.count(")")
if open_parens != close_parens:
    problemas.append(f"parentesis desbalanceados: ( {open_parens} vs ) {close_parens}")
for marker in [
    "export default function PayrollRunsPage",
    "function renderStepper",
    "function renderAnomalyQueue",
    "function renderEmployeeTable",
    "function renderActionPanel",
    "function handleTransition",
    "function handleCreate",
    "const STATUS_ORDER",
    "const RULE_ICONS",
]:
    if marker not in check:
        problemas.append(f"falta: {marker}")

line_count = check.count("\n") + 1
if not (400 <= line_count <= 520):
    problemas.append(f"cantidad de lineas sospechosa: {line_count} (esperaba ~440-460)")

if problemas:
    print("XXX VERIFICACION FALLO XXX")
    for p in problemas:
        print(" -", p)
    raise SystemExit(1)

print(f"OK: corridas/page.js escrito y verificado ({line_count} lineas, estructura intacta)")
PYEOF

# ---------- 2. agregar item al sidebar (grupo NOMINA) ----------
python3 << 'PYEOF'
path = "apps/frontend/app/[locale]/dashboard/layout.js"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

anchor = '''  {
    key: "nomina",
    icon: Wallet,
    items: [
      { key: "payroll", href: "/nomina", permission: "payroll.view" },
    ],
  },'''
assert anchor in src, "ANCHOR NOT FOUND: grupo nomina en NAV_GROUPS"
assert src.count(anchor) == 1, "ANCHOR NOT UNIQUE: grupo nomina en NAV_GROUPS"

nuevo = '''  {
    key: "nomina",
    icon: Wallet,
    items: [
      { key: "payroll", href: "/nomina", permission: "payroll.view" },
      { key: "payroll_runs", href: "/nomina/corridas", permission: "payroll.view" },
    ],
  },'''
src = src.replace(anchor, nuevo, 1)

with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("OK: item 'payroll_runs' agregado al grupo NOMINA del sidebar")
PYEOF

# ---------- 3. i18n: nav.payroll_runs + namespace payroll_run (ES/EN) ----------
python3 << 'PYEOF'
import json

nav_es = {"payroll_runs": "Corridas de Nómina"}
nav_en = {"payroll_runs": "Payroll Runs"}

payroll_run_es = {
    "title": "Corridas de Nómina",
    "subtitle": "Orquestación y auto-validación del pago de planilla",
    "new_run": "Nueva corrida",
    "back_to_list": "Volver a corridas",
    "no_periods": "Todavía no hay corridas creadas",
    "create_title": "Nueva corrida de nómina",
    "field_frequency": "Frecuencia de pago",
    "field_period_start": "Inicio del período",
    "field_period_end": "Fin del período",
    "field_pay_date": "Fecha de pago",
    "field_notes": "Notas (opcional)",
    "create_submit": "Crear corrida",
    "create_cancel": "Cancelar",
    "create_ok_toast": "Corrida creada correctamente",
    "status_draft": "Borrador",
    "status_validado": "Validado",
    "status_calculado": "Calculado",
    "status_aprobado": "Aprobado",
    "status_pagado": "Pagado",
    "status_contabilizado": "Contabilizado",
    "status_archivo_bancario": "Archivo Bancario",
    "step_draft_title": "Borrador",
    "step_draft_desc": "El período está creado pero todavía no se validaron los catálogos necesarios para calcular la nómina.",
    "step_draft_action": "Validar catálogos",
    "step_validado_title": "Validado",
    "step_validado_desc": "Los catálogos necesarios (tramos de renta, créditos, CCSS, horas estándar) están completos. Listo para calcular.",
    "step_validado_action": "Calcular nómina",
    "step_calculado_title": "Calculado",
    "step_calculado_desc": "El resultado por empleado quedó congelado (snapshot inmutable). Resolvé todas las anomalías detectadas antes de aprobar.",
    "step_calculado_action": "Aprobar corrida",
    "step_calculado_blocked": "Hay {count} anomalía(s) sin resolver",
    "step_aprobado_title": "Aprobado",
    "step_aprobado_desc": "La corrida fue aprobada. Confirmá manualmente cuando el pago haya salido del banco.",
    "step_aprobado_action": "Marcar como pagado",
    "step_pagado_title": "Pagado",
    "step_pagado_desc": "Generá el asiento contable de planilla para poder contabilizar este período.",
    "step_pagado_action_generate": "Generar asiento contable",
    "step_pagado_action_next": "Contabilizar",
    "step_contabilizado_title": "Contabilizado",
    "step_contabilizado_desc": "Generá el archivo bancario para el depósito de planilla.",
    "step_contabilizado_action_generate": "Generar archivo bancario",
    "step_contabilizado_action_next": "Cerrar corrida",
    "step_archivo_bancario_title": "Archivo Bancario",
    "step_archivo_bancario_desc": "Corrida completa. El archivo bancario está listo para subir al banco.",
    "step_archivo_bancario_download": "Descargar archivo TXT",
    "snapshot_title": "Resultado por empleado (congelado)",
    "net_preview_title": "Vista previa del cálculo",
    "anomaly_queue_title": "Cola de anomalías",
    "anomaly_none": "Sin anomalías detectadas",
    "anomaly_resolve": "Resolver",
    "anomaly_resolved_toast": "Anomalía marcada como resuelta",
    "rule_payroll_net_zero_or_negative": "Neto cero o negativo",
    "rule_payroll_paid_after_termination": "Pago después de terminación",
    "rule_payroll_net_deviation": "Desviación de neto",
    "rule_payroll_overtime_outlier": "Horas extra atípicas",
    "rule_payroll_branch_net_outlier": "Sucursal atípica",
    "rule_payroll_bank_account_changed_before_payment": "Cuenta bancaria cambiada",
    "severity_high": "Alta",
    "severity_medium": "Media",
    "col_employee": "Empleado",
    "col_gross": "Bruto",
    "col_ccss": "CCSS",
    "col_renta": "Renta",
    "col_net": "Neto",
    "no_data": "No hay datos para mostrar",
    "journal_entry_title": "Asiento contable generado",
    "journal_entry_total": "Total",
    "bank_file_title": "Archivo bancario generado",
    "bank_file_rows": "{count} empleado(s) incluidos",
    "bank_file_missing": "{count} empleado(s) excluidos",
    "transition_ok_toast": "Estado actualizado correctamente",
    "generating": "Generando...",
    "error_invalid_transition": "No se puede pasar directamente a este estado.",
    "error_missing_catalogs": "Faltan catálogos necesarios:",
    "error_blocked_rows": "{count} empleado(s) tienen datos bloqueados. Revisá Nómina Bruta.",
    "error_unresolved_flags": "Hay {count} anomalía(s) sin resolver.",
    "error_accounting_entry_missing": "Todavía no se generó el asiento contable.",
    "error_bank_file_missing": "Todavía no se generó el archivo bancario.",
    "error_bank_config_missing": "Falta configurar la glosa del archivo bancario.",
    "error_no_valid_rows": "Ningún empleado válido para el archivo bancario.",
    "error_no_rows": "No hay filas de nómina calculables para este período.",
    "error_missing_accounts": "Faltan cuentas contables configuradas.",
    "error_zero_amount": "El monto total calculado es cero.",
    "error_unbalanced": "El asiento no cuadra (debe distinto de haber).",
    "error_generic": "No se pudo completar la acción.",
}

payroll_run_en = {
    "title": "Payroll Runs",
    "subtitle": "Orchestration and auto-validation of the payroll run",
    "new_run": "New run",
    "back_to_list": "Back to runs",
    "no_periods": "No runs created yet",
    "create_title": "New payroll run",
    "field_frequency": "Pay frequency",
    "field_period_start": "Period start",
    "field_period_end": "Period end",
    "field_pay_date": "Pay date",
    "field_notes": "Notes (optional)",
    "create_submit": "Create run",
    "create_cancel": "Cancel",
    "create_ok_toast": "Run created successfully",
    "status_draft": "Draft",
    "status_validado": "Validated",
    "status_calculado": "Calculated",
    "status_aprobado": "Approved",
    "status_pagado": "Paid",
    "status_contabilizado": "Posted",
    "status_archivo_bancario": "Bank File",
    "step_draft_title": "Draft",
    "step_draft_desc": "The period is created but the required catalogs to calculate payroll haven't been validated yet.",
    "step_draft_action": "Validate catalogs",
    "step_validado_title": "Validated",
    "step_validado_desc": "Required catalogs (tax brackets, credits, CCSS, standard hours) are complete. Ready to calculate.",
    "step_validado_action": "Calculate payroll",
    "step_calculado_title": "Calculated",
    "step_calculado_desc": "The per-employee result was frozen (immutable snapshot). Resolve all detected anomalies before approving.",
    "step_calculado_action": "Approve run",
    "step_calculado_blocked": "{count} unresolved anomaly(ies)",
    "step_aprobado_title": "Approved",
    "step_aprobado_desc": "The run was approved. Confirm manually once the payment has left the bank.",
    "step_aprobado_action": "Mark as paid",
    "step_pagado_title": "Paid",
    "step_pagado_desc": "Generate the payroll journal entry to be able to post this period.",
    "step_pagado_action_generate": "Generate journal entry",
    "step_pagado_action_next": "Post",
    "step_contabilizado_title": "Posted",
    "step_contabilizado_desc": "Generate the bank file for the payroll deposit.",
    "step_contabilizado_action_generate": "Generate bank file",
    "step_contabilizado_action_next": "Close run",
    "step_archivo_bancario_title": "Bank File",
    "step_archivo_bancario_desc": "Run complete. The bank file is ready to upload to the bank.",
    "step_archivo_bancario_download": "Download TXT file",
    "snapshot_title": "Per-employee result (frozen)",
    "net_preview_title": "Calculation preview",
    "anomaly_queue_title": "Anomaly queue",
    "anomaly_none": "No anomalies detected",
    "anomaly_resolve": "Resolve",
    "anomaly_resolved_toast": "Anomaly marked as resolved",
    "rule_payroll_net_zero_or_negative": "Zero or negative net",
    "rule_payroll_paid_after_termination": "Paid after termination",
    "rule_payroll_net_deviation": "Net deviation",
    "rule_payroll_overtime_outlier": "Overtime outlier",
    "rule_payroll_branch_net_outlier": "Branch outlier",
    "rule_payroll_bank_account_changed_before_payment": "Bank account changed",
    "severity_high": "High",
    "severity_medium": "Medium",
    "col_employee": "Employee",
    "col_gross": "Gross",
    "col_ccss": "CCSS",
    "col_renta": "Income tax",
    "col_net": "Net",
    "no_data": "No data to show",
    "journal_entry_title": "Journal entry generated",
    "journal_entry_total": "Total",
    "bank_file_title": "Bank file generated",
    "bank_file_rows": "{count} employee(s) included",
    "bank_file_missing": "{count} employee(s) excluded",
    "transition_ok_toast": "Status updated successfully",
    "generating": "Generating...",
    "error_invalid_transition": "Cannot move directly to this status.",
    "error_missing_catalogs": "Missing required catalogs:",
    "error_blocked_rows": "{count} employee(s) have blocked data. Check Gross Payroll.",
    "error_unresolved_flags": "{count} unresolved anomaly(ies).",
    "error_accounting_entry_missing": "The journal entry hasn't been generated yet.",
    "error_bank_file_missing": "The bank file hasn't been generated yet.",
    "error_bank_config_missing": "The bank file description is not configured.",
    "error_no_valid_rows": "No valid employees for the bank file.",
    "error_no_rows": "No calculable payroll rows for this period.",
    "error_missing_accounts": "Missing configured accounting accounts.",
    "error_zero_amount": "The calculated total amount is zero.",
    "error_unbalanced": "The entry doesn't balance (debit != credit).",
    "error_generic": "Could not complete the action.",
}

for path, nav_new, section_new in [
    ("apps/frontend/messages/es.json", nav_es, payroll_run_es),
    ("apps/frontend/messages/en.json", nav_en, payroll_run_en),
]:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    added_nav = 0
    for k, v in nav_new.items():
        if k not in data.get("nav", {}):
            data["nav"][k] = v
            added_nav += 1
    data.setdefault("payroll_run", {})
    added_section = 0
    for k, v in section_new.items():
        if k not in data["payroll_run"]:
            data["payroll_run"][k] = v
            added_section += 1
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"OK: {path} - nav +{added_nav}, payroll_run +{added_section}")
PYEOF

# ---------- 4. rebuild ----------
echo "=== rebuild frontend ==="
docker compose build --no-cache frontend
docker compose up -d frontend
sleep 5
docker compose logs frontend --tail 30

echo "=== FIN Parte 3 ==="
