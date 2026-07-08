"use client";

import { useState } from "react";
import { useRouter, useParams } from "next/navigation";
import { useTranslations } from "next-intl";
import { login, ApiError } from "../../../lib/api";

export default function LoginPage() {
  const t = useTranslations("auth");
  const router = useRouter();
  const params = useParams();
  const locale = params.locale;

  const [tenantSlug, setTenantSlug] = useState("burgerking");
  const [email, setEmail] = useState("admin@bk.com");
  const [password, setPassword] = useState("");
  const [error, setError] = useState(null);
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e) {
    e.preventDefault();
    setError(null);
    setLoading(true);
    try {
      await login(tenantSlug, email, password);
      router.push(`/${locale}/dashboard`);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : t("error"));
    } finally {
      setLoading(false);
    }
  }

  return (
    <main className="min-h-screen flex items-center justify-center bg-bk-dark px-4">
      <div className="w-full max-w-sm bg-bk-cream rounded-2xl shadow-2xl p-8 border border-bk-orange/20">
        <p className="text-[10px] font-semibold text-bk-orange uppercase tracking-[3px] mb-1">
          Motor de Confianza Operativa™
        </p>
        <h1 className="font-heading text-3xl font-extrabold text-bk-brown mb-1 tracking-wide">
          WORKFORCE&nbsp;<span className="text-bk-orange">AI</span>
        </h1>
        <p className="text-sm text-bk-brown/70 mb-6">{t("title")}</p>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-bk-brown mb-1">
              {t("tenant_slug")}
            </label>
            <input
              className="w-full rounded-lg border border-bk-brown/20 bg-white px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-bk-orange"
              value={tenantSlug}
              onChange={(e) => setTenantSlug(e.target.value)}
              required
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-bk-brown mb-1">
              {t("email")}
            </label>
            <input
              type="email"
              className="w-full rounded-lg border border-bk-brown/20 bg-white px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-bk-orange"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-bk-brown mb-1">
              {t("password")}
            </label>
            <input
              type="password"
              className="w-full rounded-lg border border-bk-brown/20 bg-white px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-bk-orange"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
            />
          </div>
          {error && (
            <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2">{error}</p>
          )}
          <button
            type="submit"
            disabled={loading}
            className="w-full rounded-lg text-white font-semibold py-2.5 transition disabled:opacity-50"
            style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}
          >
            {loading ? "..." : t("submit")}
          </button>
        </form>
      </div>
    </main>
  );
}
