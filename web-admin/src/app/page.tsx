import { redirect } from "next/navigation";

import { getServerSession } from "@/lib/auth/session.server";

export default async function RootPage() {
  const session = await getServerSession();
  redirect(session ? "/dashboard" : "/login");
}
