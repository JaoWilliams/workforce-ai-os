"use client";

import { useEffect, useState } from "react";
import { useTranslations } from "next-intl";
import { Users, Shield } from "lucide-react";
import { apiFetch } from "../../../../lib/api";
import { useToast } from "../../../../lib/toast";
import { usePermissions } from "../../../../lib/permissions";
import { LoadingState, EmptyState } from "../../../../lib/ui";

function groupPermissions(codes) {
  const groups = {};
  for (const code of codes) {
    const [module, action] = code.split(".");
    if (!groups[module]) groups[module] = [];
    groups[module].push({ code, action });
  }
  return groups;
}

export default function UsuariosRolesPage() {
  const t = useTranslations("rbac");
  const { showToast } = useToast();
  const { me, reload: reloadMe } = usePermissions();

  const [roles, setRoles] = useState([]);
  const [users, setUsers] = useState([]);
  const [permissionCatalog, setPermissionCatalog] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const [roleSearch, setRoleSearch] = useState("");
  const [userSearch, setUserSearch] = useState("");
  const [selectedRoleId, setSelectedRoleId] = useState("");
  const [selectedUserId, setSelectedUserId] = useState("");

  const [newRoleName, setNewRoleName] = useState("");
  const [newRolePerms, setNewRolePerms] = useState({});
  const [creatingRole, setCreatingRole] = useState(false);
  const [createRoleError, setCreateRoleError] = useState(null);

  const [editRoleName, setEditRoleName] = useState("");
  const [editRolePerms, setEditRolePerms] = useState({});
  const [savingRole, setSavingRole] = useState(false);
  const [editRoleError, setEditRoleError] = useState(null);
  const [togglingRole, setTogglingRole] = useState(false);

  const [newUserEmail, setNewUserEmail] = useState("");
  const [newUserPassword, setNewUserPassword] = useState("");
  const [newUserRoleId, setNewUserRoleId] = useState("");
  const [creatingUser, setCreatingUser] = useState(false);
  const [createUserError, setCreateUserError] = useState(null);

  const [editUserEmail, setEditUserEmail] = useState("");
  const [editUserRoleId, setEditUserRoleId] = useState("");
  const [editUserPassword, setEditUserPassword] = useState("");
  const [savingUser, setSavingUser] = useState(false);
  const [editUserError, setEditUserError] = useState(null);
  const [togglingUser, setTogglingUser] = useState(false);

  useEffect(() => {
    loadAll();
  }, []);

  function loadAll() {
    setLoading(true);
    Promise.all([
      apiFetch("/api/rbac/roles"),
      apiFetch("/api/auth/users"),
      apiFetch("/api/rbac/permissions"),
    ])
      .then(([r, u, p]) => {
        setRoles(r);
        setUsers(u);
        setPermissionCatalog(p);
      })
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }

  const filteredRoles = roles.filter((r) => {
    const q = roleSearch.trim().toLowerCase();
    if (!q) return true;
    return r.name.toLowerCase().includes(q);
  });

  const filteredUsers = users.filter((u) => {
    const q = userSearch.trim().toLowerCase();
    if (!q) return true;
    return u.email.toLowerCase().includes(q) || (u.role_name || "").toLowerCase().includes(q);
  });

  const selectedRole = roles.find((r) => r.id === selectedRoleId) || null;
  const selectedUser = users.find((u) => u.id === selectedUserId) || null;
  const permissionGroups = groupPermissions(permissionCatalog);

  useEffect(() => {
    const r = roles.find((x) => x.id === selectedRoleId);
    if (r) {
      setEditRoleName(r.name);
      const permsObj = {};
      r.permissions.forEach((p) => {
        permsObj[p] = true;
      });
      setEditRolePerms(permsObj);
      setEditRoleError(null);
    }
  }, [selectedRoleId, roles]);

  useEffect(() => {
    const u = users.find((x) => x.id === selectedUserId);
    if (u) {
      setEditUserEmail(u.email);
      setEditUserRoleId(u.role_id || "");
      setEditUserPassword("");
      setEditUserError(null);
    }
  }, [selectedUserId, users]);

  function toggleNewRolePerm(code) {
    setNewRolePerms((prev) => ({ ...prev, [code]: !prev[code] }));
  }
  function toggleEditRolePerm(code) {
    setEditRolePerms((prev) => ({ ...prev, [code]: !prev[code] }));
  }

  async function handleCreateRole(e) {
    e.preventDefault();
    setCreatingRole(true);
    setCreateRoleError(null);
    try {
      const permissions = permissionCatalog.filter((c) => newRolePerms[c]);
      await apiFetch("/api/rbac/roles", {
        method: "POST",
        body: JSON.stringify({ name: newRoleName, permissions }),
      });
      showToast(t("role_created_toast", { name: newRoleName }));
      setNewRoleName("");
      setNewRolePerms({});
      loadAll();
    } catch (err) {
      setCreateRoleError(err.message);
      showToast(err.message, "error");
    } finally {
      setCreatingRole(false);
    }
  }

  async function handleSaveRole(e) {
    e.preventDefault();
    setSavingRole(true);
    setEditRoleError(null);
    try {
      const permissions = permissionCatalog.filter((c) => editRolePerms[c]);
      await apiFetch("/api/rbac/roles/" + selectedRoleId, {
        method: "PATCH",
        body: JSON.stringify({ name: editRoleName, permissions }),
      });
      showToast(t("role_updated_toast"));
      loadAll();
      reloadMe();
    } catch (err) {
      setEditRoleError(err.message);
      showToast(err.message, "error");
    } finally {
      setSavingRole(false);
    }
  }

  async function handleToggleRoleActive() {
    if (!selectedRole) return;
    if (selectedRole.active) {
      if (!window.confirm(t("deactivate_role_confirm"))) return;
    }
    setTogglingRole(true);
    try {
      if (selectedRole.active) {
        await apiFetch("/api/rbac/roles/" + selectedRoleId, { method: "DELETE" });
        showToast(t("role_deactivated_toast"));
      } else {
        await apiFetch("/api/rbac/roles/" + selectedRoleId, {
          method: "PATCH",
          body: JSON.stringify({ active: true }),
        });
        showToast(t("role_reactivated_toast"));
      }
      loadAll();
    } catch (err) {
      showToast(err.message, "error");
    } finally {
      setTogglingRole(false);
    }
  }

  async function handleCreateUser(e) {
    e.preventDefault();
    setCreatingUser(true);
    setCreateUserError(null);
    try {
      await apiFetch("/api/auth/users", {
        method: "POST",
        body: JSON.stringify({
          email: newUserEmail,
          password: newUserPassword,
          role_id: newUserRoleId,
        }),
      });
      showToast(t("user_created_toast", { email: newUserEmail }));
      setNewUserEmail("");
      setNewUserPassword("");
      setNewUserRoleId("");
      loadAll();
    } catch (err) {
      setCreateUserError(err.message);
      showToast(err.message, "error");
    } finally {
      setCreatingUser(false);
    }
  }

  async function handleSaveUser(e) {
    e.preventDefault();
    setSavingUser(true);
    setEditUserError(null);
    try {
      const payload = { email: editUserEmail, role_id: editUserRoleId };
      if (editUserPassword) payload.password = editUserPassword;
      await apiFetch("/api/auth/users/" + selectedUserId, {
        method: "PATCH",
        body: JSON.stringify(payload),
      });
      showToast(t("user_updated_toast"));
      setEditUserPassword("");
      loadAll();
      if (me && me.id === selectedUserId) reloadMe();
    } catch (err) {
      setEditUserError(err.message);
      showToast(err.message, "error");
    } finally {
      setSavingUser(false);
    }
  }

  async function handleToggleUserActive() {
    if (!selectedUser) return;
    if (selectedUser.active) {
      if (!window.confirm(t("deactivate_user_confirm"))) return;
    }
    setTogglingUser(true);
    try {
      if (selectedUser.active) {
        await apiFetch("/api/auth/users/" + selectedUserId, { method: "DELETE" });
        showToast(t("user_deactivated_toast"));
      } else {
        await apiFetch("/api/auth/users/" + selectedUserId, {
          method: "PATCH",
          body: JSON.stringify({ active: true }),
        });
        showToast(t("user_reactivated_toast"));
      }
      loadAll();
    } catch (err) {
      showToast(err.message, "error");
    } finally {
      setTogglingUser(false);
    }
  }

  const isSelf = me && selectedUser && me.id === selectedUser.id;

  return (
    <div>
      <h1 className="font-heading text-2xl font-extrabold text-bk-brown mb-6">{t("title")}</h1>

      {error && (
        <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-4">{error}</p>
      )}

      <h2 className="font-heading text-lg font-bold text-bk-brown mb-3">{t("roles_section_title")}</h2>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-10">
        <div className="space-y-6">
          <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 overflow-hidden">
            <div className="p-3 border-b border-bk-brown/10">
              <input
                type="text"
                value={roleSearch}
                onChange={(e) => setRoleSearch(e.target.value)}
                placeholder={t("search_placeholder_roles")}
                className="w-full border border-bk-brown/20 rounded-md px-3 py-1.5 text-sm"
              />
            </div>
            {loading ? (
              <LoadingState />
            ) : filteredRoles.length === 0 ? (
              <EmptyState icon={Shield} message={t("no_roles")} />
            ) : (
              <ul className="divide-y divide-bk-brown/10">
                {filteredRoles.map((r) => (
                  <li key={r.id}>
                    <button
                      onClick={() => setSelectedRoleId(r.id)}
                      className={
                        (selectedRoleId === r.id
                          ? "w-full text-left px-5 py-4 transition bg-bk-orange/10"
                          : "w-full text-left px-5 py-4 transition hover:bg-bk-cream2") +
                        (r.active ? "" : " opacity-60")
                      }
                    >
                      <div className="flex items-center gap-2">
                        <p className="font-semibold text-bk-brown">{r.name}</p>
                        {!r.active && (
                          <span className="inline-block rounded-full px-1.5 py-0.5 text-[9px] font-semibold bg-bk-brown/10 text-bk-brown/60">
                            {t("inactive")}
                          </span>
                        )}
                      </div>
                      <p className="text-xs text-bk-brown/60 mt-0.5">
                        {r.permissions.length} {t("permissions_label")} · {r.user_count} {t("assigned_users_count")}
                      </p>
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>

          <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5">
            <h3 className="font-heading font-bold text-bk-brown mb-4">{t("new_role")}</h3>
            {createRoleError && (
              <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-3">{createRoleError}</p>
            )}
            <form onSubmit={handleCreateRole} className="space-y-3 text-sm">
              <div>
                <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("role_name")}</label>
                <input
                  required
                  value={newRoleName}
                  onChange={(e) => setNewRoleName(e.target.value)}
                  className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-bk-brown/70 mb-2">{t("permissions_label")}</label>
                <div className="space-y-3 max-h-64 overflow-y-auto border border-bk-brown/10 rounded-lg p-3">
                  {Object.entries(permissionGroups).map(([mod, items]) => (
                    <div key={mod}>
                      <p className="text-[11px] font-semibold text-bk-brown/70 uppercase tracking-wide mb-1">
                        {t("module_" + mod)}
                      </p>
                      <div className="flex flex-wrap gap-3">
                        {items.map((it) => (
                          <label key={it.code} className="flex items-center gap-1 text-xs text-bk-brown/80">
                            <input
                              type="checkbox"
                              checked={!!newRolePerms[it.code]}
                              onChange={() => toggleNewRolePerm(it.code)}
                            />
                            {it.action === "manage" ? t("perm_manage") : t("perm_view")}
                          </label>
                        ))}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
              <button
                type="submit"
                disabled={creatingRole}
                className="text-xs font-semibold text-white rounded-lg px-4 py-2 disabled:opacity-50"
                style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}
              >
                {t("create_role")}
              </button>
            </form>
          </div>
        </div>

        <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 h-fit">
          {!selectedRole ? (
            <p className="text-sm text-bk-brown/60">{t("select_role_prompt")}</p>
          ) : (
            <div>
              <div className="flex items-center justify-between mb-1">
                <h3 className="font-heading font-bold text-bk-brown">{t("edit_role")}</h3>
                <span
                  className={
                    selectedRole.active
                      ? "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-green-100 text-green-700"
                      : "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-bk-brown/10 text-bk-brown/60"
                  }
                >
                  {selectedRole.active ? t("active") : t("inactive")}
                </span>
              </div>
              <p className="text-xs text-bk-brown/60 mb-4">
                {selectedRole.user_count} {t("assigned_users_count")}
              </p>

              {editRoleError && (
                <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-3">{editRoleError}</p>
              )}

              <form onSubmit={handleSaveRole} className="space-y-3 text-sm">
                <div>
                  <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("role_name")}</label>
                  <input
                    required
                    value={editRoleName}
                    onChange={(e) => setEditRoleName(e.target.value)}
                    className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                  />
                </div>
                <div>
                  <label className="block text-xs font-medium text-bk-brown/70 mb-2">{t("permissions_label")}</label>
                  <div className="space-y-3 max-h-64 overflow-y-auto border border-bk-brown/10 rounded-lg p-3">
                    {Object.entries(permissionGroups).map(([mod, items]) => (
                      <div key={mod}>
                        <p className="text-[11px] font-semibold text-bk-brown/70 uppercase tracking-wide mb-1">
                          {t("module_" + mod)}
                        </p>
                        <div className="flex flex-wrap gap-3">
                          {items.map((it) => (
                            <label key={it.code} className="flex items-center gap-1 text-xs text-bk-brown/80">
                              <input
                                type="checkbox"
                                checked={!!editRolePerms[it.code]}
                                onChange={() => toggleEditRolePerm(it.code)}
                              />
                              {it.action === "manage" ? t("perm_manage") : t("perm_view")}
                            </label>
                          ))}
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  <button
                    type="submit"
                    disabled={savingRole}
                    className="text-xs font-semibold text-white rounded-lg px-4 py-2 disabled:opacity-50"
                    style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}
                  >
                    {t("save_changes")}
                  </button>
                  <button
                    type="button"
                    disabled={togglingRole}
                    onClick={handleToggleRoleActive}
                    className={
                      selectedRole.active
                        ? "text-xs font-semibold text-bk-red border border-bk-red/30 rounded-lg px-4 py-2 disabled:opacity-50"
                        : "text-xs font-semibold text-green-700 border border-green-700/30 rounded-lg px-4 py-2 disabled:opacity-50"
                    }
                  >
                    {selectedRole.active ? t("deactivate_role") : t("reactivate_role")}
                  </button>
                </div>
              </form>
            </div>
          )}
        </div>
      </div>

      <h2 className="font-heading text-lg font-bold text-bk-brown mb-3">{t("users_section_title")}</h2>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="space-y-6">
          <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 overflow-hidden">
            <div className="p-3 border-b border-bk-brown/10">
              <input
                type="text"
                value={userSearch}
                onChange={(e) => setUserSearch(e.target.value)}
                placeholder={t("search_placeholder_users")}
                className="w-full border border-bk-brown/20 rounded-md px-3 py-1.5 text-sm"
              />
            </div>
            {loading ? (
              <LoadingState />
            ) : filteredUsers.length === 0 ? (
              <EmptyState icon={Users} message={t("no_users")} />
            ) : (
              <ul className="divide-y divide-bk-brown/10">
                {filteredUsers.map((u) => (
                  <li key={u.id}>
                    <button
                      onClick={() => setSelectedUserId(u.id)}
                      className={
                        (selectedUserId === u.id
                          ? "w-full text-left px-5 py-4 transition bg-bk-orange/10"
                          : "w-full text-left px-5 py-4 transition hover:bg-bk-cream2") +
                        (u.active ? "" : " opacity-60")
                      }
                    >
                      <div className="flex items-center gap-2">
                        <p className="font-semibold text-bk-brown">{u.email}</p>
                        {!u.active && (
                          <span className="inline-block rounded-full px-1.5 py-0.5 text-[9px] font-semibold bg-bk-brown/10 text-bk-brown/60">
                            {t("inactive")}
                          </span>
                        )}
                      </div>
                      <p className="text-xs text-bk-brown/60 mt-0.5">{u.role_name || "—"}</p>
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>

          <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5">
            <h3 className="font-heading font-bold text-bk-brown mb-4">{t("new_user")}</h3>
            {createUserError && (
              <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-3">{createUserError}</p>
            )}
            <form onSubmit={handleCreateUser} className="space-y-3 text-sm">
              <div>
                <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("user_email")}</label>
                <input
                  type="email"
                  required
                  value={newUserEmail}
                  onChange={(e) => setNewUserEmail(e.target.value)}
                  className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("user_password")}</label>
                <input
                  type="password"
                  required
                  value={newUserPassword}
                  onChange={(e) => setNewUserPassword(e.target.value)}
                  className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("user_role")}</label>
                <select
                  required
                  value={newUserRoleId}
                  onChange={(e) => setNewUserRoleId(e.target.value)}
                  className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                >
                  <option value="">{t("select_role")}</option>
                  {roles.filter((r) => r.active).map((r) => (
                    <option key={r.id} value={r.id}>
                      {r.name}
                    </option>
                  ))}
                </select>
              </div>
              <button
                type="submit"
                disabled={creatingUser}
                className="text-xs font-semibold text-white rounded-lg px-4 py-2 disabled:opacity-50"
                style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}
              >
                {t("create_user")}
              </button>
            </form>
          </div>
        </div>

        <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 h-fit">
          {!selectedUser ? (
            <p className="text-sm text-bk-brown/60">{t("select_user_prompt")}</p>
          ) : (
            <div>
              <div className="flex items-center justify-between mb-1">
                <h3 className="font-heading font-bold text-bk-brown">{t("edit_user")}</h3>
                <span
                  className={
                    selectedUser.active
                      ? "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-green-100 text-green-700"
                      : "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-bk-brown/10 text-bk-brown/60"
                  }
                >
                  {selectedUser.active ? t("active") : t("inactive")}
                </span>
              </div>

              {isSelf && (
                <p className="text-xs text-bk-orange bg-bk-orange/10 rounded-lg px-3 py-2 mb-3">
                  {t("cannot_deactivate_self_hint")}
                </p>
              )}

              {editUserError && (
                <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-3">{editUserError}</p>
              )}

              <form onSubmit={handleSaveUser} className="space-y-3 text-sm">
                <div>
                  <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("user_email")}</label>
                  <input
                    type="email"
                    required
                    value={editUserEmail}
                    onChange={(e) => setEditUserEmail(e.target.value)}
                    className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                  />
                </div>
                <div>
                  <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("user_password")}</label>
                  <input
                    type="password"
                    placeholder="••••••••"
                    value={editUserPassword}
                    onChange={(e) => setEditUserPassword(e.target.value)}
                    className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                  />
                </div>
                <div>
                  <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("user_role")}</label>
                  <select
                    required
                    value={editUserRoleId}
                    onChange={(e) => setEditUserRoleId(e.target.value)}
                    className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                  >
                    <option value="">{t("select_role")}</option>
                    {roles
                      .filter((r) => r.active || r.id === editUserRoleId)
                      .map((r) => (
                        <option key={r.id} value={r.id}>
                          {r.name}
                        </option>
                      ))}
                  </select>
                </div>
                <div className="flex items-center gap-2">
                  <button
                    type="submit"
                    disabled={savingUser}
                    className="text-xs font-semibold text-white rounded-lg px-4 py-2 disabled:opacity-50"
                    style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}
                  >
                    {t("save_changes")}
                  </button>
                  <button
                    type="button"
                    disabled={togglingUser || isSelf}
                    onClick={handleToggleUserActive}
                    className={
                      selectedUser.active
                        ? "text-xs font-semibold text-bk-red border border-bk-red/30 rounded-lg px-4 py-2 disabled:opacity-50"
                        : "text-xs font-semibold text-green-700 border border-green-700/30 rounded-lg px-4 py-2 disabled:opacity-50"
                    }
                  >
                    {selectedUser.active ? t("deactivate_user") : t("reactivate_user")}
                  </button>
                </div>
              </form>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
