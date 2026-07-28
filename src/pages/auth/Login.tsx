import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { Loader2 } from "lucide-react";
import { toast } from "sonner";
import { useAuth } from "@/context/AuthContext";
import { supabase } from "@/lib/supabase";
import { ORGANIZATION_ID } from "@/lib/organization";
import { loginSchema } from "@/lib/validations";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Logo } from "@/components/Logo";

export default function LoginPage() {
  const { signIn } = useAuth();
  const navigate = useNavigate();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const parsed = loginSchema.safeParse({ email, password });
    if (!parsed.success) {
      toast.error(parsed.error.issues[0]?.message ?? "بيانات غير صحيحة");
      return;
    }
    setLoading(true);
    try {
      await signIn(email, password);
      // توجيه حسب العضوية في organization_members (بدل الدور القديم المخزَّن)
      const { data } = await supabase.auth.getUser();
      const { data: membership } = await supabase
        .from("organization_members")
        .select("organization_id")
        .eq("user_id", data.user!.id)
        .eq("organization_id", ORGANIZATION_ID)
        .maybeSingle();
      toast.success("مرحباً بعودتك!");
      navigate(membership ? "/doctor" : "/patient");
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "تعذّر تسجيل الدخول");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-hero-gradient px-4">
      <Card className="w-full max-w-md shadow-lg">
        <CardHeader className="text-center">
          <Link to="/" className="mb-2 block">
            <Logo size="lg" className="justify-center" />
          </Link>
          <CardTitle className="text-2xl">تسجيل الدخول</CardTitle>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="email">البريد الإلكتروني</Label>
              <Input
                id="email"
                type="email"
                dir="ltr"
                placeholder="name@example.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="text-left"
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="password">كلمة المرور</Label>
              <Input
                id="password"
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
              />
            </div>
            <Button type="submit" className="w-full" disabled={loading}>
              {loading && <Loader2 className="size-4 animate-spin" />}
              دخول
            </Button>
          </form>
          <p className="mt-4 text-center text-sm text-muted-foreground">
            ليس لديك حساب؟{" "}
            <Link to="/register" className="font-medium text-primary hover:underline">
              أنشئ حساباً جديداً
            </Link>
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
