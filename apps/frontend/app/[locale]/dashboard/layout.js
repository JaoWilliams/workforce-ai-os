"use client";

import { useEffect, useState } from "react";
import { useRouter, usePathname, useParams } from "next/navigation";
import { useTranslations } from "next-intl";
import { getSession, clearSession } from "../../../lib/api";
import { ToastProvider } from "../../../lib/toast";

const NAV_ITEMS = [
  { key: "dashboard", href: "" },
  { key: "employees", href: "/empleados" },
  { key: "branches", href: "/sucursales" },
  { key: "devices", href: "/dispositivos" },
  { key: "shifts", href: "/turnos" },
  { key: "feature_flags", href: "/feature-flags" },
  { key: "attendance", href: "/marcacion" },
  { key: "confianza", href: "/confianza" },
  { key: "exceptions", href: "/excepciones" },
];

export default function DashboardLayout({ children }) {
  const t = useTranslations("nav");
  const router = useRouter();
  const pathname = usePathname();
  const params = useParams();
  const locale = params.locale;
  const [session, setSession] = useState(null);
  const [checked, setChecked] = useState(false);

  useEffect(() => {
    const s = getSession();
    if (!s) {
      router.push(`/${locale}/login`);
    } else {
      setSession(s);
    }
    setChecked(true);
  }, [locale, router]);

  function handleLogout() {
    clearSession();
    router.push(`/${locale}/login`);
  }

  function switchLocale(newLocale) {
    const rest = pathname.split("/").slice(2).join("/");
    router.push(`/${newLocale}/${rest}`);
  }

  if (!checked || !session) return null;

  return (
    <ToastProvider>
    <div className="min-h-screen flex bg-bk-cream2">
      <aside className="w-64 bg-bk-brown text-bk-cream flex flex-col">
        <div className="px-5 py-6 border-b border-bk-orange/25">
          <p className="font-heading font-extrabold text-lg leading-tight tracking-wide">
            WORKFORCE&nbsp;<span className="text-bk-orange">AI</span>
          </p>
          <p className="text-xs text-bk-cream/60 mt-1 uppercase tracking-wide">{session.tenant_slug}</p>
        </div>
        <nav className="flex-1 px-3 py-4 space-y-1">
          {NAV_ITEMS.map((item) => {
            const href = "/" + locale + "/dashboard" + item.href;
            const active = pathname === href;
            return (
              <a key={item.key} href={href} className={
                active
                  ? "block rounded-lg px-3 py-2 text-sm font-medium transition bg-bk-orange text-white"
                  : "block rounded-lg px-3 py-2 text-sm font-medium transition text-bk-cream/80 hover:bg-white/10"
              }>
                {t(item.key)}
              </a>
            );
          })}
        </nav>
        <div className="px-3 py-4 border-t border-bk-orange/25 space-y-2">
          <div className="flex gap-2 px-3">
            <button
              onClick={() => switchLocale("es")}
              className={locale === "es" ? "text-xs text-bk-orange font-semibold" : "text-xs text-bk-cream/50"}
            >
              ES
            </button>
            <span className="text-bk-cream/30">/</span>
            <button
              onClick={() => switchLocale("en")}
              className={locale === "en" ? "text-xs text-bk-orange font-semibold" : "text-xs text-bk-cream/50"}
            >
              EN
            </button>
          </div>
          <p className="px-3 text-xs text-bk-cream/50 truncate">{session.email}</p>
          <button
            onClick={handleLogout}
            className="w-full text-left rounded-lg px-3 py-2 text-sm text-bk-cream/80 hover:bg-white/10"
          >
            {t("logout")}
          </button>
        </div>
      </aside>
      <main className="flex-1 p-8 overflow-y-auto">{children}</main>
    </div>
    </ToastProvider>
  );
}
