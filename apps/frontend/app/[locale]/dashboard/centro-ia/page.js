"use client";

import { useEffect, useState } from "react";
import { useTranslations } from "next-intl";
import { useParams } from "next/navigation";
import Link from "next/link";
import { ShieldAlert, DollarSign, AlarmClock } from "lucide-react";
import { apiFetch } from "../../../../lib/api";
import { LoadingState, EmptyState } from "../../../../lib/ui";

function severityClasses(sev) {
  if (sev === "high") return "bg-bk-red/10 text-bk-red";
  if (sev === "medium") return "bg-amber-100 text-amber-700";
  return "bg-bk-brown/10 text-bk-brown/60";
}

export default function CentroIAPage() {
  const t = useTranslations("ai_center");
  const tc = useTranslations("confianza");
  const params = useParams();
  const locale = params.locale;

  const [flags, setFlags] = useState([]);
  const [shiftAlerts, setShiftAlerts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    setLoading(true);
    Promise.all([
      apiFetch("/api/confianza-operativa/flags?resolved=false").catch(() => []),
      apiFetch("/api/shifts/alerts").catch(() => []),
    ])
      .then(([fl, sa]) => {
        setFlags(fl || []);
        setShiftAlerts(sa || []);
      })
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, []);

  function ruleLabel(code) {
    const key = "rule_" + code;
    const translated = tc(key);
    return translated === key ? code : translated;
  }

  function severityLabel(sev) {
    const key = "severity_" + sev;
    const translated = tc(key);
    return translated === key ? sev : translated;
  }

  const payrollFlags = flags.filter((f) => f.rule_code.startsWith("payroll_"));
  const confianzaFlags = flags.filter((f) => !f.rule_code.startsWith("payroll_"));

  function renderFlagList(list, emptyMessage) {
    if (list.length === 0) {
      return <p className="text-sm text-bk-brown/50 px-5 py-4">{emptyMessage}</p>;
    }
    return (
      <ul className="divide-y divide-bk-brown/10">
        {list.slice(0, 6).map((f) => (
          <li key={f.id} className="px-5 py-3 flex items-center justify-between">
            <div>
              <p className="font-semibold text-bk-brown text-sm">{ruleLabel(f.rule_code)}</p>
              <p className="text-xs text-bk-brown/50">
                {new Date(f.detected_at).toLocaleString()}
              </p>
            </div>
            <span className={"inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold " + severityClasses(f.severity)}>
              {severityLabel(f.severity)}
            </span>
          </li>
        ))}
      </ul>
    );
  }

  return (
    <div>
      <h1 className="font-heading text-2xl font-extrabold text-bk-brown mb-2">{t("title")}</h1>
      <p className="text-sm text-bk-brown/60 mb-6">{t("subtitle")}</p>

      {error && <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-4">{error}</p>}

      {loading ? (
        <LoadingState />
      ) : (
        <>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
            <Link
              href={`/${locale}/dashboard/confianza`}
              className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 flex items-center gap-4 hover:shadow-md transition"
            >
              <ShieldAlert className="text-bk-orange" size={28} />
              <div>
                <p className="text-2xl font-extrabold text-bk-brown">{confianzaFlags.length}</p>
                <p className="text-xs text-bk-brown/60">{t("card_confianza")}</p>
              </div>
            </Link>
            <Link
              href={`/${locale}/dashboard/confianza`}
              className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 flex items-center gap-4 hover:shadow-md transition"
            >
              <DollarSign className="text-bk-orange" size={28} />
              <div>
                <p className="text-2xl font-extrabold text-bk-brown">{payrollFlags.length}</p>
                <p className="text-xs text-bk-brown/60">{t("card_payroll")}</p>
              </div>
            </Link>
            <Link
              href={`/${locale}/dashboard/avisos-turno`}
              className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 flex items-center gap-4 hover:shadow-md transition"
            >
              <AlarmClock className="text-bk-orange" size={28} />
              <div>
                <p className="text-2xl font-extrabold text-bk-brown">{shiftAlerts.length}</p>
                <p className="text-xs text-bk-brown/60">{t("card_shift_alerts")}</p>
              </div>
            </Link>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 overflow-hidden">
              <div className="px-5 py-3 border-b border-bk-brown/10 flex items-center justify-between">
                <h2 className="font-heading font-bold text-bk-brown text-sm">{t("section_confianza")}</h2>
                <Link href="/dashboard/confianza" className="text-xs font-semibold text-bk-orange">
                  {t("view_all")}
                </Link>
              </div>
              {renderFlagList(confianzaFlags, t("no_confianza"))}
            </div>

            <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 overflow-hidden">
              <div className="px-5 py-3 border-b border-bk-brown/10 flex items-center justify-between">
                <h2 className="font-heading font-bold text-bk-brown text-sm">{t("section_payroll")}</h2>
                <Link href="/dashboard/confianza" className="text-xs font-semibold text-bk-orange">
                  {t("view_all")}
                </Link>
              </div>
              {renderFlagList(payrollFlags, t("no_payroll"))}
            </div>

            <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 overflow-hidden">
              <div className="px-5 py-3 border-b border-bk-brown/10 flex items-center justify-between">
                <h2 className="font-heading font-bold text-bk-brown text-sm">{t("section_shift_alerts")}</h2>
                <Link href="/dashboard/avisos-turno" className="text-xs font-semibold text-bk-orange">
                  {t("view_all")}
                </Link>
              </div>
              {shiftAlerts.length === 0 ? (
                <p className="text-sm text-bk-brown/50 px-5 py-4">{t("no_shift_alerts")}</p>
              ) : (
                <ul className="divide-y divide-bk-brown/10">
                  {shiftAlerts.slice(0, 6).map((a, i) => (
                    <li key={i} className="px-5 py-3">
                      <p className="font-semibold text-bk-brown text-sm">{a.employee_name}</p>
                      <p className="text-xs text-bk-brown/60">
                        {a.type === "no_show" ? t("alert_no_show") : t("alert_not_closed")} · {a.shift_name}
                      </p>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          </div>
        </>
      )}
    </div>
  );
}
