"use client";

import { useEffect, useState } from "react";
import { useTranslations } from "next-intl";
import { ShieldAlert } from "lucide-react";
import { apiFetch } from "../../../../lib/api";
import { useToast } from "../../../../lib/toast";
import { LoadingState, EmptyState } from "../../../../lib/ui";

export default function ConfianzaPage() {
  const t = useTranslations("confianza");
  const { showToast } = useToast();
  const [flags, setFlags] = useState([]);
  const [employees, setEmployees] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [message, setMessage] = useState(null);
  const [filter, setFilter] = useState("all");
  const [resolvingId, setResolvingId] = useState(null);

  useEffect(() => {
    load();
    apiFetch("/api/employees").then(setEmployees).catch(() => {});
  }, []);

  function load() {
    setLoading(true);
    apiFetch("/api/confianza-operativa/flags")
      .then(setFlags)
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }

  function employeeName(id) {
    const e = employees.find((x) => x.id === id);
    return e ? e.first_name + " " + e.last_name : t("employee_unknown");
  }

  function ruleLabel(code) {
    const key = "rule_" + code;
    const translated = t(key);
    return translated === key ? code : translated;
  }

  function severityLabel(sev) {
    const key = "severity_" + sev;
    const translated = t(key);
    return translated === key ? sev : translated;
  }

  function severityClasses(sev) {
    if (sev === "high") {
      return { badge: "bg-bk-red/10 text-bk-red", border: "border-l-4 border-bk-red" };
    }
    if (sev === "medium") {
      return { badge: "bg-bk-orange/10 text-bk-orange", border: "border-l-4 border-bk-orange" };
    }
    return { badge: "bg-yellow-100 text-yellow-700", border: "border-l-4 border-yellow-400" };
  }

  async function handleResolveToggle(flag) {
    setResolvingId(flag.id);
    setError(null);
    setMessage(null);
    try {
      await apiFetch("/api/confianza-operativa/flags/" + flag.id, {
        method: "PATCH",
        body: JSON.stringify({ resolved: !flag.resolved }),
      });
      showToast(flag.resolved ? t("flag_reopened_toast") : t("flag_resolved_toast"));
      load();
    } catch (err) {
      setError(err.message);
      showToast(err.message, "error");
    } finally {
      setResolvingId(null);
    }
  }

  const total = flags.length;
  const pending = flags.filter((f) => !f.resolved).length;
  const resolved = flags.filter((f) => f.resolved).length;
  const highSeverity = flags.filter((f) => f.severity === "high" && !f.resolved).length;

  const displayed = flags.filter((f) => {
    if (filter === "pending") return !f.resolved;
    if (filter === "resolved") return f.resolved;
    return true;
  });

  return (
    <div>
      <h1 className="font-heading text-2xl font-extrabold text-bk-brown mb-2">{t("title")}</h1>
      <p className="text-sm text-bk-brown/60 mb-6 max-w-2xl">{t("subtitle")}</p>

      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
        <div className="bg-white rounded-xl border border-bk-brown/10 p-4">
          <p className="text-2xl font-heading font-extrabold text-bk-brown">{total}</p>
          <p className="text-xs text-bk-brown/60 mt-1">{t("stat_total")}</p>
        </div>
        <div className="bg-white rounded-xl border border-bk-brown/10 p-4">
          <p className="text-2xl font-heading font-extrabold text-bk-orange">{pending}</p>
          <p className="text-xs text-bk-brown/60 mt-1">{t("stat_pending")}</p>
        </div>
        <div className="bg-white rounded-xl border border-bk-brown/10 p-4">
          <p className="text-2xl font-heading font-extrabold text-green-600">{resolved}</p>
          <p className="text-xs text-bk-brown/60 mt-1">{t("stat_resolved")}</p>
        </div>
        <div className="bg-bk-red/5 rounded-xl border border-bk-red/30 p-4">
          <p className="text-2xl font-heading font-extrabold text-bk-red">{highSeverity}</p>
          <p className="text-xs text-bk-brown/60 mt-1">{t("stat_high")}</p>
        </div>
      </div>

      <div className="flex gap-2 mb-6">
        {["all", "pending", "resolved"].map((f) => (
          <button
            key={f}
            onClick={() => setFilter(f)}
            className={
              filter === f
                ? "text-xs font-semibold rounded-full px-4 py-1.5 text-white"
                : "text-xs font-semibold rounded-full px-4 py-1.5 border border-bk-brown/20 text-bk-brown/70"
            }
            style={
              filter === f
                ? { background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }
                : {}
            }
          >
            {t("filter_" + f)}
          </button>
        ))}
      </div>

      {error && (
        <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-4">{error}</p>
      )}

      {loading ? (
        <LoadingState />
      ) : displayed.length === 0 ? (
        <EmptyState icon={ShieldAlert} message={t("no_flags")} />
      ) : (
        <div className="space-y-4">
          {displayed.map((f) => {
            const cls = severityClasses(f.severity);
            return (
              <div key={f.id} className={"bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 " + cls.border}>
                <div className="flex items-start justify-between gap-4 mb-2">
                  <div>
                    <div className="flex items-center gap-2 mb-1">
                      <span className={"inline-block rounded-full px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide " + cls.badge}>
                        {severityLabel(f.severity)}
                      </span>
                      <span
                        className={
                          f.resolved
                            ? "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-green-100 text-green-700"
                            : "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-bk-brown/10 text-bk-brown/60"
                        }
                      >
                        {f.resolved ? t("resolved_badge") : t("pending_badge")}
                      </span>
                    </div>
                    <p className="font-heading font-bold text-bk-brown">{ruleLabel(f.rule_code)}</p>
                    <p className="text-xs text-bk-brown/60 mt-0.5">
                      {employeeName(f.employee_id)} · {t("detected_at")}: {f.detected_at}
                    </p>
                  </div>
                  <button
                    onClick={() => handleResolveToggle(f)}
                    disabled={resolvingId === f.id}
                    className={
                      f.resolved
                        ? "text-xs font-semibold text-bk-brown border border-bk-brown/30 rounded-lg px-3 py-1.5 disabled:opacity-50 shrink-0"
                        : "text-xs font-semibold text-white rounded-lg px-3 py-1.5 disabled:opacity-50 shrink-0"
                    }
                    style={
                      f.resolved
                        ? {}
                        : { background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }
                    }
                  >
                    {f.resolved ? t("reopen") : t("resolve")}
                  </button>
                </div>
                {f.details && f.details.reason && (
                  <p className="text-sm text-bk-brown/80 mt-2">{f.details.reason}</p>
                )}
                {f.details && f.details.gap_minutes != null && f.details.threshold_minutes != null && (
                  <p className="text-xs text-bk-brown/50 mt-2 font-mono">
                    {t("gap_detail", { gap: f.details.gap_minutes, threshold: f.details.threshold_minutes })}
                  </p>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
