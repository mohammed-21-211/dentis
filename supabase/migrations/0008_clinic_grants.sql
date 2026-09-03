-- =============================================================================
--  Migration 0008 — صلاحيات جداول schema clinic لأدوار الـ Data API
--  Dental Clinic Migration 0008 — table/sequence/function GRANTs for API roles
--
--  السبب (Root cause): Migration 0001 منح `usage` على schema clinic فقط، دون
--  أي صلاحيات على مستوى الجداول. في المخططات المخصّصة (غير `public`) لا تُمنح
--  صلاحيات الجداول تلقائياً لأدوار الـ Data API، فكانت كل الطلبات على
--  clinic.* ترجع 42501 "permission denied for table ..." بمجرّد تعريض المخطط،
--  ما منع (مثلاً) إضافة/حذف/تفعيل الخدمات من لوحة الطبيب.
--
--  الأمان: RLS مفعَّلة على الجداول الثمانية جميعها (Migration 0006). لذلك منح
--  DML للدور `authenticated` آمن — السياسات هي ما يحدّد الصفوف المسموح بها
--  فعلياً (services/clinic_hours/... تتطلّب public.is_org_member؛ notifications
--  وappointment_reminders بلا سياسة إدراج للمستخدم فتبقى محجوبة رغم المنح).
--
--  قابلة لإعادة التشغيل (Idempotent): grant / alter default privileges.
-- =============================================================================

grant usage on schema clinic to anon, authenticated, service_role;

-- قراءة: RLS تُقيّد الصفوف؛ كلا الدورين يقرآن ما تسمح به السياسات فقط
grant select on all tables in schema clinic to anon, authenticated;

-- كتابة على مستوى الجدول للـ authenticated (RLS تفرض عضوية العيادة/الملكية)
grant insert, update, delete on all tables in schema clinic to authenticated;

-- إرسال تقييم من زائر عام (سياسة reviews_insert_public: is_approved = false)
grant insert on clinic.reviews to anon;

-- service_role: صلاحية كاملة (للعمليات الخلفية/الدوال)
grant all on all tables in schema clinic to service_role;

-- التسلسلات (آمن حتى لو لا يوجد أي منها حالياً — كل المفاتيح uuid)
grant usage, select on all sequences in schema clinic to anon, authenticated, service_role;

-- تنفيذ دوال schema clinic إن وُجدت (دوال الحجز الرئيسية في public، لكن هذا يشمل أي دالة مستقبلية)
grant execute on all functions in schema clinic to anon, authenticated, service_role;

-- الجداول/التسلسلات/الدوال المستقبلية في clinic ترث الصلاحيات تلقائياً
alter default privileges in schema clinic grant select on tables to anon, authenticated;
alter default privileges in schema clinic grant insert, update, delete on tables to authenticated;
alter default privileges in schema clinic grant all on tables to service_role;
alter default privileges in schema clinic grant usage, select on sequences to anon, authenticated, service_role;
alter default privileges in schema clinic grant execute on functions to anon, authenticated, service_role;
