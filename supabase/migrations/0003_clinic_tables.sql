-- =============================================================================
--  Migration 0003 — جداول العيادة كاملة داخل schema clinic (تثبيت مباشر)
--  Dental Clinic Migration 0003 — clinic domain tables, created directly with
--  organization_id from day one (no staged nullable→backfill→not null dance,
--  because there is no pre-existing data to protect).
--
--  النطاق (Scope): 8 جداول دومين العيادة + enum واحد فقط (appointment_status).
--  كل جدول يحمل organization_id uuid not null → public.organizations(id)
--  منذ السطر الأول. كل قيد فريد وفهرس مُصمَّم org-scoped من البداية (لا
--  "تصحيح لاحق" لقيد كان عالمياً بالخطأ كما حدث في المشروع القديم).
--
--  ما لا يُنشأ هنا عمداً (Explicitly not created):
--    - public.profiles: موجود بالفعل (Backbone)، لا نلمسه.
--    - user_role enum: لم يعد له داعٍ — دور "طبيب" يُشتق من عضوية
--      public.organization_members، وليس عموداً مخزَّناً.
--    - is_doctor(), handle_new_user(): لا علاقة لهما بهذا التصميم إطلاقاً.
--
--  الفهارس المتعمَّد عدم إنشائها لتفادي التكرار (نفس منطق المشروع السابق):
--    - clinic_hours(organization_id) وحدها: مغطّاة بالبادئة اليسرى لقيد
--      UNIQUE (organization_id, day_of_week) أدناه.
--    - appointments(organization_id, appointment_date) وحدها: مغطّاة بالبادئة
--      اليسرى للفهرس الفريد الجزئي (organization_id, appointment_date, start_time).
--
--  قابلة لإعادة التشغيل (Idempotent): create extension/type/table/index كلها
--  "if not exists"، والقيود المُسمّاة صراحة عبر ADD CONSTRAINT داخل CREATE TABLE
--  (تُنشأ مرة واحدة فقط ضمن نفس عبارة إنشاء الجدول).
-- =============================================================================

create extension if not exists "pgcrypto"; -- gen_random_uuid()

do $$ begin
  create type public.appointment_status as enum ('pending', 'confirmed', 'cancelled');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- services
-- ---------------------------------------------------------------------------
create table if not exists clinic.services (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete restrict,
  name            text not null check (char_length(name) between 2 and 120),
  description     text,
  duration        integer not null default 30 check (duration between 5 and 480), -- بالدقائق
  price           numeric(10, 2) not null default 0 check (price >= 0),
  is_active       boolean not null default true,
  created_at      timestamptz not null default now()
);

create index if not exists services_organization_id_idx on clinic.services (organization_id);

comment on table clinic.services is 'خدمات العيادة (أسباب الحجز) لكل منظمة — تُسحب ديناميكياً في نموذج الحجز';

-- ---------------------------------------------------------------------------
-- clinic_hours
--   day_of_week: 0=الأحد ... 6=السبت (متوافق مع JS getDay)
-- ---------------------------------------------------------------------------
create table if not exists clinic.clinic_hours (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete restrict,
  day_of_week     smallint not null check (day_of_week between 0 and 6),
  start_time      time not null default '09:00',
  end_time        time not null default '17:00',
  is_closed       boolean not null default false,
  created_at      timestamptz not null default now(),
  constraint clinic_hours_valid_range check (is_closed or end_time > start_time),
  constraint clinic_hours_organization_id_day_of_week_key unique (organization_id, day_of_week)
);

comment on table clinic.clinic_hours is 'ساعات عمل كل عيادة لكل يوم من أيام الأسبوع';

