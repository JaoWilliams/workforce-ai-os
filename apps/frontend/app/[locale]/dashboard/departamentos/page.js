"use client";

import { useEffect, useState } from "react";
import { useTranslations } from "next-intl";
import { Building } from "lucide-react";
import { apiFetch } from "../../../../lib/api";
import { useToast } from "../../../../lib/toast";
import { usePermissions } from "../../../../lib/permissions";
import { LoadingState, EmptyState } from "../../../../lib/ui";

export default function DepartamentosPage() {
  const t = useTranslations("departments");
  const { hasPermission } = usePermissions();
  const { showToast } = useToast();
  const canManage = hasPermission("catalogs.manage");

  const [departments, setDepartments] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [searchQuery, setSearchQuery] = useState("");

  const [name, setName] = useState("");
  const [creating, setCreating] = useState(false);
  const [createError, setCreateError] = useState(null);

  const [selected, setSelected] = useState(null);
  const [editName, setEditName] = useState("");
  const [editActive, setEditActive] = useState(true);
  const [saving, setSaving] = useState(false);
  const [editError, setEditError] = useState(null);

  useEffect(() => {
    load();
  }, []);

  function load() {
    setLoading(true);
    apiFetch("/api/departments")
      .then(setDepartments)
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }

  function selectDepartment(d) {
    setSelected(d);
    setEditName(d.name);
    setEditActive(d.active);
    setEditError(null);
  }

  async function handleCreate(e) {
    e.preventDefault();
    setCreating(true);
    setCreateError(null);
    try {
      await apiFetch("/api/departments", { method: "POST", body: JSON.stringify({ name }) });
      setName("");
      showToast(t("saved_ok"));
      load();
    } catch (err) {
      setCreateError(err.message);
    } finally {
      setCreating(false);
    }
  }

  async function handleSaveEdit(e) {
    e.preventDefault();
    if (!selected) return;
    setSaving(true);
    setEditError(null);
    try {
      await apiFetch("/api/departments/" + selected.id, {
        method: "PATCH",
        body: JSON.stringify({ name: editName, active: editActive }),
      });
      showToast(t("saved_ok"));
      setSelected(null);
      load();
    } catch (err) {
      setEditError(err.message);
    } finally {
      setSaving(false);
    }
  }

  async function handleDeactivate(d) {
    try {
      await apiFetch("/api/departments/" + d.id, { method: "DELETE" });
      showToast(t("saved_ok"));
      setSelected(null);
      load();
    } catch (err) {
      showToast(err.message, "error");
    }
  }

  const filtered = departments.filter((d) =>
    searchQuery ? d.name.toLowerCase().includes(searchQuery.toLowerCase()) : true
  );

  return (
    <div>
      <h1 className="font-heading text-2xl font-extrabold text-bk-brown mb-2">{t("title")}</h1>
      <p className="text-sm text-bk-brown/60 mb-6">{t("subtitle")}</p>

      {error && <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-4">{error}</p>}

      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <div className="md:col-span-2 space-y-4">
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder={t("search_placeholder")}
            className="w-full border border-bk-brown/20 rounded-md px-3 py-2 text-sm"
          />
          <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 overflow-hidden">
            {loading ? (
              <LoadingState />
            ) : filtered.length === 0 ? (
              <EmptyState icon={Building} message={t("no_data")} />
            ) : (
              <ul className="divide-y divide-bk-brown/10">
                {filtered.map((d) => (
                  <li key={d.id}>
                    <button
                      type="button"
                      onClick={() => selectDepartment(d)}
                      className="w-full text-left px-5 py-3 flex items-center justify-between hover:bg-bk-cream2 transition"
                    >
                      <div>
                        <p className="font-semibold text-bk-brown text-sm">{d.name}</p>
                        <p className="text-xs text-bk-brown/60">{t("employee_count", { count: d.employee_count })}</p>
                      </div>
                      <span
                        className={
                          d.active
                            ? "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-green-100 text-green-700"
                            : "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-bk-brown/10 text-bk-brown/60"
                        }
                      >
                        {d.active ? t("active") : t("inactive")}
                      </span>
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>

          {canManage && (
            <form
              onSubmit={handleCreate}
              className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 space-y-3 text-sm"
            >
              <h3 className="font-heading font-bold text-bk-brown">{t("new_department")}</h3>
              {createError && (
                <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2">{createError}</p>
              )}
              <div>
                <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("name")}</label>
                <input
                  required
                  value={name}
                  onChange={(e) => setName(e.target.value)}
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

        <div>
          {selected ? (
            <form
              onSubmit={handleSaveEdit}
              className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 space-y-3 text-sm"
            >
              <h3 className="font-heading font-bold text-bk-brown">{t("edit_department")}</h3>
              {editError && (
                <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2">{editError}</p>
              )}
              <div>
                <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("name")}</label>
                <input
                  required
                  value={editName}
                  onChange={(e) => setEditName(e.target.value)}
                  className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                />
              </div>
              <label className="flex items-center gap-2 text-sm text-bk-brown/70">
                <input type="checkbox" checked={editActive} onChange={(e) => setEditActive(e.target.checked)} />
                {t("active")}
              </label>
              <div className="flex gap-2">
                <button
                  type="submit"
                  disabled={saving}
                  className="text-xs font-semibold text-white rounded-lg px-4 py-2 disabled:opacity-50"
                  style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}
                >
                  {t("save_changes")}
                </button>
                {selected.active && (
                  <button
                    type="button"
                    onClick={() => handleDeactivate(selected)}
                    className="text-xs font-semibold text-bk-brown/70 bg-bk-brown/10 rounded-lg px-4 py-2"
                  >
                    {t("deactivate")}
                  </button>
                )}
              </div>
            </form>
          ) : (
            <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 text-sm text-bk-brown/50">
              {t("select_hint")}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
