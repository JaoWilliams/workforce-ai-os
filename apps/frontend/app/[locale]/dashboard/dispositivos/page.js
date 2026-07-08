"use client";

import { useEffect, useState } from "react";
import { useTranslations } from "next-intl";
import { apiFetch } from "../../../../lib/api";

const BRANDS = ["tiandy", "hikvision", "zkteco"];
const METHODS = ["facial", "fingerprint", "card", "password"];
const STATUSES = ["not_provisioned", "online", "offline"];
const BIOMETRIC_TYPES = ["facial", "fingerprint", "card"];

const emptyForm = {
  branch_id: "",
  brand: "",
  model: "",
  serial_number: "",
  ip_address: "",
  max_faces: "",
  max_fingerprints: "",
  max_cards: "",
  max_events: "",
  methods: {},
};

export default function DispositivosPage() {
  const t = useTranslations("devices");
  const tb = useTranslations("biometrics");

  const [devices, setDevices] = useState([]);
  const [branches, setBranches] = useState([]);
  const [devicesLoading, setDevicesLoading] = useState(true);
  const [devicesError, setDevicesError] = useState(null);

  const [form, setForm] = useState(emptyForm);
  const [creating, setCreating] = useState(false);
  const [createError, setCreateError] = useState(null);
  const [createOk, setCreateOk] = useState(false);

  const [employees, setEmployees] = useState([]);
  const [selectedEmployee, setSelectedEmployee] = useState(null);
  const [enrollments, setEnrollments] = useState([]);
  const [enrollmentsLoading, setEnrollmentsLoading] = useState(false);

  const [enrollDeviceId, setEnrollDeviceId] = useState("");
  const [enrollType, setEnrollType] = useState("facial");
  const [granting, setGranting] = useState(false);
  const [enrolling, setEnrolling] = useState(false);
  const [bioMsg, setBioMsg] = useState(null);
  const [bioError, setBioError] = useState(null);

  useEffect(() => {
    loadDevices();
    apiFetch("/api/branches").then(setBranches).catch(() => {});
    apiFetch("/api/employees").then(setEmployees).catch(() => {});
  }, []);

  function loadDevices() {
    setDevicesLoading(true);
    apiFetch("/api/devices")
      .then(setDevices)
      .catch((err) => setDevicesError(err.message))
      .finally(() => setDevicesLoading(false));
  }

  function branchName(id) {
    const b = branches.find((br) => br.id === id);
    return b ? b.name : id;
  }

  function toggleMethod(key) {
    setForm((f) => ({ ...f, methods: { ...f.methods, [key]: !f.methods[key] } }));
  }

  async function handleCreateDevice(e) {
    e.preventDefault();
    setCreating(true);
    setCreateError(null);
    setCreateOk(false);
    try {
      const verification_methods = METHODS.filter((m) => form.methods[m]);
      const payload = {
        branch_id: form.branch_id,
        brand: form.brand,
        model: form.model,
        serial_number: form.serial_number,
        ip_address: form.ip_address || null,
        max_faces: form.max_faces ? parseInt(form.max_faces, 10) : null,
        max_fingerprints: form.max_fingerprints ? parseInt(form.max_fingerprints, 10) : null,
        max_cards: form.max_cards ? parseInt(form.max_cards, 10) : null,
        max_events: form.max_events ? parseInt(form.max_events, 10) : null,
        verification_methods,
      };
      await apiFetch("/api/devices", { method: "POST", body: JSON.stringify(payload) });
      setForm(emptyForm);
      setCreateOk(true);
      loadDevices();
    } catch (err) {
      setCreateError(err.message);
    } finally {
      setCreating(false);
    }
  }

  async function handleStatusChange(device, newStatus) {
    try {
      await apiFetch("/api/devices/" + device.id, {
        method: "PATCH",
        body: JSON.stringify({ status: newStatus }),
      });
      loadDevices();
    } catch (err) {
      setDevicesError(err.message);
    }
  }

  async function selectEmployee(emp) {
    setSelectedEmployee(emp);
    setEnrollments([]);
    setBioMsg(null);
    setBioError(null);
    setEnrollmentsLoading(true);
    try {
      const data = await apiFetch("/api/employees/" + emp.id + "/biometric-enrollments");
      setEnrollments(data);
    } catch (err) {
      setBioError(err.message);
    } finally {
      setEnrollmentsLoading(false);
    }
  }

  async function handleGrantConsent() {
    if (!selectedEmployee) return;
    setGranting(true);
    setBioMsg(null);
    setBioError(null);
    try {
      await apiFetch("/api/legal/consent", {
        method: "POST",
        body: JSON.stringify({ consent_type: "biometric", employee_id: selectedEmployee.id }),
      });
      setBioMsg(tb("consent_granted"));
    } catch (err) {
      setBioError(err.message);
    } finally {
      setGranting(false);
    }
  }

  async function handleEnroll(e) {
    e.preventDefault();
    if (!selectedEmployee || !enrollDeviceId) return;
    setEnrolling(true);
    setBioMsg(null);
    setBioError(null);
    try {
      await apiFetch("/api/employees/" + selectedEmployee.id + "/biometric-enrollments", {
        method: "POST",
        body: JSON.stringify({ device_id: enrollDeviceId, biometric_type: enrollType }),
      });
      setBioMsg(tb("enroll_ok"));
      const data = await apiFetch("/api/employees/" + selectedEmployee.id + "/biometric-enrollments");
      setEnrollments(data);
    } catch (err) {
      setBioError(err.message);
    } finally {
      setEnrolling(false);
    }
  }

  function statusBadgeClass(status) {
    if (status === "online") return "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-green-100 text-green-700";
    if (status === "offline") return "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-bk-red/10 text-bk-red";
    return "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-bk-brown/10 text-bk-brown/60";
  }

  return (
    <div>
      <h1 className="font-heading text-2xl font-extrabold text-bk-brown mb-6">{t("title")}</h1>

      {devicesError && (
        <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-4">{devicesError}</p>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-10">
        <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 overflow-hidden">
          {devicesLoading ? (
            <p className="p-4 text-sm text-bk-brown/60">...</p>
          ) : devices.length === 0 ? (
            <p className="p-4 text-sm text-bk-brown/60">{t("no_devices")}</p>
          ) : (
            <ul className="divide-y divide-bk-brown/10">
              {devices.map((d) => (
                <li key={d.id} className="px-5 py-4">
                  <p className="font-semibold text-bk-brown">
                    {d.brand} {d.model}
                  </p>
                  <p className="text-xs text-bk-brown/60 mt-0.5">
                    {t("serial_number")}: {d.serial_number} · {t("branch")}: {branchName(d.branch_id)}
                  </p>
                  {d.ip_address && (
                    <p className="text-xs text-bk-brown/60 mt-0.5">
                      {t("ip_address")}: {d.ip_address}
                    </p>
                  )}
                  <div className="flex items-center gap-2 mt-2">
                    <span className={statusBadgeClass(d.status)}>{t("status_" + d.status)}</span>
                    <select
                      value={d.status}
                      onChange={(e) => handleStatusChange(d, e.target.value)}
                      className="text-xs border border-bk-brown/20 rounded-md px-1.5 py-0.5 bg-white"
                    >
                      {STATUSES.map((s) => (
                        <option key={s} value={s}>
                          {t("status_" + s)}
                        </option>
                      ))}
                    </select>
                  </div>
                  {(d.max_faces || d.max_fingerprints || d.max_cards || d.max_events) && (
                    <p className="text-[11px] text-bk-brown/50 mt-2">
                      {d.max_faces ? t("max_faces") + ": " + d.max_faces + "  " : ""}
                      {d.max_fingerprints ? t("max_fingerprints") + ": " + d.max_fingerprints + "  " : ""}
                      {d.max_cards ? t("max_cards") + ": " + d.max_cards + "  " : ""}
                      {d.max_events ? t("max_events") + ": " + d.max_events : ""}
                    </p>
                  )}
                  {d.verification_methods && d.verification_methods.length > 0 && (
                    <p className="text-[11px] text-bk-brown/50 mt-1">
                      {t("verification_methods")}:{" "}
                      {d.verification_methods.map((m) => t("method_" + m)).join(", ")}
                    </p>
                  )}
                </li>
              ))}
            </ul>
          )}
        </div>

        <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5">
          <h2 className="font-heading font-bold text-bk-brown mb-4">{t("new_device")}</h2>

          {createError && (
            <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-3">{createError}</p>
          )}
          {createOk && (
            <p className="text-sm text-green-700 bg-green-100 rounded-lg px-3 py-2 mb-3">{t("created_ok")}</p>
          )}

          <form onSubmit={handleCreateDevice} className="space-y-3 text-sm">
            <div>
              <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("branch")}</label>
              <select
                required
                value={form.branch_id}
                onChange={(e) => setForm({ ...form, branch_id: e.target.value })}
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
              <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("brand")}</label>
              <select
                required
                value={form.brand}
                onChange={(e) => setForm({ ...form, brand: e.target.value })}
                className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
              >
                <option value="">{t("select_brand")}</option>
                {BRANDS.map((b) => (
                  <option key={b} value={b}>
                    {b}
                  </option>
                ))}
              </select>
            </div>

            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("model")}</label>
                <input
                  required
                  value={form.model}
                  onChange={(e) => setForm({ ...form, model: e.target.value })}
                  className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("serial_number")}</label>
                <input
                  required
                  value={form.serial_number}
                  onChange={(e) => setForm({ ...form, serial_number: e.target.value })}
                  className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                />
              </div>
            </div>

            <div>
              <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("ip_address")}</label>
              <input
                value={form.ip_address}
                onChange={(e) => setForm({ ...form, ip_address: e.target.value })}
                className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                placeholder="192.168.1.50"
              />
            </div>

            <div className="grid grid-cols-4 gap-2">
              <div>
                <label className="block text-[10px] font-medium text-bk-brown/70 mb-1">{t("max_faces")}</label>
                <input
                  type="number"
                  min="0"
                  value={form.max_faces}
                  onChange={(e) => setForm({ ...form, max_faces: e.target.value })}
                  className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5 text-xs"
                />
              </div>
              <div>
                <label className="block text-[10px] font-medium text-bk-brown/70 mb-1">{t("max_fingerprints")}</label>
                <input
                  type="number"
                  min="0"
                  value={form.max_fingerprints}
                  onChange={(e) => setForm({ ...form, max_fingerprints: e.target.value })}
                  className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5 text-xs"
                />
              </div>
              <div>
                <label className="block text-[10px] font-medium text-bk-brown/70 mb-1">{t("max_cards")}</label>
                <input
                  type="number"
                  min="0"
                  value={form.max_cards}
                  onChange={(e) => setForm({ ...form, max_cards: e.target.value })}
                  className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5 text-xs"
                />
              </div>
              <div>
                <label className="block text-[10px] font-medium text-bk-brown/70 mb-1">{t("max_events")}</label>
                <input
                  type="number"
                  min="0"
                  value={form.max_events}
                  onChange={(e) => setForm({ ...form, max_events: e.target.value })}
                  className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5 text-xs"
                />
              </div>
            </div>

            <div>
              <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("verification_methods")}</label>
              <div className="flex flex-wrap gap-3">
                {METHODS.map((m) => (
                  <label key={m} className="flex items-center gap-1 text-xs text-bk-brown/80">
                    <input
                      type="checkbox"
                      checked={!!form.methods[m]}
                      onChange={() => toggleMethod(m)}
                    />
                    {t("method_" + m)}
                  </label>
                ))}
              </div>
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
        </div>
      </div>

      <h1 className="font-heading text-2xl font-extrabold text-bk-brown mb-6">{tb("title")}</h1>

      {bioError && (
        <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-4">{bioError}</p>
      )}
      {bioMsg && (
        <p className="text-sm text-green-700 bg-green-100 rounded-lg px-3 py-2 mb-4">{bioMsg}</p>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 overflow-hidden">
          {employees.length === 0 ? (
            <p className="p-4 text-sm text-bk-brown/60">...</p>
          ) : (
            <ul className="divide-y divide-bk-brown/10">
              {employees.map((emp) => (
                <li key={emp.id}>
                  <button
                    onClick={() => selectEmployee(emp)}
                    className={
                      selectedEmployee && selectedEmployee.id === emp.id
                        ? "w-full text-left px-5 py-4 transition bg-bk-orange/10"
                        : "w-full text-left px-5 py-4 transition hover:bg-bk-cream2"
                    }
                  >
                    <p className="font-semibold text-bk-brown">
                      {emp.first_name} {emp.last_name}
                    </p>
                    <p className="text-xs text-bk-brown/60 mt-0.5">{emp.position}</p>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>

        <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5">
          {!selectedEmployee ? (
            <p className="text-sm text-bk-brown/60">{tb("select_employee")}</p>
          ) : (
            <div>
              <h2 className="font-heading font-bold text-bk-brown mb-4">
                {selectedEmployee.first_name} {selectedEmployee.last_name}
              </h2>

              <div className="mb-4">
                {enrollmentsLoading ? (
                  <p className="text-sm text-bk-brown/60">...</p>
                ) : enrollments.length === 0 ? (
                  <p className="text-sm text-bk-brown/60">{tb("no_enrollments")}</p>
                ) : (
                  <div className="space-y-2">
                    {enrollments.map((en) => (
                      <div key={en.id} className="border border-bk-brown/10 rounded-lg p-3 text-xs">
                        <p className="font-semibold text-bk-brown">
                          {tb("type_" + en.biometric_type)}
                          {en.is_simulated && (
                            <span className="ml-2 inline-block rounded-full px-2 py-0.5 text-[9px] font-semibold bg-bk-orange/10 text-bk-orange">
                              {tb("simulated_badge")}
                            </span>
                          )}
                        </p>
                        <p className="text-bk-brown/60 mt-0.5">
                          {tb("enrolled_at")}: {en.enrolled_at}
                        </p>
                      </div>
                    ))}
                  </div>
                )}
              </div>

              <button
                onClick={handleGrantConsent}
                disabled={granting}
                className="text-xs font-semibold text-bk-brown border border-bk-brown/30 rounded-lg px-3 py-1.5 mb-4 disabled:opacity-50"
              >
                {tb("grant_consent")}
              </button>

              <form onSubmit={handleEnroll} className="space-y-3 text-sm border-t border-bk-brown/10 pt-4">
                <div>
                  <label className="block text-xs font-medium text-bk-brown/70 mb-1">{tb("device")}</label>
                  <select
                    required
                    value={enrollDeviceId}
                    onChange={(e) => setEnrollDeviceId(e.target.value)}
                    className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                  >
                    <option value="">{tb("select_device")}</option>
                    {devices
                      .filter((d) => !selectedEmployee.branch_id || d.branch_id === selectedEmployee.branch_id)
                      .map((d) => (
                        <option key={d.id} value={d.id}>
                          {d.brand} {d.model} ({d.serial_number})
                        </option>
                      ))}
                  </select>
                </div>

                <div>
                  <label className="block text-xs font-medium text-bk-brown/70 mb-1">{tb("biometric_type")}</label>
                  <select
                    value={enrollType}
                    onChange={(e) => setEnrollType(e.target.value)}
                    className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                  >
                    {BIOMETRIC_TYPES.map((bt) => (
                      <option key={bt} value={bt}>
                        {tb("type_" + bt)}
                      </option>
                    ))}
                  </select>
                </div>

                <button
                  type="submit"
                  disabled={enrolling}
                  className="text-xs font-semibold text-white rounded-lg px-4 py-2 disabled:opacity-50"
                  style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}
                >
                  {tb("enroll")}
                </button>
              </form>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
