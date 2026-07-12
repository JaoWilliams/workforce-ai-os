#!/bin/bash
# ============================================================
# #109 - Marcacion -> Excepciones: boton "corregir marca"
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

# ---------- 1. marcacion/page.js: boton corregir por registro ----------
python3 << 'PYEOF'
path = "apps/frontend/app/[locale]/dashboard/marcacion/page.js"
with open(path, encoding="utf-8") as f:
    src = f.read()

old = '''                  <p className="text-xs text-bk-brown/60 mt-0.5">
                    {t("verification_method")}: {t("method_" + r.verification_method)} · {r.recorded_at}
                  </p>
                </li>'''
new = '''                  <p className="text-xs text-bk-brown/60 mt-0.5">
                    {t("verification_method")}: {t("method_" + r.verification_method)} · {r.recorded_at}
                  </p>
                  {hasPermission("exceptions.manage") && (
                    <a
                      href={
                        "/" + locale + "/dashboard/excepciones?employee_id=" + r.employee_id +
                        "&attendance_record_id=" + r.id
                      }
                      className="inline-block mt-2 text-[11px] font-semibold text-bk-orange hover:underline"
                    >
                      {t("correct_record")}
                    </a>
                  )}
                </li>'''

assert old in src, "ANCHOR NOT FOUND: li de registro"
assert src.count(old) == 1, "ANCHOR NOT UNIQUE: li de registro"
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
if "correct_record" not in check:
    problemas.append("falta: correct_record")
if problemas:
    print("XXX VERIFICACION FALLO XXX")
    for p in problemas:
        print(" -", p)
    raise SystemExit(1)
print("OK: marcacion/page.js verificado correctamente")
PYEOF

# ---------- 2. excepciones/page.js: leer employee_id/attendance_record_id de la URL ----------
python3 << 'PYEOF'
path = "apps/frontend/app/[locale]/dashboard/excepciones/page.js"
with open(path, encoding="utf-8") as f:
    src = f.read()

edits = []

edits.append(("import useSearchParams", '''import { useTranslations } from "next-intl";''',
'''import { useTranslations } from "next-intl";
import { useSearchParams } from "next/navigation";'''))

edits.append(("hook searchParams", '''  const { showToast } = useToast();''',
'''  const { showToast } = useToast();
  const searchParams = useSearchParams();'''))

edits.append(("effect prefill desde URL", '''  function load() {''',
'''  useEffect(() => {
    const empId = searchParams.get("employee_id");
    const attId = searchParams.get("attendance_record_id");
    if (empId) setEmployeeId(empId);
    if (attId) {
      setAttendanceRecordId(attId);
      setExceptionType("manual_correction");
    }
  }, [searchParams]);
  function load() {'''))

for label, old, new in edits:
    assert old in src, f"ANCHOR NOT FOUND ({label})"
    assert src.count(old) == 1, f"ANCHOR NOT UNIQUE ({label})"
    src = src.replace(old, new, 1)
    print(f"OK edicion aplicada (excepciones): {label}")

with open(path, "w", encoding="utf-8") as f:
    f.write(src)

with open(path, encoding="utf-8") as f:
    check = f.read()
problemas = []
if check.count("{") != check.count("}"):
    problemas.append(f"llaves desbalanceadas: {{ {check.count('{')} vs }} {check.count('}')}")
if check.count("(") != check.count(")"):
    problemas.append(f"parentesis desbalanceados: ( {check.count('(')} vs ) {check.count(')')}")
for marker in ["useSearchParams", "attendance_record_id"]:
    if marker not in check:
        problemas.append(f"falta: {marker}")
if problemas:
    print("XXX VERIFICACION FALLO XXX")
    for p in problemas:
        print(" -", p)
    raise SystemExit(1)
print("OK: excepciones/page.js verificado correctamente")
PYEOF

# ---------- 3. i18n: attendance.correct_record ----------
python3 << 'PYEOF'
import json

nuevas_es = {"correct_record": "Corregir marca"}
nuevas_en = {"correct_record": "Correct record"}

for path, nuevas in [
    ("apps/frontend/messages/es.json", nuevas_es),
    ("apps/frontend/messages/en.json", nuevas_en),
]:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    data.setdefault("attendance", {})
    added = 0
    for k, v in nuevas.items():
        if k not in data["attendance"]:
            data["attendance"][k] = v
            added += 1
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"OK: {path} - attendance +{added}")
PYEOF

echo "=== rebuild frontend ==="
docker compose build --no-cache frontend
docker compose up -d frontend
sleep 5
docker compose logs frontend --tail 30

echo "=== FIN marcacion -> excepciones ==="
