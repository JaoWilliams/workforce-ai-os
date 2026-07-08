"use client";
import { useEffect } from "react";
import { useRouter, useParams } from "next/navigation";

export default function Home() {
  const router = useRouter();
  const params = useParams();
  useEffect(() => {
    router.replace(`/${params.locale}/login`);
  }, [router, params.locale]);
  return null;
}
