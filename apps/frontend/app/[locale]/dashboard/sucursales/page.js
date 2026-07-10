"use client";

import { useEffect, useState } from "react";
import { useTranslations } from "next-intl";
import { apiFetch } from "../../../../lib/api";
import { useToast } from "../../../../lib/toast";

const emptyCreateForm = { code: "", name: "" };

export default function SucursalesPage() {
  const t = useTranslations("branches");
  const { showToast } = useToast();

  const [branches, setBranches] = useState([]);
  const [employees, setEmployees] = useState([]);
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const [selected, setSelected] = useState(null);
  const [searchQuery, setSearchQuery] = useState("");
  const [editForm, setEditForm] = useState(null);
  const [saving, setSaving] = useState(false);

  const [createForm, setCreateForm] = useState(emptyCreateForm);
  const [creating, setCreating] = useState(false);

  useEffect(() => {
    loadAll();
  }, []);

  function loadAll() {
    setLoading(true);
    Promise.all([
      apiFetch("/api/branches"),
      apiFetch("/api/employees"),
      apiFetch("/api/auth/users"),
    ])
      .then(([b, e, u]) => {
        setBranches(b);
        setEmployees(e);
        setUsers(u);
      })
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }

  function selectBranch(branch) {
    setSelected(branch);
    setEditForm({
      code: branch.code,
      name: branch.name,
      accounting_account: branch.accounting_account || "",
      supervisor_user_id: branch.supervisor_user_id || "",
    });
  }

  async function handleCreate(e) {
    e.preventDefault();
    setCreating(true);
    setError(null);
    try {
      const created = await apiFetch("/api/branches", {
        method: "POST",
        body: JSON.stringify(createForm),
      });
      showToast(t("created_ok_toast", { name: created.name }));
      setCreateForm(emptyCreateForm);
      loadAll();
    } catch (err) {
      setError(err.message);
      showToast(err.message, "error");
    } finally {
      setCreating(false);
    }
  }

  async function handleUpdate(e) {
    e.preventDefault();
    if (!selected) return;
    setSaving(true);
    setError(null);
    try {
      const payload = {
        code: editForm.code,
        name: editForm.name,
        accounting_account: editForm.accounting_account || null,
        supervisor_user_id: editForm.supervisor_user_id || null,
      };
      const updated = await apiFetch("/api/branches/" + selected.id, {
        method: "PATCH",
        body: JSON.stringify(payload),
      });
      showToast(t("updated_ok_toast", { name: updated.name }));
      loadAll();
      setSelected(updated);
    } catch (err) {
      setError(err.message);
      showToast(err.message, "error");
    } finally {
      setSaving(false);
    }
  }

  async function handleToggleActive() {
    if (!selected) return;
    setError(null);
    try {
      if (selected.active) {
        if (!confirm(t("deactivate_confirm"))) return;
        await apiFetch("/api/branches/" + selected.id, { method: "DELETE" });
        showToast(t("deactivated_ok_toast", { name: selected.name }));
      } else {
        const updated = await apiFetch("/api/branches/" + selected.id, {
          method: "PATCH",
          body: JSON.stringify({ active: true }),
        });
        showToast(t("reactivated_ok_toast", { name: updated.name }));
      }
      loadAll();
      setSelected(null);
    } catch (err) {
      setError(err.message);
      showToast(err.message, "error");
    }
  }

  function userLabel(id) {
    const u = users.find((x) => x.id === id);
    return u ? u.email : id;
  }

  const filteredBranches = branches.filter((b) => {
    const q = searchQuery.trim().toLowerCase();
    if (!q) return true;
    return b.name.toLowerCase().includes(q) || b.code.toLowerCase().includes(q);
  });

  const branchEmployees = selected
    ? employees.filter((e) => e.branch_id === selected.id)
    : [];

  return (
    <div>
      <h1 className="font-heading text-2xl font-extrabold text-bk-brown mb-6">
        {t("title")}
      </h1>

      {error && (
        <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-4">{error}</p>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
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
            {loading ? (
              <p className="p-4 text-sm text-bk-brown/60">...</p>
            ) : filteredBranches.length === 0 ? (
              <p className="p-4 text-sm text-bk-brown/60">{t("no_employees")}</p>
            ) : (
              <ul className="divide-y divide-bk-brown/10">
                {filteredBranches.map((b) => (
                  <li key={b.id}>
                    <button
                      onClick={() => selectBranch(b)}
                      className={
                        selected && selected.id === b.id
                          ? "w-full text-left px-5 py-4 transition bg-bk-orange/10"
                          : "w-full text-left px-5 py-4 transition hover:bg-bk-cream2"
                      }
                    >
                      <div className="flex items-center justify-between">
                        <p className="font-semibold text-bk-brown">{b.name}</p>
                        <span
                          className={
                            b.active
                              ? "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-green-100 text-green-700"
                              : "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-bk-brown/10 text-bk-brown/60"
                          }
                        >
                          {b.active ? t("active") : t("inactive")}
                        </span>
                      </div>
                      <p className="text-xs text-bk-brown/60 mt-0.5">
                        {b.code} · {t("employee_count")}: {b.employee_count}
                      </p>
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>

          <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5">
            <h2 className="font-heading font-bold text-bk-brown mb-4">{t("new_branch")}</h2>
            <form onSubmit={handleCreate} className="space-y-3 text-sm">
              <div>
                <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("code")}</label>
                <input
                  required
                  value={createForm.code}
                  onChange={(e) => setCreateForm({ ...createForm, code: e.target.value })}
                  className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("name")}</label>
                <input
                  required
                  value={createForm.name}
                  onChange={(e) => setCreateForm({ ...createForm, name: e.target.value })}
                  className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                />
              </div>
              <button
                type="submit"
                disabled={creating}
                className="text-xs font-semibold text-white rounded-lg px-4 py-2 disabled:opacity-50"
                style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}
              >
                {t("create_branch")}
              </button>
            </form>
          </div>
        </div>

        <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5">
          {!selected ? (
            <p className="text-sm text-bk-brown/60">{t("select_branch")}</p>
          ) : (
            <div className="space-y-6">
              <div>
                <div className="flex items-center justify-between mb-4">
                  <h2 className="font-heading font-bold text-bk-brown">{t("edit_branch")}</h2>
                  <button
                    onClick={handleToggleActive}
                    className={
                      selected.active
                        ? "text-xs font-semibold text-bk-red border border-bk-red/30 rounded-lg px-3 py-1.5"
                        : "text-xs font-semibold text-green-700 border border-green-300 rounded-lg px-3 py-1.5"
                    }
                  >
                    {selected.active ? t("deactivate_branch") : t("reactivate_branch")}
                  </button>
                </div>

                <form onSubmit={handleUpdate} className="space-y-3 text-sm">
                  <div className="grid grid-cols-2 gap-3">
                    <div>
                      <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("code")}</label>
                      <input
                        required
                        value={editForm.code}
                        onChange={(e) => setEditForm({ ...editForm, code: e.target.value })}
                        className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                      />
                    </div>
                    <div>
                      <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("name")}</label>
                      <input
                        required
                        value={editForm.name}
                        onChange={(e) => setEditForm({ ...editForm, name: e.target.value })}
                        className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                      />
                    </div>
                  </div>

                  <div>
                    <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("accounting_account")}</label>
                    <input
                      value={editForm.accounting_account}
                      onChange={(e) => setEditForm({ ...editForm, accounting_account: e.target.value })}
                      className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                    />
                  </div>

                  <div>
                    <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("supervisor")}</label>
                    <select
                      value={editForm.supervisor_user_id}
                      onChange={(e) => setEditForm({ ...editForm, supervisor_user_id: e.target.value })}
                      className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                    >
                      <option value="">{t("no_supervisor")}</option>
                      {users.map((u) => (
                        <option key={u.id} value={u.id}>
                          {u.email}
                        </option>
                      ))}
                    </select>
                  </div>

                  <button
                    type="submit"
                    disabled={saving}
                    className="text-xs font-semibold text-white rounded-lg px-4 py-2 disabled:opacity-50"
                    style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}
                  >
                    {t("save_changes")}
                  </button>
                </form>
              </div>

              <div className="border-t border-bk-brown/10 pt-4">
                <h3 className="font-heading font-bold text-bk-brown mb-3 text-sm">
                  {t("employees_in_branch")} ({branchEmployees.length})
                </h3>
                {branchEmployees.length === 0 ? (
                  <p className="text-sm text-bk-brown/60">{t("no_employees")}</p>
                ) : (
                  <ul className="space-y-2">
                    {branchEmployees.map((e) => (
                      <li
                        key={e.id}
                        className="text-sm border border-bk-brown/10 rounded-lg px-3 py-2 flex items-center justify-between"
                      >
                        <span className="text-bk-brown">
                          {e.first_name} {e.last_name}
                        </span>
                        <span className="text-xs text-bk-brown/60">{e.position}</span>
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
