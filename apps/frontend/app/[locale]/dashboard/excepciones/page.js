"use client";

import { useEffect, useState } from "react";
import { useTranslations } from "next-intl";
import { ClipboardList } from "lucide-react";
import { apiFetch } from "../../../../lib/api";
import { useToast } from "../../../../lib/toast";
import { LoadingState, EmptyState } from "../../../../lib/ui";

const TYPES = [
  "missing_checkin",
  "missing_checkout",
  "late_arrival",
  "early_departure",
  "absence",
  "manual_correction",
  "other",
];

export default function ExcepcionesPage() {
  const t = useTranslations("exceptions_page");
  const { showToast } = useToast();
  const [exceptions, setExceptions] = useState([]);
  const [employees, setEmployees] = useState([]);
  const [attendanceRecords, setAttendanceRecords] = useState([]);
  const [trustFlags, setTrustFlags] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [filter, setFilter] = useState("all");
  const [reviewingId, setReviewingId] = useState(null);
  const [reviewNotesMap, setReviewNotesMap] = useState({});

  const [employeeId, setEmployeeId] = useState("");
  const [exceptionType, setExceptionType] = useState("late_arrival");
  const [justification, setJustification] = useState("");
  const [evidenceReference, setEvidenceReference] = useState("");
  const [attendanceRecordId, setAttendanceRecordId] = useState("");
  const [trustFlagId, setTrustFlagId] = useState("");
  const [creating, setCreating] = useState(false);
  const [createError, setCreateError] = useState(null);
  const [createOk, setCreateOk] = useState(false);

  useEffect(() => {
    load();
    apiFetch("/api/employees").then(setEmployees).catch(() => {});
    apiFetch("/api/attendance").then(setAttendanceRecords).catch(() => {});
    apiFetch("/api/confianza-operativa/flags").then(setTrustFlags).catch(() => {});
  }, []);

  function load() {
    setLoading(true);
    apiFetch("/api/exceptions")
      .then(setExceptions)
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }

  function employeeName(id) {
    const e = employees.find((x) => x.id === id);
    return e ? e.first_name + " " + e.last_name : id;
  }

  function typeLabel(code) {
    const key = "type_" + code;
    const translated = t(key);
    return translated === key ? code : translated;
  }

  function statusLabel(status) {
    const key = "status_" + status;
    const translated = t(key);
    return translated === key ? status : translated;
  }

  function statusClasses(status) {
    if (status === "approved") return "bg-green-100 text-green-700";
    if (status === "rejected") return "bg-bk-red/10 text-bk-red";
    return "bg-bk-brown/10 text-bk-brown/60";
  }

  async function handleReview(exc, newStatus) {
    setReviewingId(exc.id);
    setError(null);
    try {
      await apiFetch("/api/exceptions/" + exc.id + "/review", {
        method: "PATCH",
        body: JSON.stringify({ status: newStatus, review_notes: reviewNotesMap[exc.id] || null }),
      });
      showToast(t("status_" + newStatus));
      load();
    } catch (err) {
      setError(err.message);
      showToast(err.message, "error");
    } finally {
      setReviewingId(null);
    }
  }

  async function handleCreate(e) {
    e.preventDefault();
    setCreating(true);
    setCreateError(null);
    setCreateOk(false);
    try {
      const payload = {
        employee_id: employeeId,
        exception_type: exceptionType,
        justification,
        evidence_reference: evidenceReference || null,
        attendance_record_id: attendanceRecordId || null,
        trust_flag_id: trustFlagId || null,
      };
      await apiFetch("/api/exceptions", { method: "POST", body: JSON.stringify(payload) });
      showToast(t("created_ok"));
      setJustification("");
      setEvidenceReference("");
      setAttendanceRecordId("");
      setTrustFlagId("");
      load();
    } catch (err) {
      setCreateError(err.message);
      showToast(err.message, "error");
    } finally {
      setCreating(false);
    }
  }

  const employeeAttendance = attendanceRecords.filter((r) => r.employee_id === employeeId);
  const employeeFlags = trustFlags.filter((f) => f.employee_id === employeeId);

  const displayed = exceptions.filter((exc) => {
    if (filter === "all") return true;
    return exc.status === filter;
  });

  return (
    <div>
      <h1 className="font-heading text-2xl font-extrabold text-bk-brown mb-2">{t("title")}</h1>
      <p className="text-sm text-bk-brown/60 mb-6 max-w-2xl">{t("subtitle")}</p>

      <div className="flex gap-2 mb-6">
        {["all", "pending", "approved", "rejected"].map((f) => (
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

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div>
          {loading ? (
            <LoadingState />
          ) : displayed.length === 0 ? (
            <EmptyState icon={ClipboardList} message={t("no_exceptions")} />
          ) : (
            <div className="space-y-4">
              {displayed.map((exc) => (
                <div key={exc.id} className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5">
                  <div className="flex items-center gap-2 mb-1">
                    <span className={"inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold " + statusClasses(exc.status)}>
                      {statusLabel(exc.status)}
                    </span>
                  </div>
                  <p className="font-heading font-bold text-bk-brown">{typeLabel(exc.exception_type)}</p>
                  <p className="text-xs text-bk-brown/60 mt-0.5">
                    {employeeName(exc.employee_id)} · {t("created_at")}: {exc.created_at}
                  </p>
                  <p className="text-sm text-bk-brown/80 mt-2">{exc.justification}</p>
                  {exc.evidence_reference && (
                    <p className="text-xs text-bk-brown/60 mt-1 break-all">{exc.evidence_reference}</p>
                  )}
                  {exc.status !== "pending" && exc.review_notes && (
                    <p className="text-xs text-bk-brown/50 mt-2 italic">{exc.review_notes}</p>
                  )}
                  {exc.status !== "pending" && exc.reviewed_at && (
                    <p className="text-[11px] text-bk-brown/40 mt-1">
                      {t("reviewed_at")}: {exc.reviewed_at}
                    </p>
                  )}

                  {exc.status === "pending" && (
                    <div className="mt-3 pt-3 border-t border-bk-brown/10 space-y-2">
                      <input
                        type="text"
                        placeholder={t("review_notes")}
                        value={reviewNotesMap[exc.id] || ""}
                        onChange={(ev) =>
                          setReviewNotesMap({ ...reviewNotesMap, [exc.id]: ev.target.value })
                        }
                        className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5 text-xs"
                      />
                      <div className="flex gap-2">
                        <button
                          onClick={() => handleReview(exc, "approved")}
                          disabled={reviewingId === exc.id}
                          className="text-xs font-semibold text-white rounded-lg px-3 py-1.5 bg-green-600 disabled:opacity-50"
                        >
                          {t("approve")}
                        </button>
                        <button
                          onClick={() => handleReview(exc, "rejected")}
                          disabled={reviewingId === exc.id}
                          className="text-xs font-semibold text-white rounded-lg px-3 py-1.5 bg-bk-red disabled:opacity-50"
                        >
                          {t("reject")}
                        </button>
                      </div>
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>

        <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 h-fit">
          <h2 className="font-heading font-bold text-bk-brown mb-4">{t("new_exception")}</h2>

          {createError && (
            <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-3">{createError}</p>
          )}
          {createOk && (
            <p className="text-sm text-green-700 bg-green-100 rounded-lg px-3 py-2 mb-3">{t("created_ok")}</p>
          )}

          <form onSubmit={handleCreate} className="space-y-3 text-sm">
            <div>
              <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("employee")}</label>
              <select
                required
                value={employeeId}
                onChange={(e) => {
                  setEmployeeId(e.target.value);
                  setAttendanceRecordId("");
                  setTrustFlagId("");
                }}
                className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
              >
                <option value="">{t("select_employee")}</option>
                {employees.map((emp) => (
                  <option key={emp.id} value={emp.id}>
                    {emp.first_name} {emp.last_name}
                  </option>
                ))}
              </select>
            </div>

            <div>
              <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("exception_type")}</label>
              <select
                value={exceptionType}
                onChange={(e) => setExceptionType(e.target.value)}
                className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
              >
                {TYPES.map((ty) => (
                  <option key={ty} value={ty}>
                    {typeLabel(ty)}
                  </option>
                ))}
              </select>
            </div>

            <div>
              <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("justification")}</label>
              <textarea
                required
                rows={3}
                value={justification}
                onChange={(e) => setJustification(e.target.value)}
                className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
              />
            </div>

            <div>
              <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("evidence_reference")}</label>
              <input
                value={evidenceReference}
                onChange={(e) => setEvidenceReference(e.target.value)}
                className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
              />
            </div>

            {employeeId && employeeAttendance.length > 0 && (
              <div>
                <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("attendance_record")}</label>
                <select
                  value={attendanceRecordId}
                  onChange={(e) => setAttendanceRecordId(e.target.value)}
                  className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                >
                  <option value="">{t("select_none")}</option>
                  {employeeAttendance.map((r) => (
                    <option key={r.id} value={r.id}>
                      {r.type} · {r.recorded_at}
                    </option>
                  ))}
                </select>
              </div>
            )}

            {employeeId && employeeFlags.length > 0 && (
              <div>
                <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("trust_flag")}</label>
                <select
                  value={trustFlagId}
                  onChange={(e) => setTrustFlagId(e.target.value)}
                  className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                >
                  <option value="">{t("select_none")}</option>
                  {employeeFlags.map((f) => (
                    <option key={f.id} value={f.id}>
                      {f.rule_code} · {f.severity}
                    </option>
                  ))}
                </select>
              </div>
            )}

            <button
              type="submit"
              disabled={creating}
              className="text-xs font-semibold text-white rounded-lg px-4 py-2 disabled:opacity-50"
              style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}
            >
              {t("create")}
            </button>
          </form>
        </div>
      </div>
    </div>
  );
}
