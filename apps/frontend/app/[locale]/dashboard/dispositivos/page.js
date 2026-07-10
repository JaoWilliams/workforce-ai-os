"use client";

import { useEffect, useState } from "react";
import { useTranslations } from "next-intl";
import { Router, Fingerprint } from "lucide-react";
import { apiFetch } from "../../../../lib/api";
import { useToast } from "../../../../lib/toast";
import { LoadingState, EmptyState } from "../../../../lib/ui";

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
  const { showToast } = useToast();
  const [searchQuery, setSearchQuery] = useState("");

  const [devices, setDevices] = useState([]);
  const [branches, setBranches] = useState([]);
  const [devicesLoading, setDevicesLoading] = useState(true);
  const [devicesError, setDevicesError] = useState(null);

  const [selected, setSelected] = useState(null);
  const [editForm, setEditForm] = useState(null);
  const [savingEdit, setSavingEdit] = useState(false);
  const [editError, setEditError] = useState(null);

  const [form, setForm] = useState(emptyForm);
  const [creating, setCreating] = useState(false);
  const [createError, setCreateError] = useState(null);

  const [employees, setEmployees] = useState([]);
  const [selectedEmployee, setSelectedEmployee] = useState(null);
  const [enrollments, setEnrollments] = useState([]);
  const [enrollmentsLoading, setEnrollmentsLoading] = useState(false);
  const [enrollDeviceId, setEnrollDeviceId] = useState("");
  const [enrollType, setEnrollType] = useState("facial");
  const [granting, setGranting] = useState(false);
  const [enrolling, setEnrolling] = useState(false);
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

  const filteredDevices = devices.filter((d) => {
    const q = searchQuery.trim().toLowerCase();
    if (!q) return true;
    return (
      d.brand.toLowerCase().includes(q) ||
      d.model.toLowerCase().includes(q) ||
      d.serial_number.toLowerCase().includes(q) ||
      branchName(d.branch_id).toLowerCase().includes(q)
    );
  });

  function toggleMethod(key) {
    setForm((f) => ({ ...f, methods: { ...f.methods, [key]: !f.methods[key] } }));
  }

  function toggleEditMethod(key) {
    setEditForm((f) => ({
      ...f,
      verification_methods: f.verification_methods.includes(key)
        ? f.verification_methods.filter((m) => m !== key)
        : [...f.verification_methods, key],
    }));
  }

  function selectDevice(d) {
    setSelected(d);
    setEditError(null);
    setEditForm({
      model: d.model,
      serial_number: d.serial_number,
      ip_address: d.ip_address || "",
      status: d.status,
      max_faces: d.max_faces || "",
      max_fingerprints: d.max_fingerprints || "",
      max_cards: d.max_cards || "",
      max_events: d.max_events || "",
      verification_methods: d.verification_methods || [],
    });
  }

  function statusBadgeClass(status) {
    if (status === "online") return "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-green-100 text-green-700";
    if (status === "offline") return "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-bk-red/10 text-bk-red";
    return "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-bk-brown/10 text-bk-brown/60";
  }

  async function handleCreateDevice(e) {
    e.preventDefault();
    setCreating(true);
    setCreateError(null);
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
      showToast(t("created_ok"));
      loadDevices();
    } catch (err) {
      setCreateError(err.message);
      showToast(err.message, "error");
    } finally {
      setCreating(false);
    }
  }

  async function handleUpdateDevice(e) {
    e.preventDefault();
    if (!selected) return;
    setSavingEdit(true);
    setEditError(null);
    try {
      const payload = {
        model: editForm.model,
        serial_number: editForm.serial_number,
        ip_address: editForm.ip_address || null,
        status: editForm.status,
        max_faces: editForm.max_faces ? parseInt(editForm.max_faces, 10) : null,
        max_fingerprints: editForm.max_fingerprints ? parseInt(editForm.max_fingerprints, 10) : null,
        max_cards: editForm.max_cards ? parseInt(editForm.max_cards, 10) : null,
        max_events: editForm.max_events ? parseInt(editForm.max_events, 10) : null,
        verification_methods: editForm.verification_methods,
      };
      const updated = await apiFetch("/api/devices/" + selected.id, {
        method: "PATCH",
        body: JSON.stringify(payload),
      });
      showToast(t("updated_ok"));
      setSelected(updated);
      loadDevices();
    } catch (err) {
      setEditError(err.message);
      showToast(err.message, "error");
    } finally {
      setSavingEdit(false);
    }
  }

  async function handleToggleActive() {
    if (!selected) return;
    setEditError(null);
    try {
      if (selected.active) {
        if (!confirm(t("deactivate_confirm"))) return;
        await apiFetch("/api/devices/" + selected.id, { method: "DELETE" });
        showToast(t("deactivated_ok_toast"));
      } else {
        const updated = await apiFetch("/api/devices/" + selected.id, {
          method: "PATCH",
          body: JSON.stringify({ active: true }),
        });
        showToast(t("reactivated_ok_toast"));
      }
      loadDevices();
      setSelected(null);
    } catch (err) {
      setEditError(err.message);
      showToast(err.message, "error");
    }
  }

  async function selectEmployee(emp) {
    setSelectedEmployee(emp);
    setEnrollments([]);
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
    setBioError(null);
    try {
      await apiFetch("/api/legal/consent", {
        method: "POST",
        body: JSON.stringify({ consent_type: "biometric", employee_id: selectedEmployee.id }),
      });
      showToast(tb("consent_granted"));
    } catch (err) {
      setBioError(err.message);
      showToast(err.message, "error");
    } finally {
      setGranting(false);
    }
  }

  async function handleEnroll(e) {
    e.preventDefault();
    if (!selectedEmployee || !enrollDeviceId) return;
    setEnrolling(true);
    setBioError(null);
    try {
      await apiFetch("/api/employees/" + selectedEmployee.id + "/biometric-enrollments", {
        method: "POST",
        body: JSON.stringify({ device_id: enrollDeviceId, biometric_type: enrollType }),
      });
      showToast(tb("enroll_ok"));
      const data = await apiFetch("/api/employees/" + selectedEmployee.id + "/biometric-enrollments");
      setEnrollments(data);
    } catch (err) {
      setBioError(err.message);
      showToast(err.message, "error");
    } finally {
      setEnrolling(false);
    }
  }

  return (
    <div>
      <h1 className="font-heading text-2xl font-extrabold text-bk-brown mb-6">{t("title")}</h1>
      {devicesError && (
        <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-4">{devicesError}</p>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-10">
        <div className="space-y-6">
          <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 overflow-hidden">
            <div className="p-3 border-b border-bk-brown/10">
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder={t("search_placeholder")}
                className="w-full border border-bk-brown/20 rounded-md px-3 py-1.5 text-sm"
              />
            </div>
            {devicesLoading ? (
              <LoadingState />
            ) : filteredDevices.length === 0 ? (
              <EmptyState icon={Router} message={t("no_devices")} />
            ) : (
              <ul className="divide-y divide-bk-brown/10">
                {filteredDevices.map((d) => (
                  <li key={d.id}>
                    <button
                      onClick={() => selectDevice(d)}
                      className={
                        selected && selected.id === d.id
                          ? "w-full text-left px-5 py-4 transition bg-bk-orange/10"
                          : "w-full text-left px-5 py-4 transition hover:bg-bk-cream2"
                      }
                    >
                      <div className="flex items-center justify-between">
                        <p className="font-semibold text-bk-brown">
                          {d.brand} {d.model}
                        </p>
                        <span
                          className={
                            d.active
                              ? "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-green-100 text-green-700"
                              : "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-bk-brown/10 text-bk-brown/60"
                          }
                        >
                          {d.active ? t("active") : t("inactive")}
                        </span>
                      </div>
                      <p className="text-xs text-bk-brown/60 mt-0.5">
                        {t("serial_number")}: {d.serial_number} · {t("branch")}: {branchName(d.branch_id)}
                      </p>
                      <div className="mt-2">
                        <span className={statusBadgeClass(d.status)}>{t("status_" + d.status)}</span>
                      </div>
                    </button>
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

        <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 h-fit">
          {!selected ? (
            <p className="text-sm text-bk-brown/60">{t("select_device_prompt")}</p>
          ) : (
            <>
              <div className="flex items-center justify-between mb-4">
                <h2 className="font-heading font-bold text-bk-brown">
                  {t("edit_device")} — {selected.brand} {selected.model}
                </h2>
                <button
                  onClick={handleToggleActive}
                  className={
                    selected.active
                      ? "text-xs font-semibold text-bk-red border border-bk-red/30 rounded-lg px-3 py-1.5"
                      : "text-xs font-semibold text-green-700 border border-green-300 rounded-lg px-3 py-1.5"
                  }
                >
                  {selected.active ? t("deactivate_device") : t("reactivate_device")}
                </button>
              </div>
              {editError && (
                <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-3">{editError}</p>
              )}
              <form onSubmit={handleUpdateDevice} className="space-y-3 text-sm">
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("model")}</label>
                    <input
                      required
                      value={editForm.model}
                      onChange={(e) => setEditForm({ ...editForm, model: e.target.value })}
                      className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                    />
                  </div>
                  <div>
                    <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("serial_number")}</label>
                    <input
                      required
                      value={editForm.serial_number}
                      onChange={(e) => setEditForm({ ...editForm, serial_number: e.target.value })}
                      className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                    />
                  </div>
                </div>
                <div>
                  <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("ip_address")}</label>
                  <input
                    value={editForm.ip_address}
                    onChange={(e) => setEditForm({ ...editForm, ip_address: e.target.value })}
                    className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                  />
                </div>
                <div>
                  <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("status")}</label>
                  <select
                    value={editForm.status}
                    onChange={(e) => setEditForm({ ...editForm, status: e.target.value })}
                    className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                  >
                    {STATUSES.map((s) => (
                      <option key={s} value={s}>
                        {t("status_" + s)}
                      </option>
                    ))}
                  </select>
                </div>
                <div className="grid grid-cols-4 gap-2">
                  <div>
                    <label className="block text-[10px] font-medium text-bk-brown/70 mb-1">{t("max_faces")}</label>
                    <input
                      type="number"
                      min="0"
                      value={editForm.max_faces}
                      onChange={(e) => setEditForm({ ...editForm, max_faces: e.target.value })}
                      className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5 text-xs"
                    />
                  </div>
                  <div>
                    <label className="block text-[10px] font-medium text-bk-brown/70 mb-1">{t("max_fingerprints")}</label>
                    <input
                      type="number"
                      min="0"
                      value={editForm.max_fingerprints}
                      onChange={(e) => setEditForm({ ...editForm, max_fingerprints: e.target.value })}
                      className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5 text-xs"
                    />
                  </div>
                  <div>
                    <label className="block text-[10px] font-medium text-bk-brown/70 mb-1">{t("max_cards")}</label>
                    <input
                      type="number"
                      min="0"
                      value={editForm.max_cards}
                      onChange={(e) => setEditForm({ ...editForm, max_cards: e.target.value })}
                      className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5 text-xs"
                    />
                  </div>
                  <div>
                    <label className="block text-[10px] font-medium text-bk-brown/70 mb-1">{t("max_events")}</label>
                    <input
                      type="number"
                      min="0"
                      value={editForm.max_events}
                      onChange={(e) => setEditForm({ ...editForm, max_events: e.target.value })}
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
                          checked={editForm.verification_methods.includes(m)}
                          onChange={() => toggleEditMethod(m)}
                        />
                        {t("method_" + m)}
                      </label>
                    ))}
                  </div>
                </div>
                <button
                  type="submit"
                  disabled={savingEdit}
                  className="text-xs font-semibold text-white rounded-lg px-4 py-2 disabled:opacity-50"
                  style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}
                >
                  {t("save_changes")}
                </button>
              </form>
            </>
          )}
        </div>
      </div>

      <div className="flex items-center gap-2 mb-6">
        <Fingerprint size={20} className="text-bk-brown/60" />
        <h1 className="font-heading text-2xl font-extrabold text-bk-brown">{tb("title")}</h1>
      </div>
      {bioError && (
        <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-4">{bioError}</p>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 overflow-hidden">
          {employees.length === 0 ? (
            <LoadingState compact />
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
                      .filter((d) => d.active && (!selectedEmployee.branch_id || d.branch_id === selectedEmployee.branch_id))
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
