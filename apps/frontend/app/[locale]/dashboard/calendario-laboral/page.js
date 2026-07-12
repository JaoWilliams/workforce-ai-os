"use client";
import { useEffect, useMemo, useState } from "react";
import { useTranslations } from "next-intl";
import { apiFetch } from "../../../../lib/api";
import { useToast } from "../../../../lib/toast";
import { LoadingState } from "../../../../lib/ui";

const CHIP_COLORS = [
  "bg-bk-orange/20 border-bk-orange/40 text-bk-brown",
  "bg-bk-red/15 border-bk-red/40 text-bk-brown",
  "bg-emerald-100 border-emerald-300 text-emerald-900",
  "bg-sky-100 border-sky-300 text-sky-900",
  "bg-violet-100 border-violet-300 text-violet-900",
  "bg-amber-100 border-amber-300 text-amber-900",
];

function rangesOverlap(aStart, aEnd, bStart, bEnd) {
  const aEndVal = aEnd || "9999-12-31";
  const bEndVal = bEnd || "9999-12-31";
  return aStart <= bEndVal && bStart <= aEndVal;
}

function toIsoDate(d) {
  return d.toISOString().slice(0, 10);
}

function mondayOf(date) {
  const d = new Date(date);
  const day = d.getDay();
  const diff = day === 0 ? -6 : 1 - day;
  d.setDate(d.getDate() + diff);
  d.setHours(0, 0, 0, 0);
  return d;
}

