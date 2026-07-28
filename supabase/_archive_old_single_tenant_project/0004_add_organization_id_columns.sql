-- =============================================================================
--  Migration 0004 — إضافة عمود organization_id (Nullable) + الـ Foreign Keys
--  Dental Clinic Migration 0004 — add organization_id column + FKs only
--
--  النطاق (Scope):
--    إضافة عمود organization_id (nullable مؤقتاً) يشير إلى public.organizations(id)
--    على الجداول السبعة المتفق عليها، والتي لا تزال في public (لم تُنقل بعد):
--      services, clinic_hours, appointments, medical_records,
--      notifications, case_studies, reviews
--
--  خارج النطاق عمداً (Explicitly out of scope):
--    - لا Backfill لأي بيانات.
--    - لا "not null" على العمود الجديد.
--    - لا فهارس جديدة.
--    - لا تعديل على أي قيد UNIQUE قائم.
--    - لا تعديل على أي دالة/Trigger/RLS.
--    - لا نقل أي جدول إلى schema clinic.
--
--  ملاحظة: public.appointment_reminders لا تحتاج عمود organization_id خاصاً
--  بها — تُستنتج عيادتها ضمنياً عبر appointment_id → appointments.organization_id.
--
--  تسمية القيود (Foreign Key naming):
--  كل مفتاح أجنبي مُسمّى صراحةً بالنمط <table>_organization_id_fkey بدل
--  الاعتماد على التسمية التلقائية، لضمان استقرار الاسم بغض النظر عن نسخة
--  Postgres أو ترتيب العمليات، ولتسهيل أي DROP/ALTER مستقبلي عليه بالاسم.
--
--  قرار ON DELETE (صريح لكل قيد): RESTRICT.
--  السبب: organizations هو جدول الـ Backbone المشترك، وحذف صف منظمة عملية
--  إدارية نادرة تقع خارج تطبيق العيادة تماماً. اختيار RESTRICT يمنع حذف أي
--  منظمة طالما لا تزال هناك بيانات عيادة مرتبطة بها (بما في ذلك سجلات طبية
--  حساسة في medical_records)، ويجبر أي تنظيف فعلي لبيانات المنظمة على أن
--  يكون إجراءً صريحاً ومتعمّداً (migration/عملية إدارية منفصلة) بدل حذف
--  ضمني تلقائي (CASCADE) قد يفقد بيانات حساسة دون قصد. هذا القرار قابل
--  للمراجعة لاحقاً لكل جدول على حدة إن احتاج الفريق سلوكاً مختلفاً.
--
--  قابلة لإعادة التشغيل (Idempotent): "add column if not exists" — عند تشغيل
--  ثانٍ لن يُعاد إضافة العمود ولا محاولة إعادة إنشاء القيد المرفق به.
-- =============================================================================

alter table public.services
  add column if not exists organization_id uuid
    constraint services_organization_id_fkey
    references public.organizations (id)
    on delete restrict;

comment on column public.services.organization_id is
  'المنظمة (العيادة) المالكة لهذه الخدمة. Nullable مؤقتاً — سيُفرض NOT NULL في Migration لاحقة بعد اكتمال الـ Backfill.';

alter table public.clinic_hours
  add column if not exists organization_id uuid
    constraint clinic_hours_organization_id_fkey
    references public.organizations (id)
    on delete restrict;

comment on column public.clinic_hours.organization_id is
  'المنظمة (العيادة) المالكة لساعات العمل هذه. Nullable مؤقتاً — سيُفرض NOT NULL لاحقاً.';

alter table public.appointments
  add column if not exists organization_id uuid
    constraint appointments_organization_id_fkey
    references public.organizations (id)
    on delete restrict;

comment on column public.appointments.organization_id is
  'المنظمة (العيادة) المالكة لهذا الموعد. Nullable مؤقتاً — سيُفرض NOT NULL لاحقاً.';

alter table public.medical_records
  add column if not exists organization_id uuid
    constraint medical_records_organization_id_fkey
    references public.organizations (id)
    on delete restrict;

comment on column public.medical_records.organization_id is
  'المنظمة (العيادة) المالكة لهذا السجل الطبي. Nullable مؤقتاً — سيُفرض NOT NULL لاحقاً.';

alter table public.notifications
  add column if not exists organization_id uuid
    constraint notifications_organization_id_fkey
    references public.organizations (id)
    on delete restrict;

comment on column public.notifications.organization_id is
  'المنظمة (العيادة) المصدر لهذا الإشعار. يتعايش مع عمود user_id القائم (لا يستبدله). Nullable مؤقتاً — سيُفرض NOT NULL لاحقاً.';

alter table public.case_studies
  add column if not exists organization_id uuid
    constraint case_studies_organization_id_fkey
    references public.organizations (id)
    on delete restrict;

comment on column public.case_studies.organization_id is
  'المنظمة (العيادة) المالكة لهذه الحالة. Nullable مؤقتاً — سيُفرض NOT NULL لاحقاً.';

alter table public.reviews
  add column if not exists organization_id uuid
    constraint reviews_organization_id_fkey
    references public.organizations (id)
    on delete restrict;

comment on column public.reviews.organization_id is
  'المنظمة (العيادة) المالكة لهذا التقييم. Nullable مؤقتاً — سيُفرض NOT NULL لاحقاً.';
