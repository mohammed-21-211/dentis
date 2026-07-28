-- =============================================================================
--  Migration 0001 — إنشاء schema العيادة (تثبيت جديد بالكامل)
--  Dental Clinic Migration 0001 — clinic schema (fresh install, no legacy data)
--
--  السياق: هذا تثبيت جديد بالكامل داخل مشروع Supabase يحتوي فقط على
--  الـ Backbone المشترك (public.organizations, public.organization_members,
--  public.profiles, public.projects) ومشروع expense قائم. لا توجد أي جداول
--  عيادة سابقة في هذا المشروع — لذلك لا Backfill، لا Move Schema، لا
--  Rewrite References في هذه السلسلة بأكملها؛ كل شيء يُنشأ صحيحاً من البداية.
--
--  النطاق (Scope): schema فارغة + صلاحيات الاستخدام فقط. لا جداول بعد.
--
--  قابلة لإعادة التشغيل (Idempotent): create schema if not exists / grant.
-- =============================================================================

create schema if not exists clinic;

comment on schema clinic is
  'جداول تطبيق عيادة الأسنان (Dental Clinic) فقط — منفصلة عن public/auth الخاصة بالـ Backbone المشترك بين كل التطبيقات (بما فيها expense).';

grant usage on schema clinic to anon, authenticated, service_role;
