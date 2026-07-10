"use client";

import { createContext, useCallback, useContext, useEffect, useState } from "react";
import { apiFetch } from "./api";

const PermissionsContext = createContext(null);

export function PermissionsProvider({ children }) {
  const [me, setMe] = useState(null);
  const [permissions, setPermissions] = useState(null);
  const [loading, setLoading] = useState(true);

  const reload = useCallback(() => {
    setLoading(true);
    apiFetch("/api/auth/me")
      .then((data) => {
        setMe(data);
        setPermissions(data.permissions || []);
      })
      .catch(() => {
        setMe(null);
        setPermissions([]);
      })
      .finally(() => setLoading(false));
  }, []);

  useEffect(() => {
    reload();
  }, [reload]);

  function hasPermission(code) {
    if (!permissions) return false;
    return permissions.includes(code);
  }

  return (
    <PermissionsContext.Provider value={{ me, permissions: permissions || [], hasPermission, loading, reload }}>
      {children}
    </PermissionsContext.Provider>
  );
}

export function usePermissions() {
  const ctx = useContext(PermissionsContext);
  if (!ctx) throw new Error("usePermissions must be used within PermissionsProvider");
  return ctx;
}
