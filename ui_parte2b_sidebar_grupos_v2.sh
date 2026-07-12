#!/bin/bash
# ============================================================
# UI/UX Nomina - Parte 2b: sidebar agrupado + colapsable (v2, con
# verificacion estructural post-escritura para detectar pegados
# corruptos ANTES de gastar tiempo en el build de Docker)
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

# ---------- 1. reescribir dashboard/layout.js ----------
python3 << 'PYEOF'
path = "apps/frontend/app/[locale]/dashboard/layout.js"

new_content = '''"use client";
import { useEffect, useState } from "react";
import { useRouter, usePathname, useParams } from "next/navigation";
import { useTranslations } from "next-intl";
import {
  LayoutDashboard,
  Building2,
  Users,
  Settings2,
  Clock,
  Sparkles,
  Wallet,
  Settings,
  ChevronDown,
} from "lucide-react";
import { getSession, clearSession } from "../../../lib/api";
import { ToastProvider } from "../../../lib/toast";
import { PermissionsProvider, usePermissions } from "../../../lib/permissions";

const DASHBOARD_ITEM = { key: "dashboard", href: "", permission: null, icon: LayoutDashboard };

const NAV_GROUPS = [
  {
    key: "organizacion",
    icon: Building2,
    items: [
      { key: "branches", href: "/sucursales", permission: "branches.view" },
      { key: "departments", href: "/departamentos", permission: null, disabled: true },
      { key: "positions", href: "/puestos", permission: null, disabled: true },
    ],
  },
  {
    key: "personal",
    icon: Users,
    items: [
      { key: "employees", href: "/empleados", permission: "employees.view" },
    ],
  },
  {
    key: "operacion",
    icon: Settings2,
    items: [
      { key: "shifts", href: "/turnos", permission: "shifts.view" },
      { key: "work_calendar", href: "/calendario-laboral", permission: null, disabled: true },
      { key: "devices", href: "/dispositivos", permission: "devices.view" },
    ],
  },
  {
    key: "asistencia",
    icon: Clock,
    items: [
      { key: "attendance", href: "/marcacion", permission: "attendance.view" },
      { key: "exceptions", href: "/excepciones", permission: "exceptions.view" },
      { key: "requests", href: "/solicitudes", permission: null, disabled: true },
      { key: "reports", href: "/reportes", permission: "attendance.view" },
    ],
  },
  {
    key: "ia",
    icon: Sparkles,
    items: [
      { key: "confianza", href: "/confianza", permission: "confianza.view" },
      { key: "ai_center", href: "/centro-ia", permission: null, disabled: true },
      { key: "evidence", href: "/evidencias", permission: null, disabled: true },
    ],
  },
  {
    key: "nomina",
    icon: Wallet,
    items: [
      { key: "payroll", href: "/nomina", permission: "payroll.view" },
    ],
  },
  {
    key: "configuracion",
    icon: Settings,
    items: [
      { key: "usuarios_roles", href: "/usuarios-roles", permission: "users.view" },
      { key: "feature_flags", href: "/feature-flags", permission: "feature_flags.view" },
      { key: "modules", href: "/modulos", permission: null, disabled: true },
    ],
  },
];

const SIDEBAR_STORAGE_KEY = "wf_sidebar_collapsed_groups";

export default function DashboardLayout({ children }) {
  return (
    <PermissionsProvider>
      <DashboardShell>{children}</DashboardShell>
    </PermissionsProvider>
  );
}

function DashboardShell({ children }) {
  const t = useTranslations("nav");
  const router = useRouter();
  const pathname = usePathname();
  const params = useParams();
  const locale = params.locale;
  const [session, setSession] = useState(null);
  const [checked, setChecked] = useState(false);
  const [expanded, setExpanded] = useState(() =>
    Object.fromEntries(NAV_GROUPS.map((g) => [g.key, true]))
  );
  const { hasPermission, loading: permissionsLoading } = usePermissions();

  useEffect(() => {
    const s = getSession();
    if (!s) {
      router.push(`/${locale}/login`);
    } else {
      setSession(s);
    }
    setChecked(true);
  }, [locale, router]);

  useEffect(() => {
    try {
      const raw = window.localStorage.getItem(SIDEBAR_STORAGE_KEY);
      if (raw) {
        const collapsedKeys = JSON.parse(raw);
        setExpanded((prev) => {
          const next = { ...prev };
          for (const key of collapsedKeys) next[key] = false;
          return next;
        });
      }
    } catch (e) {
      // localStorage no disponible o dato corrupto - se ignora, todo queda expandido
    }
  }, []);

  useEffect(() => {
    const activeGroup = NAV_GROUPS.find((g) =>
      g.items.some((it) => !it.disabled && "/" + locale + "/dashboard" + it.href === pathname)
    );
    if (activeGroup) {
      setExpanded((prev) => (prev[activeGroup.key] ? prev : { ...prev, [activeGroup.key]: true }));
    }
  }, [pathname, locale]);

  function toggleGroup(key) {
    setExpanded((prev) => {
      const next = { ...prev, [key]: !prev[key] };
      try {
        const collapsedKeys = Object.keys(next).filter((k) => !next[k]);
        window.localStorage.setItem(SIDEBAR_STORAGE_KEY, JSON.stringify(collapsedKeys));
      } catch (e) {
        // localStorage no disponible - se ignora, el estado igual cambia en memoria
      }
      return next;
    });
  }

  function handleLogout() {
    clearSession();
    router.push(`/${locale}/login`);
  }

  function switchLocale(newLocale) {
    const rest = pathname.split("/").slice(2).join("/");
    router.push(`/${newLocale}/${rest}`);
  }

  if (!checked || !session || permissionsLoading) return null;

  function isVisible(item) {
    return !item.permission || hasPermission(item.permission);
  }

  const visibleGroups = NAV_GROUPS.map((g) => ({
    ...g,
    items: g.items.filter(isVisible),
  })).filter((g) => g.items.length > 0);

  function renderLink(item, extraClass) {
    const href = "/" + locale + "/dashboard" + item.href;
    const active = pathname === href;
    return (
      <a
        key={item.key}
        href={href}
        className={
          (active
            ? "block rounded-lg px-3 py-2 text-sm font-medium transition bg-bk-orange text-white"
            : "block rounded-lg px-3 py-2 text-sm font-medium transition text-bk-cream/80 hover:bg-white/10") +
          " " +
          extraClass
        }
      >
        {t(item.key)}
      </a>
    );
  }

  function renderDisabled(item, extraClass) {
    return (
      <div
        key={item.key}
        title={t("coming_soon")}
        className={
          "flex items-center justify-between rounded-lg px-3 py-2 text-sm text-bk-cream/25 cursor-not-allowed select-none " +
          extraClass
        }
      >
        <span>{t(item.key)}</span>
        <span className="text-[9px] font-semibold uppercase tracking-wide bg-white/5 text-bk-cream/35 rounded px-1.5 py-0.5">
          {t("coming_soon")}
        </span>
      </div>
    );
  }

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
        <nav className="flex-1 px-3 py-4 overflow-y-auto">
          <div className="pb-3 mb-2 border-b border-bk-orange/10">
            {(() => {
              const href = "/" + locale + "/dashboard" + DASHBOARD_ITEM.href;
              const active = pathname === href;
              const Icon = DASHBOARD_ITEM.icon;
              return (
                <a
                  href={href}
                  className={
                    active
                      ? "flex items-center gap-2 rounded-lg px-3 py-2 text-sm font-medium transition bg-bk-orange text-white"
                      : "flex items-center gap-2 rounded-lg px-3 py-2 text-sm font-medium transition text-bk-cream/80 hover:bg-white/10"
                  }
                >
                  <Icon size={16} strokeWidth={2.5} />
                  {t("dashboard")}
                </a>
              );
            })()}
          </div>
          <div className="space-y-1">
            {visibleGroups.map((group) => {
              const GroupIcon = group.icon;
              const isOpen = !!expanded[group.key];
              return (
                <div key={group.key}>
                  <button
                    type="button"
                    onClick={() => toggleGroup(group.key)}
                    className="w-full flex items-center justify-between px-3 py-2 text-[11px] font-semibold uppercase tracking-wider text-bk-cream/45 hover:text-bk-cream/70 transition"
                  >
                    <span className="flex items-center gap-2">
                      <GroupIcon size={14} strokeWidth={2.5} />
                      {t(`group_${group.key}`)}
                    </span>
                    <ChevronDown
                      size={14}
                      className={"transition-transform duration-300 " + (isOpen ? "rotate-180" : "")}
                    />
                  </button>
                  <div
                    className={
                      "grid transition-all duration-300 ease-in-out " +
                      (isOpen ? "grid-rows-[1fr] opacity-100" : "grid-rows-[0fr] opacity-0")
                    }
                  >
                    <div className="overflow-hidden space-y-0.5 pb-1">
                      {group.items.map((item) =>
                        item.disabled ? renderDisabled(item, "pl-4") : renderLink(item, "pl-4")
                      )}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
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
'''

