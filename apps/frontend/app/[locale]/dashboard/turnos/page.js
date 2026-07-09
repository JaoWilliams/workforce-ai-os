"use client";

import { useEffect, useState } from "react";
import { useTranslations } from "next-intl";
import { apiFetch } from "../../../../lib/api";
import { useToast } from "../../../../lib/toast";

const DAYS = [0, 1, 2, 3, 4, 5, 6];

function rangesOverlap(aStart, aEnd, bStart, bEnd) {
  const aEndVal = aEnd || "9999-12-31";
  const bEndVal = bEnd || "9999-12-31";
  return aStart <= bEndVal && bStart <= aEndVal;
}

export default function TurnosPage() {
  const t = useTranslations("shifts");
  const { showToast } = useToast();

  const [templates, setTemplates] = useState([]);
  const [branches, setBranches] = useState([]);
  const [employees, setEmployees] = useState([]);
  const [assignments, setAssignments] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [selectedTemplateId, setSelectedTemplateId] = useState("");

  const [branchId, setBranchId] = useState("");
  const [name, setName] = useState("");
  const [startTime, setStartTime] = useState("06:00");
  const [endTime, setEndTime] = useState("14:00");
  const [days, setDays] = useState({});
  const [minCoverage, setMinCoverage] = useState(1);
  const [creating, setCreating] = useState(false);
  const [createError, setCreateError] = useState(null);

  const [assignEmployeeId, setAssignEmployeeId] = useState("");
  const [assignStartDate, setAssignStartDate] = useState("");
  const [assignEndDate, setAssignEndDate] = useState("");
  const [showOtherBranches, setShowOtherBranches] = useState(false);
  const [assigning, setAssigning] = useState(false);
  const [assignError, setAssignError] = useState(null);

  const [coverageDate, setCoverageDate] = useState("");
  const [coverageResult, setCoverageResult] = useState(null);
  const [coverageError, setCoverageError] = useState(null);
  const [checkingCoverage, setCheckingCoverage] = useState(false);

  useEffect(() => {
    loadTemplates();
    loadAssignments();
    apiFetch("/api/branches").then(setBranches).catch(() => {});
    apiFetch("/api/employees").then(setEmployees).catch(() => {});
  }, []);

  function loadTemplates() {
    setLoading(true);
    apiFetch("/api/shifts")
      .then(setTemplates)
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }

  function loadAssignments() {
    apiFetch("/api/shifts/assignments").then(setAssignments).catch(() => {});
  }

  function branchName(id) {
    const b = branches.find((x) => x.id === id);
    return b ? b.name : id;
  }

  function employeeName(id) {
    const e = employees.find((x) => x.id === id);
    return e ? e.first_name + " " + e.last_name : id;
  }

  function toggleDay(d) {
    setDays((prev) => ({ ...prev, [d]: !prev[d] }));
  }

  const selectedTemplate = templates.find((tpl) => tpl.id === selectedTemplateId) || null;
  const templateAssignments = assignments.filter((a) => a.shift_template_id === selectedTemplateId);
  const eligibleEmployees = employees.filter(
    (e) => showOtherBranches || (selectedTemplate && e.branch_id === selectedTemplate.branch_id)
  );

  let conflictWarning = null;
  if (assignEmployeeId && assignStartDate) {
    const conflict = assignments.find(
      (a) =>
        a.employee_id === assignEmployeeId &&
        a.shift_template_id !== selectedTemplateId &&
        rangesOverlap(assignStartDate, assignEndDate, a.start_date, a.end_date)
    );
    if (conflict) {
      const otherTpl = templates.find((tpl) => tpl.id === conflict.shift_template_id);
      conflictWarning = t("conflict_warning") + (otherTpl ? " — " + otherTpl.name : "");
    }
  }

  async function handleCreateTemplate(e) {
    e.preventDefault();
    setCreating(true);
    setCreateError(null);
    try {
      const days_of_week = DAYS.filter((d) => days[d]);
      const payload = {
        branch_id: branchId,
        name,
        start_time: startTime + ":00",
        end_time: endTime + ":00",
        days_of_week,
        min_coverage: parseInt(minCoverage, 10) || 1,
      };
      await apiFetch("/api/shifts", { method: "POST", body: JSON.stringify(payload) });
      showToast(t("template_created_toast", { name }));
      setName("");
      setDays({});
      loadTemplates();
    } catch (err) {
      setCreateError(err.message);
      showToast(err.message, "error");
    } finally {
      setCreating(false);
    }
  }

  async function handleAssign(e) {
    e.preventDefault();
    setAssigning(true);
    setAssignError(null);
    try {
      const payload = {
        employee_id: assignEmployeeId,
        shift_template_id: selectedTemplateId,
        start_date: assignStartDate,
        end_date: assignEndDate || null,
      };
      await apiFetch("/api/shifts/assignments", { method: "POST", body: JSON.stringify(payload) });
      showToast(
        t("assigned_to_toast", {
          employee: employeeName(assignEmployeeId),
          shift: selectedTemplate.name,
          branch: branchName(selectedTemplate.branch_id),
        })
      );
      setAssignEmployeeId("");
      setAssignStartDate("");
      setAssignEndDate("");
      loadAssignments();
    } catch (err) {
      setAssignError(err.message);
      showToast(err.message, "error");
    } finally {
      setAssigning(false);
    }
  }

  async function handleCheckCoverage(e) {
    e.preventDefault();
    setCheckingCoverage(true);
    setCoverageError(null);
    setCoverageResult(null);
    try {
      const data = await apiFetch(
        "/api/shifts/" + selectedTemplateId + "/coverage?on_date=" + coverageDate
      );
      setCoverageResult(data);
    } catch (err) {
      setCoverageError(err.message);
    } finally {
      setCheckingCoverage(false);
    }
  }

  return (
    <div>
      <h1 className="font-heading text-2xl font-extrabold text-bk-brown mb-6">{t("title")}</h1>

      {error && (
        <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-4">{error}</p>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="space-y-6">
          <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 overflow-hidden">
            {loading ? (
              <p className="p-4 text-sm text-bk-brown/60">...</p>
            ) : templates.length === 0 ? (
              <p className="p-4 text-sm text-bk-brown/60">{t("no_templates")}</p>
            ) : (
              <ul className="divide-y divide-bk-brown/10">
                {templates.map((tpl) => (
                  <li key={tpl.id}>
                    <button
                      onClick={() => setSelectedTemplateId(tpl.id)}
                      className={
                        selectedTemplateId === tpl.id
                          ? "w-full text-left px-5 py-4 transition bg-bk-orange/10"
                          : "w-full text-left px-5 py-4 transition hover:bg-bk-cream2"
                      }
                    >
                      <p className="font-semibold text-bk-brown">{tpl.name}</p>
                      <p className="text-xs text-bk-brown/60 mt-0.5">{branchName(tpl.branch_id)}</p>
                      <p className="text-xs text-bk-brown/60 mt-0.5">
                        {tpl.start_time} - {tpl.end_time}
                      </p>
                      <p className="text-xs text-bk-brown/60 mt-0.5">
                        {tpl.days_of_week.map((d) => t("day_" + d)).join(", ")}
                      </p>
                      <p className="text-[11px] text-bk-brown/50 mt-1">
                        {t("min_coverage")}: {tpl.min_coverage}
                      </p>
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>

          <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5">
            <h2 className="font-heading font-bold text-bk-brown mb-4">{t("new_template")}</h2>

            {createError && (
              <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-3">{createError}</p>
            )}

            <form onSubmit={handleCreateTemplate} className="space-y-3 text-sm">
              <div>
                <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("branch")}</label>
                <select
                  required
                  value={branchId}
                  onChange={(e) => setBranchId(e.target.value)}
                  className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                >
                  <option value="">{t("select_branch")}</option>
                  {branches.map((b) => (
                    <option key={b.id} value={b.id}>
                      {b.name}
                    </option>
                  ))}
                </select>
              </div>

              <div>
                <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("name")}</label>
                <input
                  required
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("start_time")}</label>
                  <input
                    type="time"
                    required
                    value={startTime}
                    onChange={(e) => setStartTime(e.target.value)}
                    className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                  />
                </div>
                <div>
                  <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("end_time")}</label>
                  <input
                    type="time"
                    required
                    value={endTime}
                    onChange={(e) => setEndTime(e.target.value)}
                    className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("days_of_week")}</label>
                <div className="flex flex-wrap gap-3">
                  {DAYS.map((d) => (
                    <label key={d} className="flex items-center gap-1 text-xs text-bk-brown/80">
                      <input type="checkbox" checked={!!days[d]} onChange={() => toggleDay(d)} />
                      {t("day_" + d)}
                    </label>
                  ))}
                </div>
              </div>

              <div>
                <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("min_coverage")}</label>
                <input
                  type="number"
                  min="1"
                  value={minCoverage}
                  onChange={(e) => setMinCoverage(e.target.value)}
                  className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                />
              </div>

              <button
                type="submit"
                disabled={creating}
                className="text-xs font-semibold text-white rounded-lg px-4 py-2 disabled:opacity-50"
                style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}
              >
                {t("create_template")}
              </button>
            </form>
          </div>
        </div>

        <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 h-fit">
          {!selectedTemplate ? (
            <p className="text-sm text-bk-brown/60">{t("select_template_prompt")}</p>
          ) : (
            <div>
              <h2 className="font-heading font-bold text-bk-brown mb-1">{selectedTemplate.name}</h2>
              <p className="text-xs text-bk-brown/60 mb-4">
                {branchName(selectedTemplate.branch_id)} · {selectedTemplate.start_time}-{selectedTemplate.end_time}
              </p>

              <h3 className="font-heading font-semibold text-bk-brown text-sm mb-2">{t("assigned_employees")}</h3>
              {templateAssignments.length === 0 ? (
                <p className="text-xs text-bk-brown/60 mb-4">{t("no_assigned_employees")}</p>
              ) : (
                <div className="space-y-2 mb-4">
                  {templateAssignments.map((a) => (
                    <div key={a.id} className="border border-bk-brown/10 rounded-lg px-3 py-2 text-xs">
                      <p className="font-semibold text-bk-brown">{employeeName(a.employee_id)}</p>
                      <p className="text-bk-brown/60">
                        {a.start_date} → {a.end_date || "..."}
                      </p>
                    </div>
                  ))}
                </div>
              )}

              {assignError && (
                <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-3">{assignError}</p>
              )}
              {conflictWarning && (
                <p className="text-xs text-bk-orange bg-bk-orange/10 rounded-lg px-3 py-2 mb-3">{conflictWarning}</p>
              )}

              <form onSubmit={handleAssign} className="space-y-3 text-sm border-t border-bk-brown/10 pt-4">
                <label className="flex items-center gap-1 text-xs text-bk-brown/70">
                  <input
                    type="checkbox"
                    checked={showOtherBranches}
                    onChange={(e) => setShowOtherBranches(e.target.checked)}
                  />
                  {t("show_other_branches")}
                </label>

                <div>
                  <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("employee")}</label>
                  <select
                    required
                    value={assignEmployeeId}
                    onChange={(e) => setAssignEmployeeId(e.target.value)}
                    className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                  >
                    <option value="">{t("select_employee")}</option>
                    {eligibleEmployees.map((emp) => (
                      <option key={emp.id} value={emp.id}>
                        {emp.first_name} {emp.last_name}
                      </option>
                    ))}
                  </select>
                </div>

                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("start_date")}</label>
                    <input
                      type="date"
                      required
                      value={assignStartDate}
                      onChange={(e) => setAssignStartDate(e.target.value)}
                      className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                    />
                  </div>
                  <div>
                    <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("end_date")}</label>
                    <input
                      type="date"
                      value={assignEndDate}
                      onChange={(e) => setAssignEndDate(e.target.value)}
                      className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                    />
                  </div>
                </div>

                <button
                  type="submit"
                  disabled={assigning}
                  className="text-xs font-semibold text-white rounded-lg px-4 py-2 disabled:opacity-50"
                  style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}
                >
                  {t("assign")}
                </button>
              </form>

              <div className="border-t border-bk-brown/10 pt-4 mt-4">
                <h3 className="font-heading font-semibold text-bk-brown text-sm mb-2">{t("check_coverage")}</h3>
                {coverageError && (
                  <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-3">{coverageError}</p>
                )}
                <form onSubmit={handleCheckCoverage} className="flex items-end gap-2">
                  <div className="flex-1">
                    <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("coverage_date")}</label>
                    <input
                      type="date"
                      required
                      value={coverageDate}
                      onChange={(e) => setCoverageDate(e.target.value)}
                      className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                    />
                  </div>
                  <button
                    type="submit"
                    disabled={checkingCoverage}
                    className="text-xs font-semibold text-bk-brown border border-bk-brown/30 rounded-lg px-4 py-2 disabled:opacity-50"
                  >
                    {t("check_coverage")}
                  </button>
                </form>

                {coverageResult && (
                  <div className="mt-3 border border-bk-brown/10 rounded-lg p-3 text-sm">
                    <span
                      className={
                        coverageResult.covered
                          ? "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-green-100 text-green-700"
                          : "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-bk-red/10 text-bk-red"
                      }
                    >
                      {coverageResult.covered ? t("coverage_covered") : t("coverage_not_covered")}
                    </span>
                    <p className="text-xs text-bk-brown/60 mt-2">
                      {t("assigned_count")}: {coverageResult.assigned_count} {t("of_min")} {coverageResult.min_coverage}
                    </p>
                  </div>
                )}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
