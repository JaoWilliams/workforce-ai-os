"use client";

import { useEffect, useMemo, useState } from "react";
import { useTranslations } from "next-intl";
import {
  Users,
  Wifi,
  Clock,
  AlertTriangle,
  ShieldAlert,
  Flame,
  CalendarClock,
  ClipboardList,
  AlarmClock,
} from "lucide-react";
import {
  ResponsiveContainer,
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  BarChart,
  Bar,
  Cell,
  PieChart,
  Pie,
} from "recharts";
import { apiFetch } from "../../../lib/api";

const COLOR_ORANGE = "#FF8732";
const COLOR_RED = "#F5233B";
const COLOR_BROWN = "#502314";
const COLOR_CREAM2 = "#EDE6D6";
const COLOR_GREEN = "#1F9D55";

export default function DashboardHome() {
  const t = useTranslations("dashboard");

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const [employees, setEmployees] = useState([]);
  const [branches, setBranches] = useState([]);
  const [devices, setDevices] = useState([]);
  const [attendance, setAttendance] = useState([]);
  const [pendingExceptions, setPendingExceptions] = useState([]);
  const [flags, setFlags] = useState([]);
  const [shiftTemplates, setShiftTemplates] = useState([]);
  const [shiftAssignments, setShiftAssignments] = useState([]);
  const [shiftAlerts, setShiftAlerts] = useState([]);

  useEffect(() => {
    setLoading(true);
    Promise.all([
      apiFetch("/api/employees"),
      apiFetch("/api/branches"),
      apiFetch("/api/devices"),
      apiFetch("/api/attendance"),
      apiFetch("/api/exceptions?status=pending"),
      apiFetch("/api/confianza-operativa/flags"),
      apiFetch("/api/shifts"),
      apiFetch("/api/shifts/assignments"),
      apiFetch("/api/shifts/alerts").catch(() => []),
    ])
      .then(([emp, br, dev, att, exc, fl, st, sa, sal]) => {
        setEmployees(emp);
        setBranches(br);
        setDevices(dev);
        setAttendance(att);
        setPendingExceptions(exc);
        setFlags(fl);
        setShiftTemplates(st);
        setShiftAssignments(sa);
        setShiftAlerts(sal);
      })
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, []);

  function employeeName(id) {
    const e = employees.find((x) => x.id === id);
    return e ? e.first_name + " " + e.last_name : id;
  }

  function isToday(isoString) {
    const d = new Date(isoString);
    const now = new Date();
    return d.toDateString() === now.toDateString();
  }

  const activeEmployees = employees.filter((e) => e.active).length;
  const devicesOnline = devices.filter((d) => d.status === "online").length;
  const checkinsToday = attendance.filter((a) => isToday(a.recorded_at)).length;
  const exceptionsPending = pendingExceptions.length;
  const flagsUnresolved = flags.filter((f) => !f.resolved).length;
  const flagsHigh = flags.filter((f) => !f.resolved && f.severity === "high").length;
  const onboardingIncomplete = employees.filter(
    (e) => e.active && e.onboarding_missing && e.onboarding_missing.length > 0
  ).length;

  const kpis = [
    { label: t("stat_employees_active"), value: activeEmployees, icon: Users, color: COLOR_BROWN },
    { label: t("stat_devices_online"), value: devicesOnline, icon: Wifi, color: COLOR_BROWN },
    { label: t("stat_checkins_today"), value: checkinsToday, icon: Clock, color: COLOR_BROWN },
    { label: t("stat_exceptions_pending"), value: exceptionsPending, icon: AlertTriangle, color: COLOR_ORANGE },
    { label: t("stat_flags_unresolved"), value: flagsUnresolved, icon: ShieldAlert, color: COLOR_ORANGE },
    { label: t("stat_flags_high"), value: flagsHigh, icon: Flame, color: COLOR_RED },
    { label: t("stat_onboarding_incomplete"), value: onboardingIncomplete, icon: ClipboardList, color: COLOR_ORANGE },
    { label: t("stat_shift_alerts"), value: shiftAlerts.length, icon: AlarmClock, color: COLOR_ORANGE },
  ];

  const checkinsTrend = useMemo(() => {
    const days = [];
    for (let i = 13; i >= 0; i--) {
      const d = new Date();
      d.setDate(d.getDate() - i);
      days.push(d);
    }
    return days.map((d) => {
      const dayStr = d.toLocaleDateString("es-CR", { day: "2-digit", month: "2-digit" });
      const recordsForDay = attendance.filter(
        (a) => new Date(a.recorded_at).toDateString() === d.toDateString()
      );
      return {
        day: dayStr,
        entrada: recordsForDay.filter((a) => a.type === "entrada").length,
        salida: recordsForDay.filter((a) => a.type === "salida").length,
      };
    });
  }, [attendance]);

  const today = new Date().toISOString().slice(0, 10);
  const shiftCoverage = useMemo(() => {
    return shiftTemplates.map((tpl) => {
      const assigned = shiftAssignments.filter(
        (a) =>
          a.shift_template_id === tpl.id &&
          a.start_date <= today &&
          (!a.end_date || a.end_date >= today)
      ).length;
      return {
        name: tpl.name,
        [t("chart_assigned")]: assigned,
        [t("chart_min_required")]: tpl.min_coverage,
        covered: assigned >= tpl.min_coverage,
      };
    });
  }, [shiftTemplates, shiftAssignments, today, t]);

  const understaffedCount = shiftCoverage.filter((s) => !s.covered).length;

  function ruleLabel(code) {
    const key = "rule_" + code;
    const translated = t(key);
    return translated === key ? code : translated;
  }

  const flagsByRule = useMemo(() => {
    const counts = {};
    flags.forEach((f) => {
      counts[f.rule_code] = (counts[f.rule_code] || 0) + 1;
    });
    const palette = [COLOR_RED, COLOR_ORANGE, COLOR_BROWN, COLOR_GREEN];
    return Object.entries(counts).map(([code, count], idx) => ({
      name: ruleLabel(code),
      value: count,
      color: palette[idx % palette.length],
    }));
  }, [flags, t]);

  const employeesByBranch = branches.map((b) => ({
    name: b.name,
    empleados: b.employee_count,
  }));

  const activity = [
    ...attendance.map((a) => ({
      kind: "checkin",
      timestamp: a.recorded_at,
      label: t("activity_checkin") + ": " + employeeName(a.employee_id) + " (" + a.type + ")",
    })),
    ...flags
      .filter((f) => !f.resolved)
      .map((f) => ({
        kind: "flag",
        timestamp: f.detected_at,
        label: t("activity_flag") + ": " + employeeName(f.employee_id) + " — " + ruleLabel(f.rule_code),
      })),
    ...pendingExceptions.map((e) => ({
      kind: "exception",
      timestamp: e.created_at,
      label: t("activity_exception") + ": " + employeeName(e.employee_id) + " — " + e.exception_type,
    })),
  ]
    .sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp))
    .slice(0, 8);

  return (
    <div>
      <p className="text-[10px] font-semibold text-bk-orange uppercase tracking-[3px] mb-2">
        Burger King Costa Rica
      </p>
      <h1 className="font-heading text-2xl font-extrabold text-bk-brown mb-3">
        {t("welcome_title")}
      </h1>
      <p className="text-bk-brown/70 max-w-xl leading-relaxed mb-8">{t("welcome_body")}</p>

      {error && (
        <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-4">{error}</p>
      )}

      {loading ? (
        <p className="text-sm text-bk-brown/60">...</p>
      ) : (
        <>
          <div className="grid grid-cols-2 md:grid-cols-3 gap-4 mb-6">
            {kpis.map((s) => {
              const Icon = s.icon;
              return (
                <div
                  key={s.label}
                  className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 flex items-start justify-between"
                >
                  <div>
                    <p className="font-heading text-3xl font-extrabold" style={{ color: s.color }}>
                      {s.value}
                    </p>
                    <p className="text-xs text-bk-brown/60 mt-1">{s.label}</p>
                  </div>
                  <Icon size={22} color={s.color} strokeWidth={2} />
                </div>
              );
            })}
          </div>

          {understaffedCount > 0 && (
            <div className="flex items-center gap-3 bg-bk-red/10 border border-bk-red/20 rounded-xl px-5 py-3 mb-6">
              <CalendarClock size={20} color={COLOR_RED} />
              <p className="text-sm text-bk-red font-medium">
                {understaffedCount} {t("coverage_gap_alert")}
              </p>
            </div>
          )}

          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
            <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5">
              <h2 className="font-heading font-bold text-bk-brown mb-4 text-sm">
                {t("chart_checkins_trend")}
              </h2>
              <ResponsiveContainer width="100%" height={240}>
                <AreaChart data={checkinsTrend}>
                  <defs>
                    <linearGradient id="colorEntrada" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor={COLOR_ORANGE} stopOpacity={0.4} />
                      <stop offset="95%" stopColor={COLOR_ORANGE} stopOpacity={0} />
                    </linearGradient>
                    <linearGradient id="colorSalida" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor={COLOR_BROWN} stopOpacity={0.4} />
                      <stop offset="95%" stopColor={COLOR_BROWN} stopOpacity={0} />
                    </linearGradient>
                  </defs>
                  <CartesianGrid strokeDasharray="3 3" stroke={COLOR_CREAM2} />
                  <XAxis dataKey="day" tick={{ fontSize: 11, fill: COLOR_BROWN }} />
                  <YAxis allowDecimals={false} tick={{ fontSize: 11, fill: COLOR_BROWN }} />
                  <Tooltip />
                  <Legend wrapperStyle={{ fontSize: 12 }} />
                  <Area
                    type="monotone"
                    dataKey="entrada"
                    name={t("chart_entrada")}
                    stroke={COLOR_ORANGE}
                    fill="url(#colorEntrada)"
                    strokeWidth={2}
                  />
                  <Area
                    type="monotone"
                    dataKey="salida"
                    name={t("chart_salida")}
                    stroke={COLOR_BROWN}
                    fill="url(#colorSalida)"
                    strokeWidth={2}
                  />
                </AreaChart>
              </ResponsiveContainer>
            </div>

            <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5">
              <h2 className="font-heading font-bold text-bk-brown mb-4 text-sm">
                {t("chart_shift_coverage")}
              </h2>
              {shiftCoverage.length === 0 ? (
                <p className="text-sm text-bk-brown/60">{t("no_data")}</p>
              ) : (
                <ResponsiveContainer width="100%" height={240}>
                  <BarChart data={shiftCoverage} layout="vertical" margin={{ left: 20 }}>
                    <CartesianGrid strokeDasharray="3 3" stroke={COLOR_CREAM2} />
                    <XAxis type="number" allowDecimals={false} tick={{ fontSize: 11, fill: COLOR_BROWN }} />
                    <YAxis type="category" dataKey="name" tick={{ fontSize: 11, fill: COLOR_BROWN }} width={110} />
                    <Tooltip />
                    <Legend wrapperStyle={{ fontSize: 12 }} />
                    <Bar dataKey={t("chart_min_required")} fill={COLOR_CREAM2} radius={[0, 4, 4, 0]} />
                    <Bar dataKey={t("chart_assigned")} radius={[0, 4, 4, 0]}>
                      {shiftCoverage.map((entry, idx) => (
                        <Cell key={idx} fill={entry.covered ? COLOR_GREEN : COLOR_RED} />
                      ))}
                    </Bar>
                  </BarChart>
                </ResponsiveContainer>
              )}
            </div>
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
            <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5">
              <h2 className="font-heading font-bold text-bk-brown mb-4 text-sm">
                {t("chart_flags_by_rule")}
              </h2>
              {flagsByRule.length === 0 ? (
                <p className="text-sm text-bk-brown/60">{t("no_data")}</p>
              ) : (
                <ResponsiveContainer width="100%" height={240}>
                  <PieChart>
                    <Pie
                      data={flagsByRule}
                      dataKey="value"
                      nameKey="name"
                      innerRadius={55}
                      outerRadius={85}
                      paddingAngle={3}
                    >
                      {flagsByRule.map((entry, idx) => (
                        <Cell key={idx} fill={entry.color} />
                      ))}
                    </Pie>
                    <Tooltip />
                    <Legend wrapperStyle={{ fontSize: 11 }} layout="vertical" verticalAlign="middle" align="right" />
                  </PieChart>
                </ResponsiveContainer>
              )}
            </div>

            <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5">
              <h2 className="font-heading font-bold text-bk-brown mb-4 text-sm">
                {t("chart_employees_by_branch")}
              </h2>
              <ResponsiveContainer width="100%" height={240}>
                <BarChart data={employeesByBranch}>
                  <CartesianGrid strokeDasharray="3 3" stroke={COLOR_CREAM2} />
                  <XAxis dataKey="name" tick={{ fontSize: 10, fill: COLOR_BROWN }} />
                  <YAxis allowDecimals={false} tick={{ fontSize: 11, fill: COLOR_BROWN }} />
                  <Tooltip />
                  <Bar dataKey="empleados" fill={COLOR_ORANGE} radius={[4, 4, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            </div>
          </div>

          <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 max-w-2xl">
            <h2 className="font-heading font-bold text-bk-brown mb-4">{t("recent_activity")}</h2>
            {activity.length === 0 ? (
              <p className="text-sm text-bk-brown/60">{t("no_activity")}</p>
            ) : (
              <ul className="divide-y divide-bk-brown/10">
                {activity.map((item, idx) => (
                  <li key={idx} className="py-2.5 text-sm flex items-center justify-between">
                    <span className="text-bk-brown">{item.label}</span>
                    <span className="text-xs text-bk-brown/50">
                      {new Date(item.timestamp).toLocaleString()}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </>
      )}
    </div>
  );
}
