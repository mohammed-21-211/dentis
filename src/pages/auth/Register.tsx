import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { Loader2 } from "lucide-react";
import { toast } from "sonner";
import { useAuth } from "@/context/AuthContext";
import { registerSchema } from "@/lib/validations";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Logo } from "@/components/Logo";

export default function RegisterPage() {
  const { signUp } = useAuth();
  const navigate = useNavigate();
  const [form, setForm] = useState({
    fullName: "",
    email: "",
    phone: "",
    password: "",
    confirmPassword: "",
  });
  const [loading, setLoading] = useState(false);

  function update(key: keyof typeof form, value: string) {
    setForm((f) => ({ ...f, [key]: value }));
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const parsed = registerSchema.safeParse(form);
    if (!parsed.success) {
      toast.error(parsed.error.issues[0]?.message ?? "تحقق من البيانات");
      return;
    }
    setLoading(true);
    try {
      await signUp({
        email: form.email,
        password: form.password,
        fullName: form.fullName,
        phone: form.phone,
      });
      toast.success("تم إنشاء حسابك بنجاح!");
      navigate("/patient");
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "تعذّر إنشاء الحساب");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-hero-gradient px-4 py-10">
      <Card className="w-full max-w-md shadow-lg">
        <CardHeader className="text-center">
          <Link to="/" className="mb-2 block">
            <Logo size="lg" className="justify-center" />
          </Link>
          <CardTitle className="text-2xl">إنشاء حساب جديد</CardTitle>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="fullName">الاسم الكامل</Label>
              <Input
                id="fullName"
                value={form.fullName}
                onChange={(e) => update("fullName", e.target.value)}
                placeholder="مثال: محمد أحمد"
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="email">البريد الإلكتروني</Label>
              <Input
                id="email"
                type="email"
                dir="ltr"
                className="text-left"
                value={form.email}
                onChange={(e) => update("email", e.target.value)}
                placeholder="name@example.com"
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="phone">رقم الهاتف</Label>
              <Input
                id="phone"
                type="tel"
                dir="ltr"
                className="text-left"
                value={form.phone}
                onChange={(e) => update("phone", e.target.value)}
                placeholder="05xxxxxxxx"
              />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-2">
                <Label htmlFor="password">كلمة المرور</Label>
                <Input
                  id="password"
                  type="password"
                  value={form.password}
                  onChange={(e) => update("password", e.target.value)}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="confirmPassword">تأكيد كلمة المرور</Label>
                <Input
                  id="confirmPassword"
                  type="password"
                  value={form.confirmPassword}
                  onChange={(e) => update("confirmPassword", e.target.value)}
                />
              </div>
            </div>
            <Button type="submit" className="w-full" disabled={loading}>
              {loading && <Loader2 className="size-4 animate-spin" />}
              إنشاء الحساب
            </Button>
          </form>
          <p className="mt-4 text-center text-sm text-muted-foreground">
            لديك حساب بالفعل؟{" "}
            <Link to="/login" className="font-medium text-primary hover:underline">
              سجّل الدخول
            </Link>
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
