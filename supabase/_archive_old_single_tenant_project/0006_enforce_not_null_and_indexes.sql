-- =============================================================================
--  Migration 0006 — فرض NOT NULL على organization_id + فهارس مركّبة جديدة
--  Dental Clinic Migration 0006 — enforce NOT NULL + new composite indexes
--
--  النطاق (Scope):
--    1) alter column organization_id set not null على الجداول السبعة.
--    2) إضافة فهارس جديدة تبدأ بـ organization_id (leftmost column) لتسريع
--       أنماط الاستعلام الفعلية في الكود بعد إضافة تصفية العيادة.
--
--  ⚠️ اعتماد صريح على Migration 0005 (لا يوجد تحقق برمجي داخل هذا الملف):
--  خطوة "set not null" أدناه لا تحتوي أي فحص مسبق يتأكد من خلوّ الجداول من
--  قيم NULL — هي تعتمد كلياً على أن 0005_backfill_organization_id.sql نُفِّذت
--  بنجاح قبلها ضمن نفس التسلسل، وأزالت كل الصفوف اليتيمة (organization_id
--  is null). إن فشلت هذه الخطوة بخطأ من النوع:
--    'column "organization_id" of relation "..." contains null values'
--  فهذا يعني تحديداً أن Migration 0005 إما لم تُطبَّق أصلاً على هذه القاعدة
--  قبل 0006، أو أن صفوفاً جديدة بـ organization_id = NULL أُدرجت بعد 0005
--  وقبل 0006 (مثلاً عبر seed/استيراد يدوي بين الخطوتين). الحل في الحالتين:
--  التأكد من تطبيق 0005 أولاً، ثم إعادة فحص الجداول يدوياً عن أي صف NULL
--  متبقٍ قبل إعادة محاولة تشغيل 0006 — وليس تعديل هذا الملف لتجاوز الخطأ.
--
--  خارج النطاق عمداً (Explicitly out of scope):
--    - لا تعديل على أي قيد UNIQUE قائم (appointments_unique_active_slot،
--      clinic_hours.day_of_week) — يأتي في Migration 0007 منفصلة عمداً.
--    - لا تعديل على أي دالة/Trigger/RLS.
--    - لا نقل أي جدول إلى schema clinic.
--
--  فهارس مقصود عدم إضافتها الآن (لتجنّب التكرار مستقبلاً):
--    - clinic_hours(organization_id): ستُغطّى بالكامل عبر البادئة اليسرى
--      لقيد UNIQUE الجديد (organization_id, day_of_week) في 0007.
--    - appointments(organization_id, appointment_date): ستُغطّى بالكامل عبر
--      البادئة اليسرى لقيد UNIQUE الجديد (organization_id, appointment_date,
--      start_time) في 0007. إضافة فهرس منفصل الآن سيصبح تكراراً زائداً بعد 0007.
--    (ملاحظة: بين تطبيق 0006 و0007 توجد فجوة زمنية قصيرة يفتقر خلالها هذا
--    النمط من الاستعلام لفهرس مخصص — مقبولة لأن الجداول لا تزال فارغة عملياً
--    في هذه المرحلة من التسلسل، في أي بيئة).
--
--  قابلة لإعادة التشغيل (Idempotent):
--    - "set not null" لا يفشل إن كان العمود NOT NULL بالفعل من تشغيل سابق.
--    - "create index if not exists" لا تُعيد إنشاء فهرس موجود.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) فرض NOT NULL
-- ---------------------------------------------------------------------------
alter table public.services         alter column organization_id set not null;
alter table public.clinic_hours     alter column organization_id set not null;
alter table public.appointments     alter column organization_id set not null;
alter table public.medical_records  alter column organization_id set not null;
alter table public.notifications    alter column organization_id set not null;
alter table public.case_studies     alter column organization_id set not null;
alter table public.reviews          alter column organization_id set not null;

-- ---------------------------------------------------------------------------
-- 2) فهارس مركّبة جديدة (organization_id كعمود أول)
-- ---------------------------------------------------------------------------

-- appointments: تسريع "مواعيد مريض معيّن ضمن عيادة معيّنة"
-- (PatientDashboard.tsx, PatientDetail.tsx بعد إضافة تصفية العيادة)
create index if not exists appointments_organization_id_patient_id_idx
  on public.appointments (organization_id, patient_id);

-- medical_records: تسريع "سجلات مريض معيّن ضمن عيادة معيّنة"
create index if not exists medical_records_organization_id_patient_id_idx
  on public.medical_records (organization_id, patient_id);

-- notifications: تسريع الاستعلام الأكثر تكراراً (useNotifications.ts) —
-- إشعارات مستخدم معيّن ضمن عيادة معيّنة، مرتبة بحالة القراءة
create index if not exists notifications_organization_id_user_id_is_read_idx
  on public.notifications (organization_id, user_id, is_read);

-- services: تسريع "خدمات عيادة معيّنة" (BookingForm.tsx, ClinicTab)
create index if not exists services_organization_id_idx
  on public.services (organization_id);

-- case_studies: تسريع "معرض حالات عيادة معيّنة" (Landing.tsx, CaseStudiesManager.tsx)
create index if not exists case_studies_organization_id_idx
  on public.case_studies (organization_id);

-- reviews: تسريع "تقييمات عيادة معيّنة" (Landing.tsx, ReviewsManager.tsx)
create index if not exists reviews_organization_id_idx
  on public.reviews (organization_id);
