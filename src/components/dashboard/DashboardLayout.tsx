import type { ReactNode } from "react";
import { Link, useNavigate } from "react-router-dom";
import { LogOut } from "lucide-react";
import { useAuth } from "@/context/AuthContext";
import { Button } from "@/components/ui/button";
import { Logo } from "@/components/Logo";
import { NotificationBell } from "./NotificationBell";

interface DashboardLayoutProps {
  title: string;
  children: ReactNode;
  /** عناصر تنقل اختيارية (تبويبات) */
  nav?: ReactNode;
}

export function DashboardLayout({ title, children, nav }: DashboardLayoutProps) {
  const { profile, isStaff, signOut } = useAuth();
  const navigate = useNavigate();

  async function handleSignOut() {
    await signOut();
    navigate("/");
  }

  return (
    <div className="min-h-screen bg-muted/30">
      <header className="sticky top-0 z-30 border-b border-border bg-background">
        <div className="container flex h-16 items-center justify-between gap-3 sm:h-20 sm:gap-4">
          <Link to="/" className="min-w-0 flex-shrink">
            <Logo />
          </Link>

          <div className="flex shrink-0 items-center gap-2">
            <NotificationBell />
            <div className="hidden text-left sm:block">
              <p className="text-sm font-medium leading-tight">{profile?.full_name}</p>
              <p className="text-xs text-muted-foreground">
                {isStaff ? "طبيب" : "مريض"}
              </p>
            </div>
            <Button variant="outline" size="icon" onClick={handleSignOut} aria-label="خروج">
              <LogOut className="size-4" />
            </Button>
          </div>
        </div>
      </header>

      <main className="container py-8">
        <div className="mb-6 flex flex-wrap items-center justify-between gap-4">
          <h1 className="font-display text-2xl font-extrabold">{title}</h1>
          {nav}
        </div>
        {children}
      </main>
    </div>
  );
}
