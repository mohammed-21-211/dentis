import { AlertTriangle, Terminal } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { isSupabaseConfigured } from "@/lib/supabase";

/**
 * شاشة تُعرض عندما تكون متغيّرات بيئة Supabase أو معرّف العيادة غير
 * مضبوطة، بدلاً من صفحة بيضاء صامتة. ترشد المطوّر لإكمال الإعداد.
 */
export default function SetupNotice() {
  const missingSupabase = !isSupabaseConfigured;

  return (
    <div className="flex min-h-screen items-center justify-center bg-hero-gradient px-4 py-10">
      <Card className="w-full max-w-xl shadow-lg">
        <CardHeader className="text-center">
          <div className="mx-auto mb-3 flex size-14 items-center justify-center rounded-2xl bg-amber-100">
            <AlertTriangle className="size-7 text-amber-600" />
          </div>
          <CardTitle className="text-2xl">
            {missingSupabase ? "إعداد مطلوب: اتصال Supabase" : "إعداد مطلوب: معرّف العيادة"}
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-5">
          <p className="text-center text-muted-foreground">
            {missingSupabase
              ? "لم يتم العثور على مفاتيح Supabase."
              : "لم يتم ضبط VITE_ORGANIZATION_ID — هذا التطبيق يخدم عيادة واحدة محدَّدة داخل قاعدة بيانات متعددة العيادات، ولا يعمل بدون هذا المعرّف."}{" "}
            أكمل الخطوات التالية ثم أعد تشغيل خادم التطوير.
          </p>

          <ol className="space-y-4 text-sm">
            <li className="flex gap-3">
              <span className="flex size-6 shrink-0 items-center justify-center rounded-full bg-primary text-xs font-bold text-primary-foreground">
                ١
              </span>
              <div className="space-y-2">
                <p>افتح ملف <code className="rounded bg-muted px-1.5 py-0.5">.env</code> في جذر المشروع (أنشئه إن لم يكن موجوداً).</p>
              </div>
            </li>
            <li className="flex gap-3">
              <span className="flex size-6 shrink-0 items-center justify-center rounded-full bg-primary text-xs font-bold text-primary-foreground">
                ٢
              </span>
              <div className="space-y-2">
                {missingSupabase ? (
                  <>
                    <p>
                      من لوحة Supabase: <span className="font-medium">Project Settings ← API</span>،
                      انسخ القيمتين:
                    </p>
                    <pre className="overflow-x-auto rounded-lg bg-foreground p-3 text-left text-xs text-background" dir="ltr">
VITE_SUPABASE_URL=https://xxxx.supabase.co
VITE_SUPABASE_ANON_KEY=eyJhbGci...</pre>
                  </>
                ) : (
                  <>
                    <p>
                      أضف معرّف صف المنظمة (<span dir="ltr">organizations.id</span>) الخاص بهذه العيادة:
                    </p>
                    <pre className="overflow-x-auto rounded-lg bg-foreground p-3 text-left text-xs text-background" dir="ltr">
VITE_ORGANIZATION_ID=00000000-0000-0000-0000-000000000000</pre>
                  </>
                )}
              </div>
            </li>
            <li className="flex gap-3">
              <span className="flex size-6 shrink-0 items-center justify-center rounded-full bg-primary text-xs font-bold text-primary-foreground">
                ٣
              </span>
              <div className="flex items-center gap-2">
                <Terminal className="size-4 text-muted-foreground" />
                <p>
                  أعد تشغيل الخادم:{" "}
                  <code className="rounded bg-muted px-1.5 py-0.5" dir="ltr">
                    npm run dev
                  </code>
                </p>
              </div>
            </li>
          </ol>

          <p className="rounded-lg bg-accent/40 p-3 text-center text-xs text-accent-foreground">
            ملاحظة: لا تنسَ تطبيق ملفّات الهجرة في <span dir="ltr">supabase/migrations</span> داخل
            لوحة Supabase.
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
