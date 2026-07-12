#!/bin/bash
# ============================================================
# #103 - Marcacion: exigir motivo + aprobacion solo en casos atipicos
# (metodo "manual" = sin verificacion biometrica real). Reutiliza el
# flujo de aprobacion existente en Excepciones: al crear una marcacion
# manual, se crea automaticamente una excepcion "pending" vinculada.
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

python3 << 'PYEOF'
path = "apps/frontend/app/[locale]/dashboard/marcacion/page.js"
with open(path, encoding="utf-8") as f:
    src = f.read()

edits = []

edits.append(("motivo state", '''  const [createOk, setCreateOk] = useState(false);''',
'''  const [createOk, setCreateOk] = useState(false);
  const [motivo, setMotivo] = useState("");'''))

edits.append(("handleCreate con excepcion automatica", '''      const payload = {
        employee_id: employeeId,
        device_id: deviceId,
        type,
        verification_method: method,
        biometric_enrollment_id: enrollmentId || null,
        recorded_at: new Date(recordedAt).toISOString(),
      };
      await apiFetch("/api/attendance", { method: "POST", body: JSON.stringify(payload) });
      setCreateOk(true);
      showToast(t("created_ok_toast"));
      setRecordedAt(nowLocalInputValue());
      loadRecords();''',
'''      const payload = {
        employee_id: employeeId,
        device_id: deviceId,
        type,
        verification_method: method,
        biometric_enrollment_id: enrollmentId || null,
        recorded_at: new Date(recordedAt).toISOString(),
      };
      const created = await apiFetch("/api/attendance", { method: "POST", body: JSON.stringify(payload) });
      if (method === "manual") {
        await apiFetch("/api/exceptions", {
          method: "POST",
          body: JSON.stringify({
            employee_id: employeeId,
            exception_type: "manual_correction",
            justification: motivo,
            attendance_record_id: created.id,
          }),
        });
      }
      setCreateOk(true);
      showToast(method === "manual" ? t("created_pending_toast") : t("created_ok_toast"));
      setMotivo("");
      setRecordedAt(nowLocalInputValue());
      loadRecords();'''))

edits.append(("campo motivo condicional", '''              <div>
                <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("verification_method")}</label>
                <select
                  value={method}
                  onChange={(e) => setMethod(e.target.value)}
                  className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                >
                  {METHODS.map((m) => (
                    <option key={m} value={m}>
                      {t("method_" + m)}
                    </option>
                  ))}
                </select>
              </div>
            </div>''',
'''              <div>
                <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("verification_method")}</label>
                <select
                  value={method}
                  onChange={(e) => setMethod(e.target.value)}
                  className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                >
                  {METHODS.map((m) => (
                    <option key={m} value={m}>
                      {t("method_" + m)}
                    </option>
                  ))}
                </select>
              </div>
            </div>
            {method === "manual" && (
              <div>
                <label className="block text-xs font-medium text-bk-brown/70 mb-1">{t("manual_reason")}</label>
                <textarea
                  required
                  rows={2}
                  value={motivo}
                  onChange={(e) => setMotivo(e.target.value)}
                  placeholder={t("manual_reason_hint")}
                  className="w-full border border-bk-brown/20 rounded-md px-2 py-1.5"
                />
                <p className="text-[11px] text-bk-orange mt-1">{t("manual_reason_notice")}</p>
              </div>
            )}'''))

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
for marker in ["motivo", "manual_reason", "created_pending_toast"]:
    if marker not in check:
        problemas.append(f"falta: {marker}")
if problemas:
    print("XXX VERIFICACION FALLO XXX")
    for p in problemas:
        print(" -", p)
    raise SystemExit(1)
print("OK: marcacion/page.js verificado correctamente")
PYEOF

# ---------- i18n: attendance.manual_reason / manual_reason_hint / manual_reason_notice / created_pending_toast ----------
python3 << 'PYEOF'
import json

nuevas_es = {
    "manual_reason": "Motivo de la marcación manual",
    "manual_reason_hint": "Explicá por qué se registra manualmente (sin verificación biométrica)...",
    "manual_reason_notice": "Esta marcación quedará pendiente de aprobación en Excepciones.",
    "created_pending_toast": "Marcación registrada — pendiente de aprobación",
}
nuevas_en = {
    "manual_reason": "Reason for manual record",
    "manual_reason_hint": "Explain why this is being recorded manually (without biometric verification)...",
    "manual_reason_notice": "This record will be pending approval in Exceptions.",
    "created_pending_toast": "Record created — pending approval",
}

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

echo "=== FIN marcacion motivo atipico ==="
