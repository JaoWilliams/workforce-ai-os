"use client";

import { useTranslations } from "next-intl";

export default function DashboardHome() {
  const t = useTranslations("dashboard");
  return (
    <div>
      <p className="text-[10px] font-semibold text-bk-orange uppercase tracking-[3px] mb-2">
        Burger King Costa Rica
      </p>
      <h1 className="font-heading text-2xl font-extrabold text-bk-brown mb-3">
        {t("welcome_title")}
      </h1>
      <p className="text-bk-brown/70 max-w-xl leading-relaxed">
        {t("welcome_body")}
      </p>
    </div>
  );
}
