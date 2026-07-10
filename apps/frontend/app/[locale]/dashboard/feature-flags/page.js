"use client";

import { useEffect, useState } from "react";
import { useTranslations } from "next-intl";
import { ToggleLeft } from "lucide-react";
import { apiFetch } from "../../../../lib/api";
import { useToast } from "../../../../lib/toast";
import { LoadingState, EmptyState } from "../../../../lib/ui";

export default function FeatureFlagsPage() {
  const t = useTranslations("feature_flags");
  const { showToast } = useToast();
  const [flags, setFlags] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [toggling, setToggling] = useState(null);
  const [message, setMessage] = useState(null);

  useEffect(() => {
    load();
  }, []);

  function load() {
    setLoading(true);
    apiFetch("/api/feature-flags/tenant")
      .then(setFlags)
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }

  async function handleToggle(flag) {
    setToggling(flag.code);
    setError(null);
    setMessage(null);
    try {
      await apiFetch("/api/feature-flags/tenant/" + flag.code, {
        method: "PATCH",
        body: JSON.stringify({ enabled: !flag.enabled, branch_id: null }),
      });
      showToast(t("updated_ok"));
      load();
    } catch (err) {
      setError(err.message);
      showToast(err.message, "error");
    } finally {
      setToggling(null);
    }
  }

  function sourceLabel(source) {
    const key = "source_" + source;
    const translated = t(key);
    return translated === key ? source : translated;
  }

  const categories = [...new Set(flags.map((f) => f.category))];

  return (
    <div>
      <h1 className="font-heading text-2xl font-extrabold text-bk-brown mb-6">{t("title")}</h1>

      {error && (
        <p className="text-sm text-bk-red bg-bk-red/10 rounded-lg px-3 py-2 mb-4">{error}</p>
      )}

      {loading ? (
        <LoadingState />
      ) : flags.length === 0 ? (
        <EmptyState icon={ToggleLeft} message={t("no_flags")} />
      ) : (
        <div className="space-y-6">
          {categories.map((cat) => (
            <div key={cat} className="bg-white rounded-xl shadow-sm border border-bk-brown/10 overflow-hidden">
              <div className="px-5 py-3 border-b border-bk-brown/10 bg-bk-cream2/60">
                <h2 className="font-heading font-bold text-bk-brown text-sm uppercase tracking-wide">
                  {cat}
                </h2>
              </div>
              <ul className="divide-y divide-bk-brown/10">
                {flags
                  .filter((f) => f.category === cat)
                  .map((f) => (
                    <li key={f.code} className="px-5 py-4 flex items-center justify-between gap-4">
                      <div>
                        <p className="font-semibold text-bk-brown text-sm">{f.name}</p>
                        <p className="text-xs text-bk-brown/50 mt-0.5">{sourceLabel(f.source)}</p>
                      </div>
                      <div className="flex items-center gap-3 shrink-0">
                        <span
                          className={
                            f.enabled
                              ? "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-green-100 text-green-700"
                              : "inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold bg-bk-brown/10 text-bk-brown/60"
                          }
                        >
                          {f.enabled ? t("enabled") : t("disabled")}
                        </span>
                        <button
                          onClick={() => handleToggle(f)}
                          disabled={toggling === f.code}
                          className={
                            f.enabled
                              ? "w-11 h-6 rounded-full bg-bk-orange relative transition disabled:opacity-50"
                              : "w-11 h-6 rounded-full bg-bk-brown/20 relative transition disabled:opacity-50"
                          }
                        >
                          <span
                            className={
                              f.enabled
                                ? "absolute top-0.5 right-0.5 w-5 h-5 rounded-full bg-white transition"
                                : "absolute top-0.5 left-0.5 w-5 h-5 rounded-full bg-white transition"
                            }
                          />
                        </button>
                      </div>
                    </li>
                  ))}
              </ul>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
