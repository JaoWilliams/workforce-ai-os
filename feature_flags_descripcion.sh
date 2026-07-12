#!/bin/bash
# ============================================================
# #110 - Feature Flags: mostrar descripcion (ya existe en el modelo,
# solo faltaba en el schema/response de /tenant y en el frontend).
# El "alcance" (default/tenant override/branch override) ya se
# mostraba via sourceLabel(f.source) - no requiere cambios.
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

# ---------- 1. backend: schemas.py ----------
python3 << 'PYEOF'
path = "apps/backend/app/modules/feature_flags/schemas.py"
with open(path, encoding="utf-8") as f:
    src = f.read()

old = '''class TenantFeatureFlagStatus(BaseModel):
    code: str
    name: str
    category: str
    enabled: bool
    source: str  # "branch_override" | "tenant_override" | "default"'''
new = '''class TenantFeatureFlagStatus(BaseModel):
    code: str
    name: str
    description: str
    category: str
    enabled: bool
    source: str  # "branch_override" | "tenant_override" | "default"'''

assert old in src, "ANCHOR NOT FOUND: TenantFeatureFlagStatus"
assert src.count(old) == 1, "ANCHOR NOT UNIQUE: TenantFeatureFlagStatus"
src = src.replace(old, new, 1)
with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("OK: schemas.py - description agregado a TenantFeatureFlagStatus")
PYEOF

# ---------- 2. backend: router.py (2 sitios de construccion) ----------
python3 << 'PYEOF'
path = "apps/backend/app/modules/feature_flags/router.py"
with open(path, encoding="utf-8") as f:
    src = f.read()

edits = []

edits.append(("construccion en list_tenant_status", '''            status_list.append(TenantFeatureFlagStatus(
                code=flag.code, name=flag.name, category=flag.category, enabled=enabled, source=source,
            ))''',
'''            status_list.append(TenantFeatureFlagStatus(
                code=flag.code, name=flag.name, description=flag.description,
                category=flag.category, enabled=enabled, source=source,
            ))'''))

edits.append(("construccion en toggle_tenant_flag", '''    return TenantFeatureFlagStatus(
        code=flag.code, name=flag.name, category=flag.category, enabled=payload.enabled, source=source,
    )''',
'''    return TenantFeatureFlagStatus(
        code=flag.code, name=flag.name, description=flag.description,
        category=flag.category, enabled=payload.enabled, source=source,
    )'''))

for label, old, new in edits:
    assert old in src, f"ANCHOR NOT FOUND ({label})"
    assert src.count(old) == 1, f"ANCHOR NOT UNIQUE ({label})"
    src = src.replace(old, new, 1)
    print(f"OK edicion aplicada: {label}")

with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("OK: router.py escrito")
PYEOF

echo "=== verificacion de sintaxis backend ==="
python3 -m py_compile apps/backend/app/modules/feature_flags/schemas.py && echo "schemas.py SYNTAX OK"
python3 -m py_compile apps/backend/app/modules/feature_flags/router.py && echo "router.py SYNTAX OK"

# ---------- 3. frontend: mostrar description ----------
python3 << 'PYEOF'
path = "apps/frontend/app/[locale]/dashboard/feature-flags/page.js"
with open(path, encoding="utf-8") as f:
    src = f.read()

old = '''                    <li key={f.code} className="px-5 py-4 flex items-center justify-between gap-4">
                      <div>
                        <p className="font-semibold text-bk-brown text-sm">{f.name}</p>
                        <p className="text-xs text-bk-brown/50 mt-0.5">{sourceLabel(f.source)}</p>
                      </div>'''
new = '''                    <li key={f.code} className="px-5 py-4 flex items-center justify-between gap-4">
                      <div>
                        <p className="font-semibold text-bk-brown text-sm">{f.name}</p>
                        {f.description && (
                          <p className="text-xs text-bk-brown/70 mt-0.5">{f.description}</p>
                        )}
                        <p className="text-xs text-bk-brown/50 mt-0.5">{sourceLabel(f.source)}</p>
                      </div>'''

assert old in src, "ANCHOR NOT FOUND: li de flag"
assert src.count(old) == 1, "ANCHOR NOT UNIQUE: li de flag"
src = src.replace(old, new, 1)
with open(path, "w", encoding="utf-8") as f:
    f.write(src)

with open(path, encoding="utf-8") as f:
    check = f.read()
problemas = []
if check.count("{") != check.count("}"):
    problemas.append(f"llaves desbalanceadas: {{ {check.count('{')} vs }} {check.count('}')}")
if check.count("(") != check.count(")"):
    problemas.append(f"parentesis desbalanceados: ( {check.count('(')} vs ) {check.count(')')}")
if "f.description" not in check:
    problemas.append("falta: f.description")
if problemas:
    print("XXX VERIFICACION FALLO XXX")
    for p in problemas:
        print(" -", p)
    raise SystemExit(1)
print("OK: feature-flags/page.js verificado correctamente")
PYEOF

# ---------- 4. rebuild api + frontend ----------
echo "=== rebuild api ==="
docker compose build --no-cache api
docker compose up -d api
sleep 5
docker compose logs api --tail 20

echo "=== rebuild frontend ==="
docker compose build --no-cache frontend
docker compose up -d frontend
sleep 5
docker compose logs frontend --tail 20

echo "=== FIN feature flags descripcion ==="
