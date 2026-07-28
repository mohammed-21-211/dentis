-- =============================================================================
--  Migration 0003 — إنشاء schema العيادة + الدوال المشتركة في الـ Backbone
--  Dental Clinic Migration 0003 — clinic schema + shared backbone functions
--
--  النطاق (Scope):
--    1) إنشاء schema "clinic" فارغة (بلا أي جدول بعد).
--    2) إنشاء دالة مشتركة جديدة واحدة فقط في public تُستخدم من كل التطبيقات
--       المستقبلية (وليس فقط تطبيق العيادة): current_organization_id().
--    3) منح صلاحيات الاستخدام (USAGE) على schema clinic.
--
--  خارج النطاق عمداً (Explicitly out of scope):
--    - لا إنشاء أي جدول.
--    - لا نقل أي جدول من public إلى clinic.
--    - لا تعديل على أي RLS قائمة.
--    - لا تعديل على أي Trigger أو Function موجودة مسبقاً (is_doctor, handle_new_user, ...).
--    - لا إنشاء دالة فحص عضوية جديدة: public.is_org_member() موجودة بالفعل
--      في الـ Backbone وتفي بالغرض (عضوية عامة بلا تصفية على نوع الدور).
--      migrations العيادة اللاحقة (RLS في 0010) ستستدعي هذه الدالة القائمة
--      مباشرة (public.is_org_member(organization_id)) بدل إنشاء أي مكافئ لها.
--
--  هذه الـ migration مُصمَّمة لتكون قابلة لإعادة التشغيل (Idempotent) بالكامل:
--  create schema if not exists / create or replace function / grant تُعاد
--  بأمان دون خطأ عند تنفيذها أكثر من مرة.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) Schema العيادة (clinic)
-- ---------------------------------------------------------------------------
create schema if not exists clinic;

comment on schema clinic is
  'جداول تطبيق عيادة الأسنان (Dental Clinic) فقط — منفصلة عن public/auth الخاصة بالـ Backbone المشترك بين كل التطبيقات.';

-- صلاحية الوصول إلى الـ schema نفسها (بدون هذه، حتى لو مُنحت صلاحيات على
-- جدول داخلها لاحقاً، ستفشل الاستعلامات بخطأ "permission denied for schema").
-- لا توجد جداول بعد؛ هذا فقط يفتح الطريق أمام schema 0005 لاحقاً.
grant usage on schema clinic to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2) الدوال المشتركة في public (Backbone-shared، ليست خاصة بالعيادة)
-- ---------------------------------------------------------------------------

-- current_organization_id(): تُعيد المنظمة النشطة للمستخدم الحالي.
-- مصدر الحقيقة: قاعدة البيانات فقط (public.organization_members) — لا JWT
-- claims ولا أي حالة جلسة.
--
-- ⚠️ لا يوجد تأكيد بأن organization_members يفرض قيداً فريداً (unique
-- constraint) يمنع أكثر من صف لنفس user_id. الـ LIMIT 1 هنا يعتمد فقط على
-- افتراض عملي حالي بأن كل مستخدم ينتمي لمنظمة نشطة واحدة، وليس على ضمان
-- من قاعدة البيانات. إن وُجد أكثر من صف فعلياً لنفس user_id، فالنتيجة
-- المُعادة غير محددة (arbitrary) وليست بالضرورة "الصحيحة". يُنصح بالتحقق
-- من وجود هذا القيد على organization_members(user_id) على مستوى الـ
-- Backbone، وإضافته إن لم يكن موجوداً لضمان اتساق هذا الافتراض.
--
-- ملاحظة للتطوير المستقبلي (تعدد المنظمات لكل مستخدم):
-- عند إضافة هذا الدعم، التعديل يقع داخل جسم هذه الدالة فقط (مثلاً إضافة
-- شرط على عمود "افتراضي/نشط" إن أُضيف مستقبلاً إلى organization_members)،
-- دون كسر توقيعها (returns uuid, بلا معاملات) أو أي استدعاء قائم لها.
create or replace function public.current_organization_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select m.organization_id
  from public.organization_members m
  where m.user_id = auth.uid()
  limit 1
$$;

comment on function public.current_organization_id() is
  'تُعيد organization_id الخاص بالمستخدم الحالي (auth.uid()) اعتماداً على public.organization_members. مشتركة بين كل التطبيقات، وليست خاصة بالعيادة.';

revoke all on function public.current_organization_id() from public;
grant execute on function public.current_organization_id() to authenticated, service_role;

-- ملاحظة: فحص "هل المستخدم عضو في منظمة معيّنة" ليس مطلوباً هنا — يُستخدم
-- public.is_org_member(organization_id) الموجودة بالفعل في الـ Backbone بدل
-- إنشاء دالة جديدة مكافئة (تجنّباً لمضاعفة الدوال عبر التطبيقات المتعددة).
-- سياسات RLS في Migration 0010 ستستدعيها مباشرة.
