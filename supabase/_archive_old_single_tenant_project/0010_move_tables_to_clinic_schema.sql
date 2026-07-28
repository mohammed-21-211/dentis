-- =============================================================================
--  Migration 0010 — نقل جداول العيادة إلى schema clinic
--  Dental Clinic Migration 0010 — move clinic tables to the clinic schema
--
--  النطاق (Scope): نقل الجداول الثمانية فقط من public إلى clinic. لا شيء آخر.
--    services, clinic_hours, appointments, medical_records, notifications,
--    case_studies, reviews, appointment_reminders
--
--  خارج النطاق عمداً (Explicitly out of scope):
--    - لا تعديل على أي دالة (مراجع "public.<جدول منقول>" داخل أجسام الدوال
--      تبقى كما هي حرفياً في هذا الملف — ستُصحَّح في Migration 0011 منفصلة).
--    - لا تعديل على أي RLS Policy، Trigger، أو Foreign Key: كل هذه العناصر
--      مرتبطة بالجدول عبر OID داخلي في Postgres، وتنتقل تلقائياً مع الجدول
--      عند ALTER TABLE ... SET SCHEMA، دون أي إجراء SQL إضافي مطلوب.
--    - لا تعديل على أي Realtime Publication (نفس آلية OID تنطبق على
--      supabase_realtime؛ التحقق العملي بعد التنفيذ خارج نطاق هذا الملف).
--    - لا إضافة clinic إلى Exposed Schemas في إعدادات Supabase، ولا أي تعديل
--      على كود الواجهة الأمامية (supabase.schema("clinic") في الاستدعاءات) —
--      هذه خطوات تشغيلية/نشر، تُوثَّق في قائمة نشر (Deployment Checklist)
--      منفصلة تماماً عن ملفات الـ migrations، وليست جزءاً من هذا الـ SQL.
--
--  ⚠️ اعتماد تشغيلي حرج خارج نطاق هذا الملف: حتى لحظة إضافة clinic إلى
--  Exposed Schemas وتحديث الواجهة لاستخدام supabase.schema("clinic")، فإن
--  كل استعلام مباشر (.from(...)) من الواجهة على هذه الجداول الثمانية سيفشل
--  فور تطبيق هذه الـ migration. هذا متوقَّع ومقصود ضمن تسلسل النشر المتفق
--  عليه، وليس خللاً في هذا الملف.
--
--  قابلة لإعادة التشغيل (Idempotent): "alter table if exists ... set schema"
--  — إن كان الجدول قد انتقل بالفعل من تشغيل سابق، فلن يُطابَق الاسم القديم
--  المؤهَّل بـ public، وتُتخطّى العبارة بأمان بلا خطأ.
--
--  ⚠️⚠️ الترتيب التشغيلي (Deployment Order) — Migration 0010 وMigration 0011
--  زوج مترابط (Atomic Deployment Pair)، وليسا خطوتين مستقلتين:
--  فور تطبيق هذه الـ migration، تصبح public.book_appointment(),
--  public.notify_on_appointment_change(), public.notify_on_medical_record(),
--  و public.dispatch_appointment_reminders() تشير داخلياً إلى جداول لم تعد
--  موجودة في public (لأنها انتقلت إلى clinic هنا) — أي استدعاء فعلي لأي
--  منها خلال الفترة الفاصلة سيفشل بخطأ "relation does not exist". هذا يعني:
--    - يجب تطبيق 0010 و0011 ضمن **نفس نافذة النشر**، دون استخدام حقيقي
--      للنظام (حجوزات، إشعارات، تذكيرات) بينهما.
--    - لا يجوز تطبيق 0010 والانتظار (ساعات أو أيام) قبل تطبيق 0011 — أي
--      حجز أو تحديث سجل طبي أو تشغيل دورة تذكيرات خلال تلك الفترة سيفشل.
--    - هذا الاعتماد لا يمكن حله من داخل ملف SQL بحد ذاته؛ هو قيد على عملية
--      النشر نفسها (Deployment Process)، ويجب توثيقه في أي قائمة نشر تُرافق
--      هذين الملفين تحديداً.
-- =============================================================================

alter table if exists public.services             set schema clinic;
alter table if exists public.clinic_hours          set schema clinic;
alter table if exists public.appointments          set schema clinic;
alter table if exists public.medical_records       set schema clinic;
alter table if exists public.notifications         set schema clinic;
alter table if exists public.case_studies          set schema clinic;
alter table if exists public.reviews               set schema clinic;
alter table if exists public.appointment_reminders set schema clinic;
