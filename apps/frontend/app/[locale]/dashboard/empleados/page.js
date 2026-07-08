"use client";

import { useEffect, useState } from "react";
import { useTranslations } from "next-intl";
import { apiFetch, apiFetchBlob } from "../../../../lib/api";

export default function EmpleadosPage() {
  const t = useTranslations("employees");
  const [employees, setEmployees] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [selected, setSelected] = useState(null);
  const [contracts, setContracts] = useState([]);
  const [contractsLoading, setContractsLoading] = useState(false);
  const [downloadError, setDownloadError] = useState(null);

  useEffect(() => {
    apiFetch("/api/employees")
      .then(setEmployees)
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, []);

  async function selectEmployee(emp) {
    setSelected(emp);
    setContracts([]);
    setContractsLoading(true);
    try {
      const data = await apiFetch("/api/employees/" + emp.id + "/contracts");
      setContracts(data);
    } catch (err) {
      setError(err.message);
    } finally {
      setContractsLoading(false);
    }
  }

  async function downloadPdf(contract) {
    setDownloadError(null);
    try {
      const blob = await apiFetchBlob(
        "/api/employees/" + selected.id + "/contracts/" + contract.id + "/pdf"
      );
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = "contrato-" + contract.id + ".pdf";
      document.body.appendChild(a);
      a.click();
      a.remove();
      window.URL.revokeObjectURL(url);
    } catch (err) {
      setDownloadError(err.message);
    }
  }

  function contractTypeLabel(type) {
    const key = "contract_type_" + type;
    const translated = t(key);
    return translated === key ? type : translated;
  }

  function formatMoney(amount, currency) {
    return new Intl.NumberFormat("es-CR", {
      style: "currency",
      currency: currency || "CRC",
      maximumFractionDigits: 2,
    }).format(amount);
  }

  return (
    <div>
      <h1 className="font-heading text-2xl font-extrabold text-bk-brown mb-6">
        {t("title")}
      </h1>

      {error && (
        <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-4">{error}</p>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 overflow-hidden">
          {loading ? (
            <p className="p-4 text-sm text-bk-brown/60">...</p>
          ) : employees.length === 0 ? (
            <p className="p-4 text-sm text-bk-brown/60">{t("no_employees")}</p>
          ) : (
            <ul className="divide-y divide-bk-brown/10">
              {employees.map((emp) => (
                <li key={emp.id}>
                  <button
                    onClick={() => selectEmployee(emp)}
                    className={
                      selected && selected.id === emp.id
                        ? "w-full text-left px-5 py-4 transition bg-bk-orange/10"
                        : "w-full text-left px-5 py-4 transition hover:bg-bk-cream2"
                    }
                  >
                    <p className="font-semibold text-bk-brown">
                      {emp.first_name} {emp.last_name}
                    </p>
                    <p className="text-xs text-bk-brown/60 mt-0.5">
                      {t("id_number")}: {emp.id_number} · {t("position")}: {emp.position}
                    </p>
                    <p className="text-xs mt-1">
                      <span
                        className={
                          emp.active
                            ? "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-green-100 text-green-700"
                            : "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-bk-brown/10 text-bk-brown/60"
                        }
                      >
                        {emp.active ? t("active") : t("inactive")}
                      </span>
                    </p>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>

        <div className="bg-white rounded-xl shadow-sm border border-bk-brown/10 p-5">
          <h2 className="font-heading font-bold text-bk-brown mb-4">
            {t("contracts_title")}
            {selected ? " — " + selected.first_name + " " + selected.last_name : ""}
          </h2>

          {!selected ? (
            <p className="text-sm text-bk-brown/60">{t("select_employee")}</p>
          ) : contractsLoading ? (
            <p className="text-sm text-bk-brown/60">...</p>
          ) : contracts.length === 0 ? (
            <p className="text-sm text-bk-brown/60">{t("no_contracts")}</p>
          ) : (
            <div className="space-y-3">
              {downloadError && (
                <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2">
                  {downloadError}
                </p>
              )}
              {contracts.map((c) => (
                <div key={c.id} className="border border-bk-brown/10 rounded-lg p-4 text-sm">
                  <p className="font-semibold text-bk-brown mb-1">
                    {contractTypeLabel(c.contract_type)}
                  </p>
                  <p className="text-bk-brown/70">
                    {t("start_date")}: {c.start_date} · {t("end_date")}: {c.end_date || t("no_end_date")}
                  </p>
                  <p className="text-bk-brown/70 mb-3">
                    {t("base_salary")}: {formatMoney(c.base_salary, c.currency)}
                  </p>
                  <button
                    onClick={() => downloadPdf(c)}
                    className="text-xs font-semibold text-white rounded-lg px-3 py-1.5"
                    style={{ background: "linear-gradient(135deg, var(--color-bk-orange), var(--color-bk-red))" }}
                  >
                    {t("download_pdf")}
                  </button>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
