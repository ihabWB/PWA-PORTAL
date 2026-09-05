import { redirect } from "next/navigation";

/**
 * The one question Phase 1 exists to answer is the Saeer arrival balance, so that is the
 * landing screen. Nothing else earns the first position yet.
 */
export default function HomePage() {
  redirect("/saeer");
}
