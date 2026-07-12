#!/bin/bash
# ============================================================
# Pantalla "Conceptos de Nomina" (mantenimiento de PayrollConcept).
# El backend ya existe desde Mod. 6 (GET/POST /api/catalogs/concepts,
# PATCH /api/catalogs/concepts/{id}) pero nunca se construyo la UI -
# gap detectado por el usuario. 100% frontend, sin cambios de backend.
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

# ---------- 1. sidebar: nuevo item en grupo "nomina" ----------
python3 << 'PYEOF'
path = "apps/frontend/app/[locale]/dashboard/layout.js"
with open(path, encoding="utf-8") as f:
    src = f.read()

old = '''  {
    key: "nomina",
    icon: Wallet,
    items: [
      { key: "payroll", href: "/nomina", permission: "payroll.view" },
      { key: "payroll_runs", href: "/nomina/corridas", permission: "payroll.view" },
    ],
  },'''
new = '''  {
    key: "nomina",
    icon: Wallet,
    items: [
      { key: "payroll", href: "/nomina", permission: "payroll.view" },
      { key: "payroll_runs", href: "/nomina/corridas", permission: "payroll.view" },
      { key: "concepts", href: "/nomina/conceptos", permission: "catalogs.view" },
    ],
  },'''

assert old in src, "ANCHOR NOT FOUND: grupo nomina"
assert src.count(old) == 1, "ANCHOR NOT UNIQUE: grupo nomina"
src = src.replace(old, new, 1)
with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("OK: layout.js - item concepts agregado al sidebar")
PYEOF

# ---------- 2. pantalla nueva: nomina/conceptos/page.js ----------
mkdir -p "apps/frontend/app/[locale]/dashboard/nomina/conceptos"
cat > "apps/frontend/app/[locale]/dashboard/nomina/conceptos/page.js" << 'PYEOF'
"use client";

import { useEffect, useState } from "react";
import { useTranslations } from "next-intl";
import { apiFetch } from "../../../../../lib/api";
import { useToast } from "../../../../../lib/toast";
import { usePermissions } from "../../../../../lib/permissions";
import { LoadingState, EmptyState } from "../../../../../lib/ui";
import { FileText } from "lucide-react";

const CALCULATION_METHODS = ["monto_fijo", "porcentaje", "cantidad"];
const NATURES = ["ingreso", "deduccion"];
const ORIGINS = ["patronal", "empleado"];

const emptyCreateForm = {
  code: "",
  name: "",
  calculation_method: "monto_fijo",
  nature: "ingreso",
  origin: "empleado",
  value: "",
  employer_value: "",
  accounting_account_id: "",
};

