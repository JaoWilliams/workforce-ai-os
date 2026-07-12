#!/bin/bash
# ============================================================
# Onboarding - Parte D: boton "Verificar onboarding" en Empleados
# ahora redirige al Centro de Onboarding en vez de mostrar un toast
# generico con el conteo.
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

python3 << 'PYEOF'
path = "apps/frontend/app/[locale]/dashboard/empleados/page.js"
with open(path, encoding="utf-8") as f:
    src = f.read()

edits = []

edits.append(("import useRouter/useParams", '''import { useTranslations } from "next-intl";
import { useSearchParams } from "next/navigation";''',
'''import { useTranslations } from "next-intl";
import { useSearchParams, useRouter, useParams } from "next/navigation";'''))

edits.append(("hooks router/locale", '''  const { hasPermission } = usePermissions();
  const searchParams = useSearchParams();''',
'''  const { hasPermission } = usePermissions();
  const searchParams = useSearchParams();
  const router = useRouter();
  const params = useParams();
  const locale = params.locale;'''))

edits.append(("handleOnboardingCheck redirige", '''  async function handleOnboardingCheck() {
    setCheckingOnboarding(true);
    try {
      const result = await apiFetch("/api/employees/onboarding-check", { method: "POST" });
      showToast(t("onboarding_check_ok_toast", { checked: result.checked, with_gaps: result.with_gaps }));
      loadEmployees();
    } catch (err) {
      showToast(err.message, "error");
    } finally {
      setCheckingOnboarding(false);
    }
  }''',
'''  async function handleOnboardingCheck() {
    setCheckingOnboarding(true);
    try {
      await apiFetch("/api/employees/onboarding-check", { method: "POST" });
      router.push("/" + locale + "/dashboard/onboarding");
    } catch (err) {
      showToast(err.message, "error");
    } finally {
      setCheckingOnboarding(false);
    }
  }'''))

for label, old, new in edits:
    assert old in src, f"ANCHOR NOT FOUND ({label})"
    assert src.count(old) == 1, f"ANCHOR NOT UNIQUE ({label})"
    src = src.replace(old, new, 1)
    print(f"OK edicion aplicada: {label}")

with open(path, "w", encoding="utf-8") as f:
    f.write(src)

with open(path, encoding="utf-8") as f:
    check = f.read()
problemas = []
if check.count("{") != check.count("}"):
    problemas.append(f"llaves desbalanceadas: {{ {check.count('{')} vs }} {check.count('}')}")
if check.count("(") != check.count(")"):
    problemas.append(f"parentesis desbalanceados: ( {check.count('(')} vs ) {check.count(')')}")
for marker in ["useRouter", "router.push", "dashboard/onboarding"]:
    if marker not in check:
        problemas.append(f"falta: {marker}")
if problemas:
    print("XXX VERIFICACION FALLO XXX")
    for p in problemas:
        print(" -", p)
    raise SystemExit(1)
print("OK: empleados/page.js verificado correctamente")
PYEOF

echo "=== rebuild frontend ==="
docker compose build --no-cache frontend
docker compose up -d frontend
sleep 5
docker compose logs frontend --tail 30

echo "=== FIN Parte D ==="
