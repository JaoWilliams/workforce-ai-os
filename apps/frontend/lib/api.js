const TOKEN_KEY = "workforce_token";
const TENANT_KEY = "workforce_tenant";
const EMAIL_KEY = "workforce_email";

export function saveSession({ token, tenant_slug, email }) {
  localStorage.setItem(TOKEN_KEY, token);
  localStorage.setItem(TENANT_KEY, tenant_slug);
  localStorage.setItem(EMAIL_KEY, email);
}

export function getToken() {
  if (typeof window === "undefined") return null;
  return localStorage.getItem(TOKEN_KEY);
}

export function getSession() {
  if (typeof window === "undefined") return null;
  const token = localStorage.getItem(TOKEN_KEY);
  if (!token) return null;
  return {
    token,
    tenant_slug: localStorage.getItem(TENANT_KEY),
    email: localStorage.getItem(EMAIL_KEY),
  };
}

export function clearSession() {
  localStorage.removeItem(TOKEN_KEY);
  localStorage.removeItem(TENANT_KEY);
  localStorage.removeItem(EMAIL_KEY);
}

export class ApiError extends Error {
  constructor(message, status, detail) {
    super(message);
    this.status = status;
    this.detail = detail;
  }
}

export async function apiFetch(path, options = {}) {
  const token = getToken();
  const headers = {
    "Content-Type": "application/json",
    ...(options.headers || {}),
  };
  if (token) {
    headers["Authorization"] = `Bearer ${token}`;
  }

  const res = await fetch(path, { ...options, headers });

  if (res.status === 204) return null;

  let body = null;
  const text = await res.text();
  if (text) {
    try {
      body = JSON.parse(text);
    } catch {
      body = text;
    }
  }

  if (!res.ok) {
    const detail = body && body.detail ? body.detail : res.statusText;
    throw new ApiError(
      typeof detail === "string" ? detail : JSON.stringify(detail),
      res.status,
      body
    );
  }

  return body;
}

export async function apiFetchBlob(path) {
  const token = getToken();
  const headers = {};
  if (token) headers["Authorization"] = `Bearer ${token}`;
  const res = await fetch(path, { headers });
  if (!res.ok) {
    throw new ApiError(res.statusText, res.status, null);
  }
  return res.blob();
}

export async function login(tenant_slug, email, password) {
  const data = await apiFetch("/api/auth/login", {
    method: "POST",
    body: JSON.stringify({ tenant_slug, email, password }),
  });
  saveSession({ token: data.access_token, tenant_slug, email });
  return data;
}