with open(path, "w", encoding="utf-8") as f:
    f.write(new_content)

# ---------- verificacion estructural (detecta pegados con lineas perdidas) ----------
with open(path, encoding="utf-8") as f:
    check = f.read()

problemas = []
if check.count("<a") != 2:
    problemas.append(f"esperaba 2 tags <a, encontre {check.count('<a')}")
if check.count("</a>") != 2:
    problemas.append(f"esperaba 2 cierres </a>, encontre {check.count('</a>')}")
if check.count("<div") < 5:
    problemas.append(f"muy pocos <div ({check.count('<div')}), algo se perdio")
if "function renderLink" not in check:
    problemas.append("falta function renderLink")
if "function renderDisabled" not in check:
    problemas.append("falta function renderDisabled")
if "export default function DashboardLayout" not in check:
    problemas.append("falta export default function DashboardLayout")
line_count = check.count("\n") + 1
if not (300 <= line_count <= 340):
    problemas.append(f"cantidad de lineas sospechosa: {line_count} (esperaba ~324)")

if problemas:
    print("XXX VERIFICACION FALLO - el pegado perdio contenido, NO SE HACE EL BUILD XXX")
    for p in problemas:
        print(" -", p)
    raise SystemExit(1)

print(f"OK: layout.js reescrito y verificado ({line_count} lineas, estructura intacta)")
PYEOF