export default function CalendarioLaboralPage() {
  const t = useTranslations("work_calendar_page");
  const { showToast } = useToast();

  const [templates, setTemplates] = useState([]);
  const [branches, setBranches] = useState([]);
  const [employees, setEmployees] = useState([]);
  const [assignments, setAssignments] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const [weekStart, setWeekStart] = useState(() => mondayOf(new Date()));
  const [branchFilter, setBranchFilter] = useState("");
  const [searchQuery, setSearchQuery] = useState("");

  useEffect(() => {
    loadAll();
  }, []);

  function loadAll() {
    setLoading(true);
    Promise.all([
      apiFetch("/api/shifts"),
      apiFetch("/api/branches"),
      apiFetch("/api/employees"),
      apiFetch("/api/shifts/assignments"),
    ])
      .then(([tpl, br, emp, asg]) => {
        setTemplates(tpl);
        setBranches(br);
        setEmployees(emp);
        setAssignments(asg);
      })
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }

  function reloadAssignments() {
    apiFetch("/api/shifts/assignments").then(setAssignments).catch(() => {});
  }

  const weekDays = useMemo(() => {
    const days = [];
    for (let i = 0; i < 7; i++) {
      const d = new Date(weekStart);
      d.setDate(d.getDate() + i);
      days.push(d);
    }
    return days;
  }, [weekStart]);

  function branchName(id) {
    const b = branches.find((x) => x.id === id);
    return b ? b.name : id;
  }
  function templateName(id) {
    const tpl = templates.find((x) => x.id === id);
    return tpl ? tpl.name : id;
  }
  function templateColor(id) {
    const idx = templates.findIndex((x) => x.id === id);
    return CHIP_COLORS[idx >= 0 ? idx % CHIP_COLORS.length : 0];
  }

  const activeTemplates = templates.filter(
    (tpl) => tpl.active && (!branchFilter || tpl.branch_id === branchFilter)
  );

  const visibleEmployees = employees.filter((e) => {
    if (branchFilter && e.branch_id !== branchFilter) return false;
    const q = searchQuery.trim().toLowerCase();
    if (!q) return true;
    return (e.first_name + " " + e.last_name).toLowerCase().includes(q);
  });

  function assignmentsFor(employeeId, dayIso) {
    return assignments.filter(
      (a) => a.employee_id === employeeId && a.start_date <= dayIso && (a.end_date || "9999-12-31") >= dayIso
    );
  }

  function hasConflict(employeeId, dayIso, excludeId) {
    return assignments.some(
      (a) =>
        a.employee_id === employeeId &&
        a.id !== excludeId &&
        rangesOverlap(dayIso, dayIso, a.start_date, a.end_date)
    );
  }

  function handleDragStartTemplate(e, templateId) {
    e.dataTransfer.setData("text/plain", JSON.stringify({ kind: "template", templateId }));
  }
  function handleDragStartAssignment(e, assignment) {
    if (assignment.start_date !== assignment.end_date) {
      e.preventDefault();
      return;
    }
    e.dataTransfer.setData("text/plain", JSON.stringify({ kind: "assignment", assignmentId: assignment.id }));
  }

  async function handleDrop(e, employeeId, dayIso) {
    e.preventDefault();
    let data;
    try {
      data = JSON.parse(e.dataTransfer.getData("text/plain"));
    } catch {
      return;
    }
    if (data.kind === "template") {
      if (hasConflict(employeeId, dayIso, null)) {
        showToast(t("conflict_toast"), "error");
        return;
      }
      try {
        await apiFetch("/api/shifts/assignments", {
          method: "POST",
          body: JSON.stringify({
            employee_id: employeeId,
            shift_template_id: data.templateId,
            start_date: dayIso,
            end_date: dayIso,
          }),
        });
        showToast(t("assignment_created_toast"));
        reloadAssignments();
      } catch (err) {
        showToast(err.message, "error");
      }
    } else if (data.kind === "assignment") {
      if (hasConflict(employeeId, dayIso, data.assignmentId)) {
        showToast(t("conflict_toast"), "error");
        return;
      }
      try {
        await apiFetch("/api/shifts/assignments/" + data.assignmentId, {
          method: "PATCH",
          body: JSON.stringify({ employee_id: employeeId, start_date: dayIso, end_date: dayIso }),
        });
        showToast(t("assignment_moved_toast"));
        reloadAssignments();
      } catch (err) {
        showToast(err.message, "error");
      }
    }
  }

  async function handleRemoveAssignment(assignmentId) {
    if (!window.confirm(t("remove_confirm"))) return;
    try {
      await apiFetch("/api/shifts/assignments/" + assignmentId, { method: "DELETE" });
      showToast(t("assignment_removed_toast"));
      reloadAssignments();
    } catch (err) {
      showToast(err.message, "error");
    }
  }

  function shiftWeek(delta) {
    const d = new Date(weekStart);
    d.setDate(d.getDate() + delta * 7);
    setWeekStart(d);
  }

  const dayLabelKeys = [0, 1, 2, 3, 4, 5, 6];

  return (
    <div>
      <h1 className="font-heading text-2xl font-extrabold text-bk-brown mb-2">{t("title")}</h1>
      <p className="text-sm text-bk-brown/60 mb-6">{t("subtitle")}</p>

      {error && <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-4">{error}</p>}

      <div className="flex flex-wrap items-center gap-3 mb-4">
        <button
          onClick={() => shiftWeek(-1)}
          className="text-xs font-semibold text-bk-brown border border-bk-brown/30 rounded-lg px-3 py-1.5"
        >
          {t("prev_week")}
        </button>
        <button
          onClick={() => setWeekStart(mondayOf(new Date()))}
          className="text-xs font-semibold text-bk-brown border border-bk-brown/30 rounded-lg px-3 py-1.5"
        >
          {t("this_week")}
        </button>
        <button
          onClick={() => shiftWeek(1)}
          className="text-xs font-semibold text-bk-brown border border-bk-brown/30 rounded-lg px-3 py-1.5"
        >
          {t("next_week")}
        </button>
        <span className="text-sm font-semibold text-bk-brown ml-2">
          {toIsoDate(weekDays[0])} → {toIsoDate(weekDays[6])}
        </span>
        <select
          value={branchFilter}
          onChange={(e) => setBranchFilter(e.target.value)}
          className="text-xs border border-bk-brown/20 rounded-md px-2 py-1.5 ml-auto"
        >
          <option value="">{t("all_branches")}</option>
          {branches.map((b) => (
            <option key={b.id} value={b.id}>
              {b.name}
            </option>
          ))}
        </select>
        <input
          type="text"
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          placeholder={t("search_employee_placeholder")}
          className="text-xs border border-bk-brown/20 rounded-md px-2 py-1.5"
        />
      </div>

      <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-4 mb-6">
        <p className="text-xs font-semibold text-bk-brown/70 mb-2">{t("palette_hint")}</p>
        <div className="flex flex-wrap gap-2">
          {activeTemplates.length === 0 ? (
            <p className="text-xs text-bk-brown/50">{t("no_templates")}</p>
          ) : (
            activeTemplates.map((tpl) => (
              <div
                key={tpl.id}
                draggable
                onDragStart={(e) => handleDragStartTemplate(e, tpl.id)}
                className={
                  "cursor-grab select-none text-xs font-semibold rounded-lg border px-3 py-1.5 " + templateColor(tpl.id)
                }
                title={branchName(tpl.branch_id) + " · " + tpl.start_time + "-" + tpl.end_time}
              >
                {tpl.name}
              </div>
            ))
          )}
        </div>
      </div>

      {loading ? (
        <LoadingState />
      ) : (
        <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 overflow-x-auto">
          <table className="min-w-full text-xs">
            <thead>
              <tr className="border-b border-bk-brown/10">
                <th className="text-left px-3 py-2 font-semibold text-bk-brown/70 sticky left-0 bg-white">
                  {t("employee")}
                </th>
                {weekDays.map((d, i) => (
                  <th key={i} className="text-left px-3 py-2 font-semibold text-bk-brown/70 min-w-[130px]">
                    {t("day_" + dayLabelKeys[i])}
                    <div className="text-[10px] font-normal text-bk-brown/50">{toIsoDate(d)}</div>
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {visibleEmployees.length === 0 ? (
                <tr>
                  <td colSpan={8} className="px-3 py-6 text-center text-bk-brown/50">
                    {t("no_employees")}
                  </td>
                </tr>
              ) : (
                visibleEmployees.map((emp) => (
                  <tr key={emp.id} className="border-b border-bk-brown/5">
                    <td className="px-3 py-2 font-semibold text-bk-brown sticky left-0 bg-white whitespace-nowrap">
                      {emp.first_name} {emp.last_name}
                    </td>
                    {weekDays.map((d, i) => {
                      const dayIso = toIsoDate(d);
                      const dayAssignments = assignmentsFor(emp.id, dayIso);
                      return (
                        <td
                          key={i}
                          onDragOver={(e) => e.preventDefault()}
                          onDrop={(e) => handleDrop(e, emp.id, dayIso)}
                          className="px-2 py-2 align-top border-l border-bk-brown/5 min-h-[56px]"
                        >
                          <div className="flex flex-col gap-1 min-h-[40px]">
                            {dayAssignments.map((a) => {
                              const movable = a.start_date === a.end_date;
                              return (
                                <div
                                  key={a.id}
                                  draggable={movable}
                                  onDragStart={(e) => handleDragStartAssignment(e, a)}
                                  className={
                                    "rounded-md border px-2 py-1 text-[11px] flex items-center justify-between gap-1 " +
                                    templateColor(a.shift_template_id) +
                                    (movable ? " cursor-grab" : " opacity-60")
                                  }
                                  title={movable ? t("drag_hint") : t("locked_hint")}
                                >
                                  <span className="truncate">{templateName(a.shift_template_id)}</span>
                                  {movable && (
                                    <button
                                      onClick={() => handleRemoveAssignment(a.id)}
                                      className="text-bk-red font-bold leading-none"
                                    >
                                      ×
                                    </button>
                                  )}
                                </div>
                              );
                            })}
                          </div>
                        </td>
                      );
                    })}
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
