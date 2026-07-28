import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import type { Session, User } from "@supabase/supabase-js";
import { supabase } from "@/lib/supabase";
import { ORGANIZATION_ID } from "@/lib/organization";
import type { Profile } from "@/types";

interface AuthContextValue {
  user: User | null;
  session: Session | null;
  profile: Profile | null;
  loading: boolean;
  /** عضو في organization_members لعيادة ORGANIZATION_ID — بديل isDoctor القديم */
  isStaff: boolean;
  signIn: (email: string, password: string) => Promise<void>;
  signUp: (args: {
    email: string;
    password: string;
    fullName: string;
    phone: string;
  }) => Promise<void>;
  signOut: () => Promise<void>;
  refreshProfile: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [user, setUser] = useState<User | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [isStaff, setIsStaff] = useState(false);
  const [loading, setLoading] = useState(true);

  async function loadProfile(userId: string) {
    const { data } = await supabase
      .from("profiles")
      .select("*")
      .eq("id", userId)
      .single();
    setProfile((data as Profile) ?? null);
  }

  /**
   * "طبيب/كادر" لم يعد عموداً مخزَّناً — يُشتق من وجود صف عضوية في
   * public.organization_members لنفس عيادة هذه الواجهة (ORGANIZATION_ID).
   */
  async function loadMembership(userId: string) {
    // eslint-disable-next-line no-console
    console.log("[AuthDebug] loadMembership() userId:", userId);
    // eslint-disable-next-line no-console
    console.log("[AuthDebug] VITE_ORGANIZATION_ID:", ORGANIZATION_ID);

    if (!ORGANIZATION_ID) {
      // eslint-disable-next-line no-console
      console.log("[AuthDebug] ORGANIZATION_ID falsy — skipping query, forcing isStaff=false");
      setIsStaff(false);
      return;
    }
    const { data, error, status, statusText } = await supabase
      .from("organization_members")
      .select("organization_id")
      .eq("user_id", userId)
      .eq("organization_id", ORGANIZATION_ID)
      .maybeSingle();
    // eslint-disable-next-line no-console
    console.log("[AuthDebug] organization_members raw result:", {
      data,
      error,
      status,
      statusText,
    });
    const computed = Boolean(data);
    // eslint-disable-next-line no-console
    console.log("[AuthDebug] computed isStaff:", computed);
    setIsStaff(computed);
  }

  async function loadUserContext(userId: string) {
    await Promise.all([loadProfile(userId), loadMembership(userId)]);
  }

  useEffect(() => {
    // يمنع تحديث الحالة بعد فكّ تركيب المكوّن (تسجيل خروج أثناء طلب معلَّق مثلاً)
    let cancelled = false;

    /**
     * نقطة الحقيقة الوحيدة لتطبيق أي جلسة (سواء عند التحميل الأول عبر
     * getSession، أو عند أي تغيّر لاحق عبر onAuthStateChange — signIn،
     * signUp، signOut، تجديد التوكن، إلخ). كلا المسارين يستدعيان هذه
     * الدالة نفسها بدل تكرار المنطق، لضمان معاملة loading بنفس الطريقة
     * تماماً في كل الحالات:
     *   - loading تصبح true قبل أي استعلام profile/organization_members.
     *   - loading تصبح false فقط بعد اكتمال loadUserContext (نجاحاً أو فشلاً).
     */
    async function applySession(newSession: Session | null) {
      if (cancelled) return;
      // eslint-disable-next-line no-console
      console.log("[AuthDebug] applySession() user id:", newSession?.user?.id ?? null);
      // eslint-disable-next-line no-console
      console.log("[AuthDebug] applySession() user email:", newSession?.user?.email ?? null);

      setSession(newSession);
      setUser(newSession?.user ?? null);

      if (!newSession?.user) {
        // نفس سلوك تسجيل الخروج الأصلي: تفريغ فوري، لا حاجة لحالة تحميل
        setProfile(null);
        setIsStaff(false);
        setLoading(false);
        return;
      }

      setLoading(true);
      try {
        await loadUserContext(newSession.user.id);
      } finally {
        if (!cancelled) setLoading(false);
      }
    }

    // الجلسة الحالية عند التحميل
    supabase.auth.getSession().then(({ data }) => {
      applySession(data.session);
    });

    // الاستماع لتغيّرات المصادقة (signIn/signUp/signOut/تجديد التوكن...)
    const { data: sub } = supabase.auth.onAuthStateChange((_event, newSession) => {
      applySession(newSession);
    });

    return () => {
      cancelled = true;
      sub.subscription.unsubscribe();
    };
  }, []);

  async function signIn(email: string, password: string) {
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) throw new Error(translateAuthError(error.message));
  }

  async function signUp(args: {
    email: string;
    password: string;
    fullName: string;
    phone: string;
  }) {
    const { error } = await supabase.auth.signUp({
      email: args.email,
      password: args.password,
      options: {
        data: { full_name: args.fullName, phone: args.phone },
      },
    });
    if (error) throw new Error(translateAuthError(error.message));
  }

  async function signOut() {
    await supabase.auth.signOut();
    setProfile(null);
    setIsStaff(false);
  }

  async function refreshProfile() {
    if (user) await loadUserContext(user.id);
  }

  const value = useMemo<AuthContextValue>(
    () => ({
      user,
      session,
      profile,
      loading,
      isStaff,
      signIn,
      signUp,
      signOut,
      refreshProfile,
    }),
    [user, session, profile, loading, isStaff],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

// eslint-disable-next-line react-refresh/only-export-components
export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth يجب أن يُستخدم داخل AuthProvider");
  return ctx;
}

/** ترجمة رسائل أخطاء Supabase الشائعة إلى العربية */
function translateAuthError(message: string): string {
  const m = message.toLowerCase();
  if (m.includes("invalid login credentials")) return "بيانات الدخول غير صحيحة";
  if (m.includes("user already registered")) return "هذا البريد مسجّل مسبقاً";
  if (m.includes("email not confirmed")) return "يرجى تأكيد بريدك الإلكتروني أولاً";
  if (m.includes("password")) return "كلمة المرور غير صالحة";
  return "حدث خطأ، يرجى المحاولة مرة أخرى";
}
