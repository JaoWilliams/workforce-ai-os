#!/bin/bash
# ============================================================
# #104 - Verificacion final: smoke test automatico del backend
# antes de mostrar la demo al cliente.
#
# Que hace: login real con el admin del tenant demo, despues pega
# TODOS los endpoints GET de solo lectura (sin efectos secundarios)
# y clasifica cada uno como OK (2xx), WARN (4xx - puede ser normal,
# ej. sin datos todavia) o FAIL (5xx - bug real). Tambien chequea
# salud de contenedores y disco.
#
# IMPORTANTE: el puerto 8000 del contenedor "api" no esta publicado
# al host, asi que las peticiones se hacen DESDE ADENTRO del propio
# contenedor via "docker compose exec" (mismo patron que usamos
# para las consultas a postgres durante toda esta sesion).
#
# Uso: un solo paso. nano verificacion_final_demo.sh, pegar este
# archivo completo (las credenciales ya van adentro), guardar,
# correr: bash verificacion_final_demo.sh
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

DEMO_TENANT_SLUG="burgerking"
DEMO_EMAIL="admin@bk.com"
DEMO_PASSWORD="whopper2024"

echo "=== 1. Salud de contenedores ==="
docker compose ps

echo ""
echo "=== 2. Disco y memoria (riesgo conocido, ver 5.2 del doc maestro) ==="
df -h / 2>/dev/null | head -2
free -h 2>/dev/null | head -2

echo ""
echo "=== 3. Health check + login + endpoints (desde adentro del contenedor api) ==="

docker compose exec -T \
  -e DEMO_TENANT_SLUG="$DEMO_TENANT_SLUG" \
  -e DEMO_EMAIL="$DEMO_EMAIL" \
  -e DEMO_PASSWORD="$DEMO_PASSWORD" \
  api python3 << 'PYEOF'
import json, os, sys, urllib.request, urllib.error

BASE = "http://localhost:8000"
TENANT_SLUG = os.environ["DEMO_TENANT_SLUG"]
EMAIL = os.environ["DEMO_EMAIL"]
PASSWORD = os.environ["DEMO_PASSWORD"]

results = []

def request(method, path, token=None, payload=None):
    url = BASE + path
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    if payload is not None:
        req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            code = resp.status
            body_raw = resp.read()
    except urllib.error.HTTPError as e:
        code = e.code
        body_raw = e.read()
    except Exception as ex:
        return None, None, str(ex)
    body = None
    try:
        body = json.loads(body_raw)
    except Exception:
        pass
    return code, body, None

def check(label, method, path, token=None, payload=None):
    code, body, err = request(method, path, token, payload)
    if err:
        status = "FAIL"
    elif code is None:
        status = "FAIL"
    elif 200 <= code < 300:
        status = "OK"
    elif 400 <= code < 500:
        status = "WARN"
    else:
        status = "FAIL"
    results.append((status, method, path, str(code) if code is not None else "ERR", err or ""))
    return code, body

# --- health (sin auth) ---
check("health", "GET", "/api/health")

# --- login ---
login_code, login_body = check(
    "login", "POST", "/api/auth/login",
    payload={"tenant_slug": TENANT_SLUG, "email": EMAIL, "password": PASSWORD},
)
token = None
if login_code and 200 <= login_code < 300 and login_body:
    token = login_body.get("access_token")

if not token:
    print("XXX Login fallo, no se puede continuar con el resto de los checks.")
    for status, method, path, code, err in results:
        print(f"  [{status}] {method} {path} -> {code} {err}")
    sys.exit(1)

check("me", "GET", "/api/auth/me", token)

# --- listados base (sin parametros) ---
_, employees = check("employees", "GET", "/api/employees", token)
_, branches = check("branches", "GET", "/api/branches", token)
_, devices = check("devices", "GET", "/api/devices", token)
check("attendance", "GET", "/api/attendance", token)
check("attendance report", "GET", "/api/attendance/report", token)
check("exceptions", "GET", "/api/exceptions", token)
check("exceptions pending-check", "GET", "/api/exceptions/pending-check", token)
check("confianza operativa flags", "GET", "/api/confianza-operativa/flags", token)
check("feature flags (catalogo)", "GET", "/api/feature-flags", token)
check("feature flags (tenant)", "GET", "/api/feature-flags/tenant", token)
_, shifts = check("shifts", "GET", "/api/shifts", token)
check("shifts assignments", "GET", "/api/shifts/assignments", token)
check("rbac roles", "GET", "/api/rbac/roles", token)
check("rbac permissions", "GET", "/api/rbac/permissions", token)
check("auth users", "GET", "/api/auth/users", token)
check("legal audit-log", "GET", "/api/legal/audit-log", token)

