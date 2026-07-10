"use client";

import { Loader2 } from "lucide-react";

export function LoadingState({ compact = false }) {
  return (
    <div className={compact ? "flex items-center justify-center py-6" : "flex items-center justify-center py-16"}>
      <Loader2 className="animate-spin text-bk-orange" size={compact ? 18 : 26} strokeWidth={2.5} />
    </div>
  );
}

export function EmptyState({ icon: Icon, message }) {
  return (
    <div className="flex flex-col items-center justify-center py-10 text-center px-4">
      {Icon && <Icon size={26} className="text-bk-brown/25 mb-2" strokeWidth={1.5} />}
      <p className="text-sm text-bk-brown/50">{message}</p>
    </div>
  );
}
