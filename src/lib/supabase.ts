import { createClient } from "@supabase/supabase-js";

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined;

/**
 * هل تم ضبط متغيّرات بيئة Supabase؟
 * نتفادى رمي خطأ عند تحميل الوحدة (الذي يسبّب صفحة بيضاء صامتة)،
 * ونعرض بدلاً منه شاشة إعداد واضحة عبر بوّابة التهيئة في App.
 */
export const isSupabaseConfigured = Boolean(
  supabaseUrl &&
    supabaseAnonKey &&
    // تجاهل القيم النائبة الموجودة في ملف .env.example
    !supabaseUrl.includes("your-project-ref") &&
    !supabaseAnonKey.includes("your-anon"),
);

// عميل صالح دائماً للاستيراد؛ يستخدم قيماً نائبة عند غياب الإعداد
// (الطلبات تفشل بلطف، والواجهة لا تنهار).
export const supabase = createClient(
  supabaseUrl || "https://placeholder.supabase.co",
  supabaseAnonKey || "placeholder-anon-key",
  {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
    },
  },
);

/**
 * عميل مُخصَّص لِschema "clinic" (جداول العيادة: services, clinic_hours,
 * appointments, medical_records, notifications, case_studies, reviews,
 * appointment_reminders). العميل الافتراضي أعلاه يبقى على "public" (جداول
 * الـ Backbone المشتركة: profiles, organizations, organization_members).
 * استخدم clinicDb.from(...) بدل supabase.from(...) لأي جدول من جداول العيادة.
 */
export const clinicDb = supabase.schema("clinic");
