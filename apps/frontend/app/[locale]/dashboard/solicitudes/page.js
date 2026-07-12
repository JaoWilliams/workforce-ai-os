"use client";

import { useEffect, useState } from "react";
import { useTranslations } from "next-intl";
import { CalendarRange } from "lucide-react";
import { apiFetch } from "../../../../lib/api";
import { useToast } from "../../../../lib/toast";
import { usePermissions } from "../../../../lib/permissions";
import { LoadingState, EmptyState } from "../../../../lib/ui";

const LEAVE_TYPES = ["medico", "personal", "duelo", "otro"];

function StatusBadge({ status, t }) {
  const cls =
    status === "approved"
      ? "bg-green-100 text-green-700"
      : status === "rejected"
      ? "bg-bk-red/10 text-bk-red"
      : "bg-amber-100 text-amber-700";
  return (
    <span className={"inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold " + cls}>
      {t("status_" + status)}
    </span>
  );
}

export default function SolicitudesPage() {
  const t = useTranslations("requests_page");
  const { hasPermission } = usePermissions();
  const { showToast } = useToast();
  const canManage = hasPermission("payroll.manage");

  const [activeTab, setActiveTab] = useState("vacation");
  const [employees, setEmployees] = useState([]);

  // --- vacaciones ---
  const [vacations, setVacations] = useState([]);
  const [vacationsLoading, setVacationsLoading] = useState(true);
  const [balanceEmployeeId, setBalanceEmployeeId] = useState("");
  const [balance, setBalance] = useState(null);
  const [vacForm, setVacForm] = useState({ employee_id: "", start_date: "", end_date: "" });
  const [creatingVac, setCreatingVac] = useState(false);
  const [vacError, setVacError] = useState(null);

  // --- permisos ---
  const [leaves, setLeaves] = useState([]);
  const [leavesLoading, setLeavesLoading] = useState(true);
  const [leaveForm, setLeaveForm] = useState({
    employee_id: "", leave_type: "personal", start_date: "", end_date: "", reason: "",
  });
  const [creatingLeave, setCreatingLeave] = useState(false);
  const [leaveError, setLeaveError] = useState(null);

  useEffect(() => {
    apiFetch("/api/employees").then(setEmployees).catch(() => {});
    loadVacations();
    loadLeaves();
  }, []);

  useEffect(() => {
    if (!balanceEmployeeId) {
      setBalance(null);
      return;
    }
    apiFetch(`/api/payroll/vacations/balance?employee_id=${balanceEmployeeId}`)
      .then(setBalance)
      .catch(() => setBalance(null));
  }, [balanceEmployeeId]);

  function loadVacations() {
    setVacationsLoading(true);
    apiFetch("/api/payroll/vacations")
      .then(setVacations)
      .catch(() => {})
      .finally(() => setVacationsLoading(false));
  }

  function loadLeaves() {
    setLeavesLoading(true);
    apiFetch("/api/leave-requests")
      .then(setLeaves)
      .catch(() => {})
      .finally(() => setLeavesLoading(false));
  }

  function employeeName(id) {
    const e = employees.find((x) => x.id === id);
    return e ? `${e.first_name} ${e.last_name}` : "";
  }

  async function handleCreateVacation(e) {
    e.preventDefault();
    setCreatingVac(true);
    setVacError(null);
    try {
      await apiFetch("/api/payroll/vacations/request", {
        method: "POST",
        body: JSON.stringify(vacForm),
      });
      showToast(t("created_ok"));
      setVacForm({ employee_id: "", start_date: "", end_date: "" });
      loadVacations();
    } catch (err) {
      setVacError(err.message);
    } finally {
      setCreatingVac(false);
    }
  }

  async function handleReviewVacation(id, status) {
    try {
      await apiFetch(`/api/payroll/vacations/${id}/status`, {
        method: "PATCH",
        body: JSON.stringify({ status }),
      });
      showToast(t("reviewed_ok"));
      loadVacations();
    } catch (err) {
      showToast(err.message, "error");
    }
  }

  async function handleCreateLeave(e) {
    e.preventDefault();
    setCreatingLeave(true);
    setLeaveError(null);
    try {
      await apiFetch("/api/leave-requests", {
        method: "POST",
        body: JSON.stringify({ ...leaveForm, reason: leaveForm.reason || null }),
      });
      showToast(t("created_ok"));
      setLeaveForm({ employee_id: "", leave_type: "personal", start_date: "", end_date: "", reason: "" });
      loadLeaves();
    } catch (err) {
      setLeaveError(err.message);
    } finally {
      setCreatingLeave(false);
    }
  }

  async function handleReviewLeave(id, status) {
    try {
      await apiFetch(`/api/leave-requests/${id}/status`, {
        method: "PATCH",
        body: JSON.stringify({ status }),
      });
      showToast(t("reviewed_ok"));
      loadLeaves();
    } catch (err) {
      showToast(err.message, "error");
    }
  }

  return (
    <div>
      <h1 className="font-heading text-2xl font-extrabold text-bk-brown mb-2">{t("title")}</h1>
      <p className="text-sm text-bk-brown/60 mb-6">{t("subtitle")}</p>

      <div className="flex gap-2 mb-6">
        <button
          type="button"
          onClick={() => setActiveTab("vacation")}
          className={
            "px-4 py-2 rounded-full text-sm font-semibold " +
            (activeTab === "vacation" ? "text-white" : "bg-white text-bk-brown/70 border border-bk-brown/10")
          }
          style={activeTab === "vacation" ? { background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" } : {}}
        >
          {t("tab_vacation")}
        </button>
        <button
          type="button"
          onClick={() => setActiveTab("leave")}
          className={
            "px-4 py-2 rounded-full text-sm font-semibold " +
            (activeTab === "leave" ? "text-white" : "bg-white text-bk-brown/70 border border-bk-brown/10")
          }
          style={activeTab === "leave" ? { background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" } : {}}
        >
          {t("tab_leave")}
        </button>
      </div>

      {activeTab === "vacation" && (
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          <div className="md:col-span-2 space-y-4">
            <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 overflow-hidden">
              {vacationsLoading ? (
                <LoadingState />
              ) : vacations.length === 0 ? (
                <EmptyState icon={CalendarRange} message={t("no_data")} />
              ) : (
                <ul className="divide-y divide-bk-brown/10">
                  {vacations.map((v) => (
                    <li key={v.id} className="px-5 py-3">
                      <div className="flex items-center justify-between mb-1">
                        <p className="font-semibold text-bk-brown text-sm">{v.employee_name}</p>
                        <StatusBadge status={v.status} t={t} />
                      </div>
                      <p className="text-xs text-bk-brown/60">
                        {v.start_date} - {v.end_date} · {t("days_count", { count: v.days_count })}
                      </p>
                      {v.status === "pending" && canManage && (
                        <div className="flex gap-2 mt-2">
                          <button
                            onClick={() => handleReviewVacation(v.id, "approved")}
                            className="text-xs font-semibold text-white bg-green-600 rounded-lg px-3 py-1"
                          >
                            {t("approve")}
                          </button>
                          <button
                            onClick={() => handleReviewVacation(v.id, "rejected")}
                            className="text-xs font-semibold text-white bg-bk-red rounded-lg px-3 py-1"
                          >
                            {t("reject")}
                          </button>
                        </div>
                      )}
                    </li>
                  ))}
                </ul>
              )}
            </div>

            {canManage && (
              <form
                onSubmit={handleCreateVacation}
                className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 space-y-3 text-sm"
              >
                <h3 className="font-heading font-bold text-bk-brown">{t("new_vacation_request")}</h3>
                {vacError && <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2">{vacError}</p>}
                <div>
                  <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("employee")}</label>
                  <select
                    required
                    value={vacForm.employee_id}
                    onChange={(e) => setVacForm({ ...vacForm, employee_id: e.target.value })}
                    className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                  >
                    <option value="">{t("select_employee")}</option>
                    {employees.map((e) => (
                      <option key={e.id} value={e.id}>
                        {e.first_name} {e.last_name}
                      </option>
                    ))}
                  </select>
                </div>
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("start_date")}</label>
                    <input
                      required
                      type="date"
                      value={vacForm.start_date}
                      onChange={(e) => setVacForm({ ...vacForm, start_date: e.target.value })}
                      className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                    />
                  </div>
                  <div>
                    <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("end_date")}</label>
                    <input
                      required
                      type="date"
                      value={vacForm.end_date}
                      onChange={(e) => setVacForm({ ...vacForm, end_date: e.target.value })}
                      className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                    />
                  </div>
                </div>
                <button
                  type="submit"
                  disabled={creatingVac}
                  className="text-xs font-semibold text-white rounded-lg px-4 py-2 disabled:opacity-50"
                  style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}
                >
                  {t("create")}
                </button>
              </form>
            )}
          </div>

          <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 text-sm space-y-3">
            <h3 className="font-heading font-bold text-bk-brown">{t("balance_title")}</h3>
            <select
              value={balanceEmployeeId}
              onChange={(e) => setBalanceEmployeeId(e.target.value)}
              className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
            >
              <option value="">{t("select_employee")}</option>
              {employees.map((e) => (
                <option key={e.id} value={e.id}>
                  {e.first_name} {e.last_name}
                </option>
              ))}
            </select>
            {balance && balance.blocked && (
              <p className="text-xs text-bk-brown/50">{t("balance_blocked_" + balance.reason)}</p>
            )}
            {balance && !balance.blocked && (
              <div className="space-y-1 text-xs text-bk-brown/70">
                <p>{t("accrued_days")}: {balance.accrued_days}</p>
                <p>{t("taken_days")}: {balance.taken_days}</p>
                <p>{t("pending_days")}: {balance.pending_days}</p>
                <p className="font-semibold text-bk-brown">{t("available_days")}: {balance.available_days}</p>
              </div>
            )}
          </div>
        </div>
      )}

      {activeTab === "leave" && (
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          <div className="md:col-span-2 space-y-4">
            <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 overflow-hidden">
              {leavesLoading ? (
                <LoadingState />
              ) : leaves.length === 0 ? (
                <EmptyState icon={CalendarRange} message={t("no_data")} />
              ) : (
                <ul className="divide-y divide-bk-brown/10">
                  {leaves.map((l) => (
                    <li key={l.id} className="px-5 py-3">
                      <div className="flex items-center justify-between mb-1">
                        <p className="font-semibold text-bk-brown text-sm">{l.employee_name}</p>
                        <StatusBadge status={l.status} t={t} />
                      </div>
                      <p className="text-xs text-bk-brown/60">
                        {t("leave_type_" + l.leave_type)} · {l.start_date} - {l.end_date}
                      </p>
                      {l.reason && <p className="text-xs text-bk-brown/60 mt-1">{l.reason}</p>}
                      {l.status === "pending" && canManage && (
                        <div className="flex gap-2 mt-2">
                          <button
                            onClick={() => handleReviewLeave(l.id, "approved")}
                            className="text-xs font-semibold text-white bg-green-600 rounded-lg px-3 py-1"
                          >
                            {t("approve")}
                          </button>
                          <button
                            onClick={() => handleReviewLeave(l.id, "rejected")}
                            className="text-xs font-semibold text-white bg-bk-red rounded-lg px-3 py-1"
                          >
                            {t("reject")}
                          </button>
                        </div>
                      )}
                    </li>
                  ))}
                </ul>
              )}
            </div>

            {canManage && (
              <form
                onSubmit={handleCreateLeave}
                className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 space-y-3 text-sm"
              >
                <h3 className="font-heading font-bold text-bk-brown">{t("new_leave_request")}</h3>
                {leaveError && <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2">{leaveError}</p>}
                <div>
                  <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("employee")}</label>
                  <select
                    required
                    value={leaveForm.employee_id}
                    onChange={(e) => setLeaveForm({ ...leaveForm, employee_id: e.target.value })}
                    className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                  >
                    <option value="">{t("select_employee")}</option>
                    {employees.map((e) => (
                      <option key={e.id} value={e.id}>
                        {e.first_name} {e.last_name}
                      </option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("leave_type")}</label>
                  <select
                    value={leaveForm.leave_type}
                    onChange={(e) => setLeaveForm({ ...leaveForm, leave_type: e.target.value })}
                    className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                  >
                    {LEAVE_TYPES.map((lt) => (
                      <option key={lt} value={lt}>
                        {t("leave_type_" + lt)}
                      </option>
                    ))}
                  </select>
                </div>
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("start_date")}</label>
                    <input
                      required
                      type="date"
                      value={leaveForm.start_date}
                      onChange={(e) => setLeaveForm({ ...leaveForm, start_date: e.target.value })}
                      className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                    />
                  </div>
                  <div>
                    <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("end_date")}</label>
                    <input
                      required
                      type="date"
                      value={leaveForm.end_date}
                      onChange={(e) => setLeaveForm({ ...leaveForm, end_date: e.target.value })}
                      className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                    />
                  </div>
                </div>
                <div>
                  <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("reason")}</label>
                  <textarea
                    rows={2}
                    value={leaveForm.reason}
                    onChange={(e) => setLeaveForm({ ...leaveForm, reason: e.target.value })}
                    className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                  />
                </div>
                <button
                  type="submit"
                  disabled={creatingLeave}
                  className="text-xs font-semibold text-white rounded-lg px-4 py-2 disabled:opacity-50"
                  style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}
                >
                  {t("create")}
                </button>
              </form>
            )}
          </div>
          <div />
        </div>
      )}
    </div>
  );
}
