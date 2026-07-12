#!/bin/bash
# ============================================================
# Retrofit toast/#118 - Marcacion: usar sistema de Toast estandar
# ademas del mensaje inline (que se conserva por el link a Confianza).
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

python3 << 'PYEOF'
path = "apps/frontend/app/[locale]/dashboard/marcacion/page.js"
with open(path, encoding="utf-8") as f:
    src = f.read()

edits = []

edits.append(("import useToast", '''import { usePermissions } from "../../../../lib/permissions";''',
'''import { usePermissions } from "../../../../lib/permissions";
import { useToast } from "../../../../lib/toast";'''))

edits.append(("hook showToast", '''  const { hasPermission } = usePermissions();''',
'''  const { hasPermission } = usePermissions();
  const { showToast } = useToast();'''))

edits.append(("toast en handleCreate", '''      await apiFetch("/api/attendance", { method: "POST", body: JSON.stringify(payload) });
      setCreateOk(true);
      setRecordedAt(nowLocalInputValue());
      loadRecords();
    } catch (err) {
      setCreateError(err.message);
    } finally {
      setCreating(false);
    }
  }''',
'''      await apiFetch("/api/attendance", { method: "POST", body: JSON.stringify(payload) });
      setCreateOk(true);
      showToast(t("created_ok_toast"));
      setRecordedAt(nowLocalInputValue());
      loadRecords();
    } catch (err) {
      setCreateError(err.message);
      showToast(err.message, "error");
    } finally {
      setCreating(false);
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
for marker in ["useToast", "showToast"]:
    if marker not in check:
        problemas.append(f"falta: {marker}")
if problemas:
    print("XXX VERIFICACION FALLO XXX")
    for p in problemas:
        print(" -", p)
    raise SystemExit(1)
print("OK: marcacion/page.js verificado correctamente")
PYEOF

# ---------- i18n: attendance.created_ok_toast ----------
python3 << 'PYEOF'
import json

nuevas_es = {"created_ok_toast": "Marcación registrada correctamente"}
nuevas_en = {"created_ok_toast": "Attendance record created successfully"}

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

echo "=== FIN retrofit marcacion toast ==="
