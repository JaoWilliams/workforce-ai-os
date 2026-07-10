"use client";

import { useEffect, useState } from "react";
import { useTranslations } from "next-intl";
import { apiFetch, apiFetchBlob } from "../../../../lib/api";
import { useToast } from "../../../../lib/toast";
import { usePermissions } from "../../../../lib/permissions";

const ID_TYPES = ["cedula_fisica", "cedula_juridica", "dimex", "pasaporte"];
const CONTRACT_TYPES = ["indefinido", "plazo_fijo", "por_obra"];
const CURRENCIES = ["CRC", "USD", "GTQ", "HNL", "NIO", "PAB"];
const PAY_FREQUENCIES = ["semanal", "quincenal", "bisemanal", "mensual"];

const emptyForm = {
  branch_id: "",
  first_name: "",
  last_name: "",
  id_type: "cedula_fisica",
  id_number: "",
  email: "",
  phone: "",
  position: "",
  hire_date: "",
};

const emptyContractForm = {
  contract_type: "indefinido",
  start_date: "",
  end_date: "",
  base_salary: "",
  currency: "CRC",
  pay_frequency: "mensual",
};

export default function EmpleadosPage() {
  const t = useTranslations("employees");  
  const { hasPermission } = usePermissions();
  const { showToast } = useToast();

  const [employees, setEmployees] = useState([]);
  const [branches, setBranches] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [selected, setSelected] = useState(null);
  const [searchQuery, setSearchQuery] = useState("");
  const [contracts, setContracts] = useState([]);
  const [contractsLoading, setContractsLoading] = useState(false);
  const [downloadError, setDownloadError] = useState(null);

  const [form, setForm] = useState(emptyForm);
  const [creating, setCreating] = useState(false);
  const [createError, setCreateError] = useState(null);

  const [editForm, setEditForm] = useState(null);
  const [savingEdit, setSavingEdit] = useState(false);
  const [editError, setEditError] = useState(null);

  const [contractForm, setContractForm] = useState(emptyContractForm);
  const [creatingContract, setCreatingContract] = useState(false);
  const [contractError, setContractError] = useState(null);

  useEffect(() => {
    loadEmployees();
    apiFetch("/api/branches").then(setBranches).catch(() => {});
  }, []);

  function loadEmployees() {
    setLoading(true);
    apiFetch("/api/employees")
      .then(setEmployees)
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }

  function branchName(id) {
    const b = branches.find((x) => x.id === id);
    return b ? b.name : id;
  }

  const filteredEmployees = employees.filter((emp) => {
    const q = searchQuery.trim().toLowerCase();
    if (!q) return true;
    return (
      emp.first_name.toLowerCase().includes(q) ||
      emp.last_name.toLowerCase().includes(q) ||
      emp.id_number.toLowerCase().includes(q) ||
      emp.position.toLowerCase().includes(q)
    );
  });

  async function selectEmployee(emp) {
    setSelected(emp);
    setEditForm({
      email: emp.email || "",
      phone: emp.phone || "",
      position: emp.position,
      active: emp.active,
    });
    setContractForm(emptyContractForm);
    setContracts([]);
    setContractsLoading(true);
    try {
      const data = await apiFetch("/api/employees/" + emp.id + "/contracts");
      setContracts(data);
    } catch (err) {
      setError(err.message);
    } finally {
      setContractsLoading(false);
    }
  }

  async function downloadPdf(contract) {
    setDownloadError(null);
    try {
      const blob = await apiFetchBlob(
        "/api/employees/" + selected.id + "/contracts/" + contract.id + "/pdf"
      );
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = "contrato-" + contract.id + ".pdf";
      document.body.appendChild(a);
      a.click();
      a.remove();
      window.URL.revokeObjectURL(url);
    } catch (err) {
      setDownloadError(err.message);
    }
  }

  function contractTypeLabel(type) {
    const key = "contract_type_" + type;
    const translated = t(key);
    return translated === key ? type : translated;
  }

  function payFrequencyLabel(freq) {
    const key = "pay_frequency_" + freq;
    const translated = t(key);
    return translated === key ? freq : translated;
  }

  function idTypeLabel(type) {
    const key = "id_type_" + type;
    const translated = t(key);
    return translated === key ? type : translated;
  }

  function formatMoney(amount, currency) {
    return new Intl.NumberFormat("es-CR", {
      style: "currency",
      currency: currency || "CRC",
      maximumFractionDigits: 2,
    }).format(amount);
  }

  async function handleCreateEmployee(e) {
    e.preventDefault();
    setCreating(true);
    setCreateError(null);
    try {
      const payload = {
        branch_id: form.branch_id,
        first_name: form.first_name,
        last_name: form.last_name,
        id_type: form.id_type,
        id_number: form.id_number,
        email: form.email || null,
        phone: form.phone || null,
        position: form.position,
        hire_date: form.hire_date,
      };
      await apiFetch("/api/employees", { method: "POST", body: JSON.stringify(payload) });
      showToast(t("created_ok_toast", { name: form.first_name + " " + form.last_name }));
      setForm(emptyForm);
      loadEmployees();
    } catch (err) {
      setCreateError(err.message);
      showToast(err.message, "error");
    } finally {
      setCreating(false);
    }
  }

  async function handleUpdateEmployee(e) {
    e.preventDefault();
    if (!selected) return;
    setSavingEdit(true);
    setEditError(null);
    try {
      const payload = {
        email: editForm.email || null,
        phone: editForm.phone || null,
        position: editForm.position,
        active: editForm.active,
      };
      const updated = await apiFetch("/api/employees/" + selected.id, {
        method: "PATCH",
        body: JSON.stringify(payload),
      });
      showToast(t("updated_ok_toast", { name: updated.first_name + " " + updated.last_name }));
      setSelected(updated);
      loadEmployees();
    } catch (err) {
      setEditError(err.message);
      showToast(err.message, "error");
    } finally {
      setSavingEdit(false);
    }
  }

  async function handleCreateContract(e) {
    e.preventDefault();
    if (!selected) return;
    setCreatingContract(true);
    setContractError(null);
    try {
      const payload = {
        contract_type: contractForm.contract_type,
        start_date: contractForm.start_date,
        end_date: contractForm.end_date || null,
        base_salary: parseFloat(contractForm.base_salary),
        currency: contractForm.currency,
        pay_frequency: contractForm.pay_frequency,
      };
      await apiFetch("/api/employees/" + selected.id + "/contracts", {
        method: "POST",
        body: JSON.stringify(payload),
      });
      showToast(
        t("contract_created_ok_toast", { name: selected.first_name + " " + selected.last_name })
      );
      setContractForm(emptyContractForm);
      const data = await apiFetch("/api/employees/" + selected.id + "/contracts");
      setContracts(data);
    } catch (err) {
      setContractError(err.message);
      showToast(err.message, "error");
    } finally {
      setCreatingContract(false);
    }
  }

  return (
    <div>
      <h1 className="font-heading text-2xl font-extrabold text-bk-brown mb-6">
        {t("title")}
      </h1>

      {error && (
        <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-4">{error}</p>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-10">
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
          {loading ? (
            <p className="p-4 text-sm text-bk-brown/60">...</p>
          ) : filteredEmployees.length === 0 ? (
            <p className="p-4 text-sm text-bk-brown/60">{t("no_employees")}</p>
          ) : (
            <ul className="divide-y divide-bk-brown/10">
              {filteredEmployees.map((emp) => (
                <li key={emp.id}>
                  <button
                    onClick={() => selectEmployee(emp)}
                    className={
                      selected && selected.id === emp.id
                        ? "w-full text-left px-5 py-4 transition bg-bk-orange/10"
                        : "w-full text-left px-5 py-4 transition hover:bg-bk-cream2"
                    }
                  >
                    <p className="font-semibold text-bk-brown">
                      {emp.first_name} {emp.last_name}
                    </p>
                    <p className="text-xs text-bk-brown/60 mt-0.5">
                      {t("id_number")}: {emp.id_number} · {t("position")}: {emp.position}
                    </p>
                    <p className="text-xs text-bk-brown/60 mt-0.5">{branchName(emp.branch_id)}</p>
                    <p className="text-xs mt-1">
                      <span
                        className={
                          emp.active
                            ? "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-green-100 text-green-700"
                            : "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-bk-brown/10 text-bk-brown/60"
                        }
                      >
                        {emp.active ? t("active") : t("inactive")}
                      </span>
                    </p>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>

        <div className="space-y-6">
          {!selected ? (
            <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5">
              <p className="text-sm text-bk-brown/60">{t("select_employee")}</p>
            </div>
          ) : (
            <>
              <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5">
                <h2 className="font-heading font-bold text-bk-brown mb-4">
                  {t("edit_employee")} — {selected.first_name} {selected.last_name}
                </h2>
                {editError && (
                  <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-3">{editError}</p>
                )}
                {hasPermission("employees.manage") && (
                <form onSubmit={handleUpdateEmployee} className="space-y-3 text-sm">
                  <div className="grid grid-cols-2 gap-3">
                    <div>
                      <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("email")}</label>
                      <input
                        type="email"
                        value={editForm.email}
                        onChange={(e) => setEditForm({ ...editForm, email: e.target.value })}
                        className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                      />
                    </div>
                    <div>
                      <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("phone")}</label>
                      <input
                        value={editForm.phone}
                        onChange={(e) => setEditForm({ ...editForm, phone: e.target.value })}
                        className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                      />
                    </div>
                  </div>
                  <div>
                    <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("position")}</label>
                    <input
                      required
                      value={editForm.position}
                      onChange={(e) => setEditForm({ ...editForm, position: e.target.value })}
                      className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                    />
                  </div>
                  <label className="flex items-center gap-2 text-xs text-bk-brown/70">
                    <input
                      type="checkbox"
                      checked={editForm.active}
                      onChange={(e) => setEditForm({ ...editForm, active: e.target.checked })}
                    />
                    {t("active")}
                  </label>
                  <button
                    type="submit"
                    disabled={savingEdit}
                    className="text-xs font-semibold text-white rounded-lg px-4 py-2 disabled:opacity-50"
                    style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}
                  >
                    {t("save_changes")}
                  </button>
                </form>
                )}
              </div>

              <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5">
                <h2 className="font-heading font-bold text-bk-brown mb-4">{t("contracts_title")}</h2>

                {contractsLoading ? (
                  <p className="text-sm text-bk-brown/60">...</p>
                ) : contracts.length === 0 ? (
                  <p className="text-sm text-bk-brown/60 mb-4">{t("no_contracts")}</p>
                ) : (
                  <div className="space-y-3 mb-5">
                    {downloadError && (
                      <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2">
                        {downloadError}
                      </p>
                    )}
                    {contracts.map((c) => (
                      <div key={c.id} className="border border-bk-brown/10 rounded-lg p-4 text-sm">
                        <p className="font-semibold text-bk-brown mb-1">
                          {contractTypeLabel(c.contract_type)}
                        </p>
                        <p className="text-bk-brown/70">
                          {t("start_date")}: {c.start_date} · {t("end_date")}: {c.end_date || t("no_end_date")}
                        </p>
                        <p className="text-bk-brown/70 mb-3">
                          {t("base_salary")}: {formatMoney(c.base_salary, c.currency)} · {t("pay_frequency")}: {payFrequencyLabel(c.pay_frequency)}
                        </p>
                        <button
                          onClick={() => downloadPdf(c)}
                          className="text-xs font-semibold text-white rounded-lg px-3 py-1.5"
                          style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}
                        >
                          {t("download_pdf")}
                        </button>
                      </div>
                    ))}
                  </div>
                )}

                <div className="border-t border-bk-brown/10 pt-4">
                  <h3 className="font-heading font-bold text-bk-brown mb-3 text-sm">{t("new_contract")}</h3>
                  {contractError && (
                    <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-3">{contractError}</p>
                  )}
                  {hasPermission("employees.manage") && (
                  <form onSubmit={handleCreateContract} className="space-y-3 text-sm">
                    <div>
                      <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("contract_type")}</label>
                      <select
                        value={contractForm.contract_type}
                        onChange={(e) => setContractForm({ ...contractForm, contract_type: e.target.value })}
                        className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                      >
                        {CONTRACT_TYPES.map((ct) => (
                          <option key={ct} value={ct}>
                            {contractTypeLabel(ct)}
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
                          value={contractForm.start_date}
                          onChange={(e) => setContractForm({ ...contractForm, start_date: e.target.value })}
                          className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                        />
                      </div>
                      <div>
                        <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("end_date")}</label>
                        <input
                          type="date"
                          value={contractForm.end_date}
                          onChange={(e) => setContractForm({ ...contractForm, end_date: e.target.value })}
                          className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                        />
                      </div>
                    </div>
                    <div className="grid grid-cols-2 gap-3">
                      <div>
                        <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("base_salary")}</label>
                        <input
                          type="number"
                          step="0.01"
                          required
                          value={contractForm.base_salary}
                          onChange={(e) => setContractForm({ ...contractForm, base_salary: e.target.value })}
                          className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                        />
                      </div>
                      <div>
                        <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("currency")}</label>
                        <select
                          value={contractForm.currency}
                          onChange={(e) => setContractForm({ ...contractForm, currency: e.target.value })}
                          className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                        >
                          {CURRENCIES.map((c) => (
                            <option key={c} value={c}>
                              {c}
                            </option>
                          ))}
                        </select>
                      </div>
                    </div>
                    <div>
                      <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("pay_frequency")}</label>
                      <select
                        value={contractForm.pay_frequency}
                        onChange={(e) => setContractForm({ ...contractForm, pay_frequency: e.target.value })}
                        className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                      >
                        {PAY_FREQUENCIES.map((f) => (
                          <option key={f} value={f}>
                            {payFrequencyLabel(f)}
                          </option>
                        ))}
                      </select>
                      <p className="text-[11px] text-bk-brown/50 mt-1">{t("pay_frequency_hint")}</p>
                    </div>
                    <button
                      type="submit"
                      disabled={creatingContract}
                      className="text-xs font-semibold text-white rounded-lg px-4 py-2 disabled:opacity-50"
                      style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}
                    >
                      {t("new_contract")}
                    </button>
                  </form>
                  )}
                </div>
              </div>
            </>
          )}
        </div>
      </div>

      <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 max-w-2xl">
        <h2 className="font-heading font-bold text-bk-brown mb-4">{t("new_employee")}</h2>

        {createError && (
          <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-3">{createError}</p>
        )}

        {hasPermission("employees.manage") && (
        <form onSubmit={handleCreateEmployee} className="space-y-3 text-sm">
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

          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("first_name")}</label>
              <input
                required
                value={form.first_name}
                onChange={(e) => setForm({ ...form, first_name: e.target.value })}
                className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("last_name")}</label>
              <input
                required
                value={form.last_name}
                onChange={(e) => setForm({ ...form, last_name: e.target.value })}
                className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
              />
            </div>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("id_type")}</label>
              <select
                value={form.id_type}
                onChange={(e) => setForm({ ...form, id_type: e.target.value })}
                className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
              >
                {ID_TYPES.map((it) => (
                  <option key={it} value={it}>
                    {idTypeLabel(it)}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("id_number")}</label>
              <input
                required
                value={form.id_number}
                onChange={(e) => setForm({ ...form, id_number: e.target.value })}
                className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
              />
            </div>
          </div>

          <div>
            <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("position")}</label>
            <input
              required
              value={form.position}
              onChange={(e) => setForm({ ...form, position: e.target.value })}
              className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
            />
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("email")}</label>
              <input
                type="email"
                value={form.email}
                onChange={(e) => setForm({ ...form, email: e.target.value })}
                className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("phone")}</label>
              <input
                value={form.phone}
                onChange={(e) => setForm({ ...form, phone: e.target.value })}
                className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
              />
            </div>
          </div>

          <div>
            <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("hire_date")}</label>
            <input
              type="date"
              required
              value={form.hire_date}
              onChange={(e) => setForm({ ...form, hire_date: e.target.value })}
              className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
            />
          </div>

          <button
            type="submit"
            disabled={creating}
            className="text-xs font-semibold text-white rounded-lg px-4 py-2 disabled:opacity-50"
            style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}
          >
            {t("create_employee")}
          </button>
        </form>
        )}
      </div>
    </div>
  );
}