# ---------- 2. agregar claves i18n nuevas (idempotente) ----------
python3 << 'PYEOF'
import json

nuevas_es = {
    "group_organizacion": "Organización",
    "group_personal": "Personal",
    "group_operacion": "Operación",
    "group_asistencia": "Asistencia",
    "group_ia": "IA",
    "group_nomina": "Nómina",
    "group_configuracion": "Configuración",
    "departments": "Departamentos",
    "positions": "Puestos",
    "work_calendar": "Calendario Laboral",
    "requests": "Solicitudes",
    "ai_center": "Centro IA",
    "evidence": "Evidencias",
    "modules": "Módulos",
    "coming_soon": "Pronto",
}
nuevas_en = {
    "group_organizacion": "Organization",
    "group_personal": "People",
    "group_operacion": "Operations",
    "group_asistencia": "Attendance",
    "group_ia": "AI",
    "group_nomina": "Payroll",
    "group_configuracion": "Settings",
    "departments": "Departments",
    "positions": "Positions",
    "work_calendar": "Work Calendar",
    "requests": "Requests",
    "ai_center": "AI Center",
    "evidence": "Evidence",
    "modules": "Modules",
    "coming_soon": "Soon",
}

for path, nuevas in [
    ("apps/frontend/messages/es.json", nuevas_es),
    ("apps/frontend/messages/en.json", nuevas_en),
]:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    if "nav" not in data:
        raise SystemExit(f"ERROR: {path} no tiene seccion 'nav'")
    added = 0
    for k, v in nuevas.items():
        if k not in data["nav"]:
            data["nav"][k] = v
            added += 1
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"OK: {path} - {added} claves nuevas agregadas")
PYEOF

# ---------- 3. rebuild (solo si la verificacion de arriba paso) ----------
echo "=== rebuild frontend ==="
docker compose build --no-cache frontend
docker compose up -d frontend
sleep 5
docker compose logs frontend --tail 30

echo "=== FIN Parte 2b ==="
