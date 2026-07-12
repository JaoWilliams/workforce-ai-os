"use client";

import { useEffect, useState } from "react";
import { useTranslations } from "next-intl";
import { useParams } from "next/navigation";
import { Clock } from "lucide-react";
import { apiFetch } from "../../../../lib/api";
import { LoadingState, EmptyState } from "../../../../lib/ui";
import { usePermissions } from "../../../../lib/permissions";
import { useToast } from "../../../../lib/toast";

const TYPES = ["entrada", "salida"];
const METHODS = ["facial", "fingerprint", "card", "manual"];

function nowLocalInputValue() {
  const d = new Date();
  d.setSeconds(0, 0);
  const off = d.getTimezoneOffset();
  const local = new Date(d.getTime() - off * 60000);
  return local.toISOString().slice(0, 16);
}

export default function MarcacionPage() {
  const t = useTranslations("attendance");  
  const { hasPermission } = usePermissions();
  const { showToast } = useToast();
  const params = useParams();
  const locale = params.locale;
  const [searchQuery, setSearchQuery] = useState("");
  const [branchFilter, setBranchFilter] = useState("");

  const [records, setRecords] = useState([]);
  const [employees, setEmployees] = useState([]);
  const [devices, setDevices] = useState([]);
  const [branches, setBranches] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const [employeeId, setEmployeeId] = useState("");
  const [deviceId, setDeviceId] = useState("");
  const [type, setType] = useState("entrada");
  const [method, setMethod] = useState("facial");
  const [recordedAt, setRecordedAt] = useState(nowLocalInputValue());
  const [enrollments, setEnrollments] = useState([]);
  const [enrollmentId, setEnrollmentId] = useState("");
  const [creating, setCreating] = useState(false);
  const [createError, setCreateError] = useState(null);
  const [createOk, setCreateOk] = useState(false);
  const [motivo, setMotivo] = useState("");

  useEffect(() => {
    loadRecords();
    apiFetch("/api/employees").then(setEmployees).catch(() => {});
    apiFetch("/api/devices").then(setDevices).catch(() => {});
    apiFetch("/api/branches").then(setBranches).catch(() => {});
  }, []);

  useEffect(() => {
    if (!employeeId) {
      setEnrollments([]);
      setEnrollmentId("");
      return;
    }
    apiFetch("/api/employees/" + employeeId + "/biometric-enrollments")
      .then(setEnrollments)
      .catch(() => setEnrollments([]));
    setEnrollmentId("");
  }, [employeeId]);

  function loadRecords() {
    setLoading(true);
    apiFetch("/api/attendance")
      .then(setRecords)
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }

  function employeeName(id) {
    const e = employees.find((x) => x.id === id);
    return e ? e.first_name + " " + e.last_name : id;
  }

  const filteredRecords = records
    .filter((r) => {
      if (!branchFilter) return true;
      const emp = employees.find((x) => x.id === r.employee_id);
      return emp && emp.branch_id === branchFilter;
    })
    .filter((r) => {
      const q = searchQuery.trim().toLowerCase();
      if (!q) return true;
      return employeeName(r.employee_id).toLowerCase().includes(q);
    });

  function deviceLabel(id) {
    const d = devices.find((x) => x.id === id);
    return d ? d.brand + " " + d.model + " (" + d.serial_number + ")" : id;
  }

  async function handleCreate(e) {
    e.preventDefault();
    setCreating(true);
    setCreateError(null);
    setCreateOk(false);
    try {
      const payload = {
        employee_id: employeeId,
        device_id: deviceId,
        type,
        verification_method: method,
        biometric_enrollment_id: enrollmentId || null,
        recorded_at: new Date(recordedAt).toISOString(),
      };
      const created = await apiFetch("/api/attendance", { method: "POST", body: JSON.stringify(payload) });
      if (method === "manual") {
        await apiFetch("/api/exceptions", {
          method: "POST",
          body: JSON.stringify({
            employee_id: employeeId,
            exception_type: "manual_correction",
            justification: motivo,
            attendance_record_id: created.id,
          }),
        });
      }
      setCreateOk(true);
      showToast(method === "manual" ? t("created_pending_toast") : t("created_ok_toast"));
      setMotivo("");
      setRecordedAt(nowLocalInputValue());
      loadRecords();
    } catch (err) {
      setCreateError(err.message);
      showToast(err.message, "error");
    } finally {
      setCreating(false);
    }
  }

  return (
    <div>
      <h1 className="font-heading text-2xl font-extrabold text-bk-brown mb-2">{t("title")}</h1>
      <p className="text-sm text-bk-brown/60 mb-6 max-w-2xl">{t("subtitle")}</p>

      {error && (
        <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-4">{error}</p>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 overflow-hidden">
          <div className="p-3 border-b border-bk-brown/10 flex flex-col gap-2 sm:flex-row">
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder={t("search_placeholder")}
              className="w-full border border-bk-brown/20 rounded-md px-3 py-1.5 text-sm"
            />
            <select
              value={branchFilter}
              onChange={(e) => setBranchFilter(e.target.value)}
              className="border border-bk-brown/20 rounded-md px-3 py-1.5 text-sm sm:w-48"
            >
              <option value="">{t("filter_all_branches")}</option>
              {branches.map((b) => (
                <option key={b.id} value={b.id}>
                  {b.name}
                </option>
              ))}
            </select>
          </div>
          {loading ? (
            <LoadingState />
          ) : filteredRecords.length === 0 ? (
            <EmptyState icon={Clock} message={t("no_records")} />
          ) : (
            <ul className="divide-y divide-bk-brown/10 max-h-[640px] overflow-y-auto">
              {filteredRecords.map((r) => (
                <li key={r.id} className="px-5 py-4">
                  <div className="flex items-center gap-2 mb-1">
                    <span
                      className={
                        r.type === "entrada"
                          ? "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-green-100 text-green-700"
                          : "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-bk-orange/10 text-bk-orange"
                      }
                    >
                      {t("type_" + r.type)}
                    </span>
                    {r.is_simulated && (
                      <span className="inline-block rounded-full px-2 py-0.5 text-[9px] font-semibold bg-bk-brown/10 text-bk-brown/50">
                        {t("simulated_badge")}
                      </span>
                    )}
                  </div>
                  <p className="font-semibold text-bk-brown text-sm">{employeeName(r.employee_id)}</p>
                  <p className="text-xs text-bk-brown/60 mt-0.5">{deviceLabel(r.device_id)}</p>
                  <p className="text-xs text-bk-brown/60 mt-0.5">
                    {t("verification_method")}: {t("method_" + r.verification_method)} · {r.recorded_at}
                  </p>
                  {hasPermission("exceptions.manage") && (
                    <a
                      href={
                        "/" + locale + "/dashboard/excepciones?employee_id=" + r.employee_id +
                        "&attendance_record_id=" + r.id
                      }
                      className="inline-block mt-2 text-[11px] font-semibold text-bk-orange hover:underline"
                    >
                      {t("correct_record")}
                    </a>
                  )}
                </li>
              ))}
            </ul>
          )}
        </div>

        <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5">
          <h2 className="font-heading font-bold text-bk-brown mb-4">{t("new_record")}</h2>

          {createError && (
            <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-3">{createError}</p>
          )}
          {createOk && (
            <p className="text-sm text-green-700 bg-green-100 rounded-lg px-3 py-2 mb-3">
              {t("created_ok")}{" "}
              <a href={"/" + locale + "/dashboard/confianza"} className="underline font-semibold">
                {t("go_to_confianza")}
              </a>
            </p>
          )}

          {hasPermission("attendance.manage") && (
          <form onSubmit={handleCreate} className="space-y-3 text-sm">
            <div>
              <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("employee")}</label>
              <select
                required
                value={employeeId}
                onChange={(e) => setEmployeeId(e.target.value)}
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
              <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("device")}</label>
              <select
                required
                value={deviceId}
                onChange={(e) => setDeviceId(e.target.value)}
                className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
              >
                <option value="">{t("select_device")}</option>
                {devices.map((d) => (
                  <option key={d.id} value={d.id}>
                    {d.brand} {d.model} ({d.serial_number})
                  </option>
                ))}
              </select>
            </div>

            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("type")}</label>
                <select
                  value={type}
                  onChange={(e) => setType(e.target.value)}
                  className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                >
                  {TYPES.map((ty) => (
                    <option key={ty} value={ty}>
                      {t("type_" + ty)}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("verification_method")}</label>
                <select
                  value={method}
                  onChange={(e) => setMethod(e.target.value)}
                  className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                >
                  {METHODS.map((m) => (
                    <option key={m} value={m}>
                      {t("method_" + m)}
                    </option>
                  ))}
                </select>
              </div>
            </div>
            {method === "manual" && (
              <div>
                <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("manual_reason")}</label>
                <textarea
                  required
                  rows={2}
                  value={motivo}
                  onChange={(e) => setMotivo(e.target.value)}
                  placeholder={t("manual_reason_hint")}
                  className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                />
                <p className="text-[11px] text-bk-orange mt-1">{t("manual_reason_notice")}</p>
              </div>
            )}

            {method !== "manual" && enrollments.length > 0 && (
              <div>
                <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("biometric_enrollment")}</label>
                <select
                  value={enrollmentId}
                  onChange={(e) => setEnrollmentId(e.target.value)}
                  className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                >
                  <option value="">{t("select_enrollment")}</option>
                  {enrollments.map((en) => (
                    <option key={en.id} value={en.id}>
                      {en.biometric_type} · {en.enrolled_at}
                    </option>
                  ))}
                </select>
              </div>
            )}

            <div>
              <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("recorded_at")}</label>
              <input
                type="datetime-local"
                required
                value={recordedAt}
                onChange={(e) => setRecordedAt(e.target.value)}
                className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
              />
            </div>

            <button
              type="submit"
              disabled={creating}
              className="text-xs font-semibold text-white rounded-lg px-4 py-2 disabled:opacity-50"
              style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}
            >
              {t("create")}
            </button>
          </form>
          )}
        </div>
      </div>
    </div>
  );
}
