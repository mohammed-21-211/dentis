-- =============================================================================
--  Migration 0009 — تحديث سياسات RLS لجداول العيادة لتعتمد على organization_id
--  Dental Clinic Migration 0009 — organization-scoped RLS for clinic tables only
--
--  النطاق (Scope):
--    استبدال public.is_doctor() في سياسات RLS الخاصة بجداول العيادة السبعة
--    فقط، بـ public.is_org_member(organization_id) — دالة Backbone موجودة
--    مسبقاً (لم تُنشأ في هذا الملف ولا في أي migration سابقة).
--
--    9 سياسات فقط تتغيّر (كانت تعتمد على is_doctor()):
--      services_doctor_write, clinic_hours_doctor_write,
--      appointments_select_own_or_doctor, appointments_update_own_or_doctor,
--      medical_records_select_own_or_doctor, medical_records_doctor_write,
--      case_studies_doctor_write, reviews_select_approved_or_doctor,
--      reviews_doctor_write
--
--  خارج النطاق عمداً (Explicitly out of scope):
--    - 7 سياسات لا تعتمد على is_doctor() أصلاً تبقى بلا أي لمس:
--      services_select_all, clinic_hours_select_all, appointments_patient_insert,
--      notifications_select_own, notifications_update_own,
--      case_studies_select_all, reviews_insert_public.
--    - سياستا profiles (profiles_select_self_or_doctor, profiles_update_self):
--      public.profiles جدول Backbone مشترك، لسنا الجهة المخوَّلة بتعديل RLS
--      عليه، ولا نعرف حالته الفعلية الحية. غير مذكورتين في هذا الملف إطلاقاً.
--    - سياسات Storage (x-rays, case-media): مؤجَّلة بالكامل حتى يُحسم تصميم
--      مسارات الملفات (organization_id غير موجود حالياً في بنية المسار).
--    - لا تعديل على public.is_doctor() — لا حذف ولا تغيير تعريف. تتوقف
--      سياسات العيادة عن استدعائها فقط؛ تُترك يتيمة، وقرار حذفها/إصلاحها
--      مسؤولية الـ Backbone في مرحلة لاحقة منفصلة تماماً عن migrations العيادة.
--    - لا إنشاء دالة مساعدة جديدة (مثل clinic.can_view_patient_row) — الشروط
--      مكتوبة حرفياً داخل كل سياسة كما طُلب، رغم التكرار البسيط بينها.
--    - لا نقل أي جدول إلى schema clinic (يأتي في Migration 0010 منفصلة).
--
--  ⚠️ اعتماد صريح على توقيع public.is_org_member(p_organization_id uuid):
--  هذه الدالة موجودة بالفعل في الـ Backbone ولم تُنشأ هنا. الافتراض المعتمد
--  هو أنها تأخذ معاملاً واحداً من نوع uuid وتُعيد boolean. الفحص أدناه (قبل
--  أي DROP/CREATE POLICY) يتحقق من وجودها بهذا التوقيع بالضبط عبر pg_proc،
--  ويوقف التنفيذ بخطأ واضح إن اختلف التوقيع الفعلي — بدل إنشاء سياسات
--  ستفشل لاحقاً برسالة غامضة عند أول استعلام فعلي عليها.
--
--  قابلة لإعادة التشغيل (Idempotent): كل سياسة تُسقَط (drop policy if exists)
--  ثم تُنشأ من جديد — نفس نمط 0001_initial_schema.sql الأصلي تماماً.
--
--  ⚠️ طبيعة هذه الـ migration: تغيير طبقة التفويض (Authorization) فقط.
--  هذا الملف لا يغيّر منطق الأعمال (Business Logic)، ولا يغيّر أي بيانات،
--  ولا يعدّل بنية أي جدول (لا أعمدة جديدة، لا فهارس، لا قيود)، ولا ينقل أي
--  جدول إلى schema أخرى. التغيير الوحيد هو آلية التحقق من "من يحق له الوصول
--  لهذا الصف؟" — من مفهوم "طبيب عالمي واحد" (is_doctor(): هل role=doctor في
--  كامل النظام) إلى مفهوم "عضوية في منظمة محدَّدة" (is_org_member(organization_id):
--  هل المستخدم عضو في نفس عيادة هذا الصف تحديداً). كل شرط آخر داخل كل سياسة
--  (ملكية المريض عبر patient_id = auth.uid()، حالة الموافقة is_approved، إلخ)
--  بقي كما هو دون أي تعديل.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- فحص مسبق: التأكد من وجود public.is_org_member(uuid) بالتوقيع المتوقَّع
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'is_org_member'
      and p.pronargs = 1
      and p.proargtypes[0] = 'uuid'::regtype
  ) then
    raise exception
      'public.is_org_member(uuid) غير موجودة بهذا التوقيع — توقّف عن تطبيق Migration 0009 وراجع التوقيع الفعلي قبل المتابعة';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- services
-- ---------------------------------------------------------------------------
drop policy if exists "services_doctor_write" on public.services;
create policy "services_doctor_write" on public.services
  for all
  using (public.is_org_member(organization_id))
  with check (public.is_org_member(organization_id));

-- ---------------------------------------------------------------------------
-- clinic_hours
-- ---------------------------------------------------------------------------
drop policy if exists "clinic_hours_doctor_write" on public.clinic_hours;
create policy "clinic_hours_doctor_write" on public.clinic_hours
  for all
  using (public.is_org_member(organization_id))
  with check (public.is_org_member(organization_id));

-- ---------------------------------------------------------------------------
-- appointments
-- ---------------------------------------------------------------------------
drop policy if exists "appointments_select_own_or_doctor" on public.appointments;
create policy "appointments_select_own_or_doctor" on public.appointments
  for select
  using (patient_id = auth.uid() or public.is_org_member(organization_id));

drop policy if exists "appointments_update_own_or_doctor" on public.appointments;
create policy "appointments_update_own_or_doctor" on public.appointments
  for update
  using (patient_id = auth.uid() or public.is_org_member(organization_id))
  with check (patient_id = auth.uid() or public.is_org_member(organization_id));

-- ---------------------------------------------------------------------------
-- medical_records
-- ---------------------------------------------------------------------------
drop policy if exists "medical_records_select_own_or_doctor" on public.medical_records;
create policy "medical_records_select_own_or_doctor" on public.medical_records
  for select
  using (patient_id = auth.uid() or public.is_org_member(organization_id));

drop policy if exists "medical_records_doctor_write" on public.medical_records;
create policy "medical_records_doctor_write" on public.medical_records
  for all
  using (public.is_org_member(organization_id))
  with check (public.is_org_member(organization_id));

-- ---------------------------------------------------------------------------
-- case_studies
-- ---------------------------------------------------------------------------
drop policy if exists "case_studies_doctor_write" on public.case_studies;
create policy "case_studies_doctor_write" on public.case_studies
  for all
  using (public.is_org_member(organization_id))
  with check (public.is_org_member(organization_id));

-- ---------------------------------------------------------------------------
-- reviews
-- ---------------------------------------------------------------------------
drop policy if exists "reviews_select_approved_or_doctor" on public.reviews;
create policy "reviews_select_approved_or_doctor" on public.reviews
  for select
  using (is_approved = true or public.is_org_member(organization_id));

drop policy if exists "reviews_doctor_write" on public.reviews;
create policy "reviews_doctor_write" on public.reviews
  for all
  using (public.is_org_member(organization_id))
  with check (public.is_org_member(organization_id));
