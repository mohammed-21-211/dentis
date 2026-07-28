import { Navigate, useLocation } from "react-router-dom";
import type { ReactNode } from "react";
import { useAuth } from "@/context/AuthContext";
import { Loader2 } from "lucide-react";

interface ProtectedRouteProps {
  children: ReactNode;
  /**
   * هل يتطلّب هذا المسار عضوية في organization_members (كادر/طبيب)؟
   * true = كادر فقط، false = غير الكادر (مريض) فقط، undefined = يكفي تسجيل الدخول.
   */
  requireStaff?: boolean;
}

export function ProtectedRoute({ children, requireStaff }: ProtectedRouteProps) {
  const { user, isStaff, loading } = useAuth();
  const location = useLocation();

  // eslint-disable-next-line no-console
  console.log("[AuthDebug][ProtectedRoute] evaluate", {
    path: location.pathname,
    requireStaff,
    isStaff,
    loading,
    userId: user?.id ?? null,
  });

  if (loading) {
    // eslint-disable-next-line no-console
    console.log("[AuthDebug][ProtectedRoute] decision: loading — showing spinner, no redirect");
    return (
      <div className="flex min-h-screen items-center justify-center">
        <Loader2 className="size-8 animate-spin text-primary" />
      </div>
    );
  }

  if (!user) {
    // eslint-disable-next-line no-console
    console.log("[AuthDebug][ProtectedRoute] decision: no user — redirect to /login");
    return <Navigate to="/login" state={{ from: location }} replace />;
  }

  if (requireStaff !== undefined && requireStaff !== isStaff) {
    const target = isStaff ? "/doctor" : "/patient";
    // eslint-disable-next-line no-console
    console.log(
      `[AuthDebug][ProtectedRoute] decision: requireStaff(${requireStaff}) !== isStaff(${isStaff}) — redirect to ${target}`,
    );
    // إعادة التوجيه إلى اللوحة المطابقة لعضويته الفعلية
    return <Navigate to={target} replace />;
  }

  // eslint-disable-next-line no-console
  console.log("[AuthDebug][ProtectedRoute] decision: authorized — rendering children");
  return <>{children}</>;
}