-- ---------------------------------------------------------------------------
-- appointments
--   منع الحجز المزدوج داخل نفس العيادة: فهرس فريد جزئي على
--   (organization_id, appointment_date, start_time) لكل المواعيد غير الملغاة.
-- ---------------------------------------------------------------------------
create table if not exists clinic.appointments (
  id                  uuid primary key default gen_random_uuid(),
  organization_id     uuid not null references public.organizations (id) on delete restrict,
  patient_id          uuid not null references public.profiles (id) on delete cascade,
  service_id          uuid not null references clinic.services (id) on delete restrict,
  appointment_date    date not null,
  start_time          time not null,
  status              public.appointment_status not null default 'pending',
  cancellation_reason text,
  created_at          timestamptz not null default now(),
  constraint appointments_not_in_past check (appointment_date >= current_date),
  constraint appointments_cancel_reason check (
    status <> 'cancelled' or (cancellation_reason is not null and char_length(trim(cancellation_reason)) >= 3)
  )
);

create unique index if not exists appointments_unique_active_slot
  on clinic.appointments (organization_id, appointment_date, start_time)
  where status <> 'cancelled';

create index if not exists appointments_organization_id_patient_id_idx
  on clinic.appointments (organization_id, patient_id);

comment on table clinic.appointments is 'مواعيد المرضى مع ضمان عدم تكرار الفترة الزمنية داخل نفس العيادة';

-- ---------------------------------------------------------------------------
-- medical_records
-- ---------------------------------------------------------------------------
create table if not exists clinic.medical_records (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete restrict,
  patient_id      uuid not null references public.profiles (id) on delete cascade,
  doctor_notes    text,
  treatment_plan  text,
  x_ray_url       text,
  created_at      timestamptz not null default now()
);

create index if not exists medical_records_organization_id_patient_id_idx
  on clinic.medical_records (organization_id, patient_id);

comment on table clinic.medical_records is 'السجلات الطبية وصور الأشعة لكل عيادة — يكتبها الكادر ويطّلع عليها المريض فقط';

-- ---------------------------------------------------------------------------
-- notifications
-- ---------------------------------------------------------------------------
create table if not exists clinic.notifications (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete restrict,
  user_id         uuid not null references public.profiles (id) on delete cascade,
  title           text not null,
  message         text not null,
  is_read         boolean not null default false,
  created_at      timestamptz not null default now()
);

create index if not exists notifications_organization_id_user_id_is_read_idx
  on clinic.notifications (organization_id, user_id, is_read);

comment on table clinic.notifications is 'الإشعارات الفورية والتذكيرات لكل مستخدم ضمن كل عيادة';

-- ---------------------------------------------------------------------------
-- case_studies
-- ---------------------------------------------------------------------------
create table if not exists clinic.case_studies (
  id                uuid primary key default gen_random_uuid(),
  organization_id   uuid not null references public.organizations (id) on delete restrict,
  title             text not null,
  before_image_url  text,
  after_image_url   text,
  description       text,
  created_at        timestamptz not null default now()
);

create index if not exists case_studies_organization_id_idx on clinic.case_studies (organization_id);

comment on table clinic.case_studies is 'معرض الحالات قبل/بعد لكل عيادة، يُعرض في صفحتها الهبوطية';

-- ---------------------------------------------------------------------------
-- reviews
-- ---------------------------------------------------------------------------
create table if not exists clinic.reviews (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete restrict,
  patient_name    text not null,
  rating          smallint not null check (rating between 1 and 5),
  comment         text,
  is_approved     boolean not null default false,
  created_at      timestamptz not null default now()
);

create index if not exists reviews_organization_id_idx on clinic.reviews (organization_id);

comment on table clinic.reviews is 'تقييمات مرضى كل عيادة — تُعرض المعتمدة فقط في صفحتها الهبوطية';

-- ---------------------------------------------------------------------------
-- appointment_reminders — جدول تتبّع التذكيرات المُرسلة (idempotency)
--   لا عمود organization_id خاص بها: تُشتق ضمنياً عبر appointment_id.
-- ---------------------------------------------------------------------------
create table if not exists clinic.appointment_reminders (
  appointment_id uuid not null references clinic.appointments (id) on delete cascade,
  kind           text not null check (kind in ('24h', '1h')),
  sent_at        timestamptz not null default now(),
  primary key (appointment_id, kind)
);

comment on table clinic.appointment_reminders is 'تتبّع تذكيرات المواعيد المُرسلة لمنع التكرار — لا سياسات مستخدمين، وصول عبر دوال SECURITY DEFINER فقط';