# --- catalogos de nomina ---
check("catalog concepts", "GET", "/api/catalogs/concepts", token)
check("catalog holidays", "GET", "/api/catalogs/holidays", token)
check("catalog payroll-hours", "GET", "/api/catalogs/payroll-hours", token)
check("catalog tax-brackets", "GET", "/api/catalogs/tax-brackets", token)
check("catalog renta-credits", "GET", "/api/catalogs/renta-credits", token)
check("catalog vacation-config", "GET", "/api/catalogs/vacation-config", token)
check("catalog aguinaldo-config", "GET", "/api/catalogs/aguinaldo-config", token)
check("catalog cesantia-config", "GET", "/api/catalogs/cesantia-config", token)
check("catalog cesantia-scale", "GET", "/api/catalogs/cesantia-scale", token)
check("catalog chart-of-accounts", "GET", "/api/catalogs/chart-of-accounts", token)
check("catalog bank-file-config", "GET", "/api/catalogs/bank-file-config", token)
check("catalog payroll-anomaly-config", "GET", "/api/catalogs/payroll-anomaly-config", token)

# --- nomina (periodos, calculos) ---
_, periods = check("payroll periods", "GET", "/api/payroll/periods", token)
check("payroll net", "GET", "/api/payroll/net", token)
check("payroll overtime", "GET", "/api/payroll/overtime", token)
check("payroll vacations", "GET", "/api/payroll/vacations", token)
check("payroll vacations balance", "GET", "/api/payroll/vacations/balance", token)
check("payroll aguinaldo", "GET", "/api/payroll/aguinaldo", token)
check("payroll terminations", "GET", "/api/payroll/terminations", token)
check("accounting journal-entries", "GET", "/api/accounting/journal-entries", token)
check("bank-file", "GET", "/api/bank-file", token)

# --- dependientes de datos existentes (employee_id, shift_id, period_id) ---
emp_id = None
if isinstance(employees, list) and employees:
    emp_id = employees[0].get("id")
if emp_id:
    check("employee biometric-enrollments", "GET", f"/api/employees/{emp_id}/biometric-enrollments", token)
    check("employee contracts", "GET", f"/api/employees/{emp_id}/contracts", token)
    check("employee dependents", "GET", f"/api/employees/{emp_id}/dependents", token)
else:
    results.append(("WARN", "GET", "/api/employees/{id}/...", "-", "no hay empleados para probar sub-rutas"))

if isinstance(shifts, list) and shifts:
    shift_id = shifts[0].get("id")
    check("shift coverage", "GET", f"/api/shifts/{shift_id}/coverage", token)

if isinstance(periods, list) and periods:
    period_id = periods[0].get("id")
    check("payroll period snapshot", "GET", f"/api/payroll/periods/{period_id}/snapshot", token)

# --- resumen ---
print("")
print("=== RESULTADO ===")
ok = sum(1 for r in results if r[0] == "OK")
warn = sum(1 for r in results if r[0] == "WARN")
fail = sum(1 for r in results if r[0] == "FAIL")
for status, method, path, code, err in results:
    marker = {"OK": "OK  ", "WARN": "WARN", "FAIL": "FAIL"}[status]
    line = f"[{marker}] {method:6s} {path:45s} -> {code}"
    if err:
        line += f"  ({err})"
    print(line)

print("")
print(f"Total: {len(results)} checks -> {ok} OK, {warn} WARN (revisar si aplica), {fail} FAIL (bug real)")
if fail > 0:
    print("XXX Hay errores 5xx - revisar antes de la demo.")
    sys.exit(1)
else:
    print("OK: sin errores 5xx. Los WARN (4xx) son normales si ese modulo no tiene datos cargados todavia.")
PYEOF

echo ""
echo "=== FIN verificacion final demo ==="