export default function ConceptosNominaPage() {
  const t = useTranslations("payroll_concepts");
  const { hasPermission } = usePermissions();
  const { showToast } = useToast();

  const [concepts, setConcepts] = useState([]);
  const [chartAccounts, setChartAccounts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [searchQuery, setSearchQuery] = useState("");

  const [selected, setSelected] = useState(null);
  const [editForm, setEditForm] = useState(null);
  const [saving, setSaving] = useState(false);
  const [editError, setEditError] = useState(null);

  const [createForm, setCreateForm] = useState(emptyCreateForm);
  const [creating, setCreating] = useState(false);
  const [createError, setCreateError] = useState(null);

  useEffect(() => {
    loadAll();
  }, []);

  function loadAll() {
    setLoading(true);
    Promise.all([
      apiFetch("/api/catalogs/concepts"),
      apiFetch("/api/catalogs/chart-of-accounts").catch(() => []),
    ])
      .then(([c, ca]) => {
        setConcepts(c);
        setChartAccounts(ca);
      })
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }

  function accountLabel(id) {
    if (!id) return "—";
    const a = chartAccounts.find((x) => x.id === id);
    return a ? a.code + " · " + a.name : id;
  }

  const filteredConcepts = concepts.filter((c) => {
    const q = searchQuery.trim().toLowerCase();
    if (!q) return true;
    return c.code.toLowerCase().includes(q) || c.name.toLowerCase().includes(q);
  });

  function selectConcept(c) {
    setSelected(c);
    setEditError(null);
    setEditForm({
      name: c.name,
      value: c.value,
      employer_value: c.employer_value != null ? c.employer_value : "",
      active: c.active,
      accounting_account_id: c.accounting_account_id || "",
    });
  }

  async function handleCreate(e) {
    e.preventDefault();
    setCreating(true);
    setCreateError(null);
    try {
      const payload = {
        code: createForm.code,
        name: createForm.name,
        calculation_method: createForm.calculation_method,
        nature: createForm.nature,
        origin: createForm.origin,
        value: parseFloat(createForm.value),
        employer_value: createForm.employer_value !== "" ? parseFloat(createForm.employer_value) : null,
        accounting_account_id: createForm.accounting_account_id || null,
      };
      await apiFetch("/api/catalogs/concepts", { method: "POST", body: JSON.stringify(payload) });
      setCreateForm(emptyCreateForm);
      showToast(t("created_ok_toast"));
      loadAll();
    } catch (err) {
      setCreateError(err.message);
      showToast(err.message, "error");
    } finally {
      setCreating(false);
    }
  }

  async function handleUpdate(e) {
    e.preventDefault();
    if (!selected) return;
    setSaving(true);
    setEditError(null);
    try {
      const payload = {
        name: editForm.name,
        value: parseFloat(editForm.value),
        employer_value: editForm.employer_value !== "" ? parseFloat(editForm.employer_value) : null,
        active: editForm.active,
        accounting_account_id: editForm.accounting_account_id || null,
      };
      const updated = await apiFetch("/api/catalogs/concepts/" + selected.id, {
        method: "PATCH",
        body: JSON.stringify(payload),
      });
      showToast(t("updated_ok_toast"));
      setSelected(updated);
      loadAll();
    } catch (err) {
      setEditError(err.message);
      showToast(err.message, "error");
    } finally {
      setSaving(false);
    }
  }

  return (
    <div>
      <h1 className="font-heading text-2xl font-extrabold text-bk-brown mb-2">{t("title")}</h1>
      <p className="text-sm text-bk-brown/60 mb-6">{t("subtitle")}</p>

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
              <LoadingState />
            ) : filteredConcepts.length === 0 ? (
              <EmptyState icon={FileText} message={t("no_concepts")} />
            ) : (
              <ul className="divide-y divide-bk-brown/10">
                {filteredConcepts.map((c) => (
                  <li key={c.id}>
                    <button
                      onClick={() => selectConcept(c)}
                      className={
                        selected && selected.id === c.id
                          ? "w-full text-left px-5 py-4 transition bg-bk-orange/10"
                          : "w-full text-left px-5 py-4 transition hover:bg-bk-cream2"
                      }
                    >
                      <div className="flex items-center justify-between">
                        <p className="font-semibold text-bk-brown">{c.name}</p>
                        <span
                          className={
                            c.active
                              ? "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-green-100 text-green-700"
                              : "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-bk-brown/10 text-bk-brown/60"
                          }
                        >
                          {c.active ? t("active") : t("inactive")}
                        </span>
                      </div>
                      <p className="text-xs text-bk-brown/60 mt-0.5">{c.code}</p>
                      <div className="flex flex-wrap gap-1 mt-2">
                        <span className="inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-bk-brown/10 text-bk-brown/70">
                          {t("nature_" + c.nature)}
                        </span>
                        <span className="inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-bk-brown/10 text-bk-brown/70">
                          {t("origin_" + c.origin)}
                        </span>
                        <span className="inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-bk-brown/10 text-bk-brown/70">
                          {t("method_" + c.calculation_method)}
                        </span>
                      </div>
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>

          <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5">
            <h2 className="font-heading font-bold text-bk-brown mb-4">{t("new_concept")}</h2>
            {createError && (
              <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-3">{createError}</p>
            )}
            {hasPermission("catalogs.manage") && (
              <form onSubmit={handleCreate} className="space-y-3 text-sm">
                <div className="grid grid-cols-2 gap-3">
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
                </div>
                <div className="grid grid-cols-3 gap-3">
                  <div>
                    <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("calculation_method")}</label>
                    <select
                      value={createForm.calculation_method}
                      onChange={(e) => setCreateForm({ ...createForm, calculation_method: e.target.value })}
                      className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                    >
                      {CALCULATION_METHODS.map((m) => (
                        <option key={m} value={m}>
                          {t("method_" + m)}
                        </option>
                      ))}
                    </select>
                  </div>
                  <div>
                    <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("nature")}</label>
                    <select
                      value={createForm.nature}
                      onChange={(e) => setCreateForm({ ...createForm, nature: e.target.value })}
                      className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                    >
                      {NATURES.map((n) => (
                        <option key={n} value={n}>
                          {t("nature_" + n)}
                        </option>
                      ))}
                    </select>
                  </div>
                  <div>
                    <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("origin")}</label>
                    <select
                      value={createForm.origin}
                      onChange={(e) => setCreateForm({ ...createForm, origin: e.target.value })}
                      className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                    >
                      {ORIGINS.map((o) => (
                        <option key={o} value={o}>
                          {t("origin_" + o)}
                        </option>
                      ))}
                    </select>
                  </div>
                </div>
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("value")}</label>
                    <input
                      required
                      type="number"
                      step="0.0001"
                      value={createForm.value}
                      onChange={(e) => setCreateForm({ ...createForm, value: e.target.value })}
                      className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                    />
                  </div>
                  <div>
                    <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("employer_value")}</label>
                    <input
                      type="number"
                      step="0.0001"
                      value={createForm.employer_value}
                      onChange={(e) => setCreateForm({ ...createForm, employer_value: e.target.value })}
                      placeholder={t("employer_value_hint")}
                      className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                    />
                  </div>
                </div>
                <div>
                  <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("accounting_account")}</label>
                  <select
                    value={createForm.accounting_account_id}
                    onChange={(e) => setCreateForm({ ...createForm, accounting_account_id: e.target.value })}
                    className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                  >
                    <option value="">{t("select_account")}</option>
                    {chartAccounts.map((a) => (
                      <option key={a.id} value={a.id}>
                        {a.code} · {a.name}
                      </option>
                    ))}
                  </select>
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
        </div>

        <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5 h-fit">
          {!selected ? (
            <p className="text-sm text-bk-brown/60">{t("select_concept_prompt")}</p>
          ) : (
            <>
              <h2 className="font-heading font-bold text-bk-brown mb-1">{selected.name}</h2>
              <p className="text-xs text-bk-brown/50 mb-4">{selected.code}</p>
              {editError && (
                <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-3">{editError}</p>
              )}
              {hasPermission("catalogs.manage") && (
                <form onSubmit={handleUpdate} className="space-y-3 text-sm">
                  <div>
                    <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("name")}</label>
                    <input
                      required
                      value={editForm.name}
                      onChange={(e) => setEditForm({ ...editForm, name: e.target.value })}
                      className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                    />
                  </div>
                  <div className="grid grid-cols-2 gap-3">
                    <div>
                      <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("value")}</label>
                      <input
                        required
                        type="number"
                        step="0.0001"
                        value={editForm.value}
                        onChange={(e) => setEditForm({ ...editForm, value: e.target.value })}
                        className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                      />
                    </div>
                    <div>
                      <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("employer_value")}</label>
                      <input
                        type="number"
                        step="0.0001"
                        value={editForm.employer_value}
                        onChange={(e) => setEditForm({ ...editForm, employer_value: e.target.value })}
                        className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                      />
                    </div>
                  </div>
                  <div>
                    <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("accounting_account")}</label>
                    <select
                      value={editForm.accounting_account_id}
                      onChange={(e) => setEditForm({ ...editForm, accounting_account_id: e.target.value })}
                      className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                    >
                      <option value="">{t("select_account")}</option>
                      {chartAccounts.map((a) => (
                        <option key={a.id} value={a.id}>
                          {a.code} · {a.name}
                        </option>
                      ))}
                    </select>
                  </div>
                  <label className="flex items-center gap-2 text-xs text-bk-brown/80">
                    <input
                      type="checkbox"
                      checked={editForm.active}
                      onChange={(e) => setEditForm({ ...editForm, active: e.target.checked })}
                    />
                    {t("active")}
                  </label>
                  <button
                    type="submit"
                    disabled={saving}
                    className="text-xs font-semibold text-white rounded-lg px-4 py-2 disabled:opacity-50"
                    style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}
                  >
                    {t("save_changes")}
                  </button>
                </form>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
}
PYEOF
echo "OK: nomina/conceptos/page.js creado"

# ---------- 3. i18n: nav.concepts + namespace payroll_concepts ----------
python3 << 'PYEOF'
import json

nuevas_nav_es = {"concepts": "Conceptos de Nómina"}
nuevas_nav_en = {"concepts": "Payroll Concepts"}

nuevas_pc_es = {
    "title": "Conceptos de Nómina",
    "subtitle": "Catálogo de ingresos y deducciones que alimenta todo el motor de nómina — CCSS, renta, horas extra, feriados, aguinaldo y más.",
    "search_placeholder": "Buscar por código o nombre...",
    "no_concepts": "Sin conceptos cargados todavía.",
    "new_concept": "Nuevo concepto",
    "code": "Código",
    "name": "Nombre",
    "calculation_method": "Método de cálculo",
    "nature": "Naturaleza",
    "origin": "Origen",
    "value": "Valor",
    "employer_value": "% patronal (opcional)",
    "employer_value_hint": "Solo si tiene componente patronal separado",
    "accounting_account": "Cuenta contable",
    "select_account": "Sin cuenta asignada",
    "create": "Crear concepto",
    "select_concept_prompt": "Seleccioná un concepto de la lista para editarlo.",
    "save_changes": "Guardar cambios",
    "active": "Activo",
    "inactive": "Inactivo",
    "created_ok_toast": "Concepto creado",
    "updated_ok_toast": "Concepto actualizado",
    "method_monto_fijo": "Monto fijo",
    "method_porcentaje": "Porcentaje",
    "method_cantidad": "Cantidad",
    "nature_ingreso": "Ingreso",
    "nature_deduccion": "Deducción",
    "origin_patronal": "Patronal",
    "origin_empleado": "Empleado",
}
nuevas_pc_en = {
    "title": "Payroll Concepts",
    "subtitle": "Catalog of income and deduction concepts that feeds the entire payroll engine — CCSS, income tax, overtime, holidays, bonuses and more.",
    "search_placeholder": "Search by code or name...",
    "no_concepts": "No concepts loaded yet.",
    "new_concept": "New concept",
    "code": "Code",
    "name": "Name",
    "calculation_method": "Calculation method",
    "nature": "Nature",
    "origin": "Origin",
    "value": "Value",
    "employer_value": "Employer % (optional)",
    "employer_value_hint": "Only if it has a separate employer component",
    "accounting_account": "Accounting account",
    "select_account": "No account assigned",
    "create": "Create concept",
    "select_concept_prompt": "Select a concept from the list to edit it.",
    "save_changes": "Save changes",
    "active": "Active",
    "inactive": "Inactive",
    "created_ok_toast": "Concept created",
    "updated_ok_toast": "Concept updated",
    "method_monto_fijo": "Fixed amount",
    "method_porcentaje": "Percentage",
    "method_cantidad": "Quantity",
    "nature_ingreso": "Income",
    "nature_deduccion": "Deduction",
    "origin_patronal": "Employer",
    "origin_empleado": "Employee",
}

for path, nav_v, pc_v in [
    ("apps/frontend/messages/es.json", nuevas_nav_es, nuevas_pc_es),
    ("apps/frontend/messages/en.json", nuevas_nav_en, nuevas_pc_en),
]:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    added = 0
    data.setdefault("nav", {})
    for k, v in nuevas_nav_es.items() if False else nav_v.items():
        if k not in data["nav"]:
            data["nav"][k] = v
            added += 1
    data.setdefault("payroll_concepts", {})
    for k, v in pc_v.items():
        if k not in data["payroll_concepts"]:
            data["payroll_concepts"][k] = v
            added += 1
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"OK: {path} - +{added} claves nuevas")
PYEOF

echo "=== rebuild frontend ==="
docker compose build --no-cache frontend
docker compose up -d frontend
sleep 6
docker compose logs frontend --tail 40

echo "=== FIN conceptos de nomina ==="
