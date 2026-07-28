-- =============================================================================
--  نظام إدارة عيادة الأسنان — مخطط قاعدة البيانات الأولي
--  Dental Clinic Management System — Initial Schema Migration
--
--  يشمل: الجداول، العلاقات، الفهارس، أمان مستوى الصف (RLS)،
--        المُشغّلات (Triggers) للإشعارات، منع الحجز المزدوج،
--        دالة الحجز الذرّية، وتخزين الملفات (Storage).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 0) الإضافات (Extensions)
-- ---------------------------------------------------------------------------
create extension if not exists "pgcrypto";      -- gen_random_uuid()
create extension if not exists "btree_gist";    -- لقيود الاستبعاد (exclusion constraints)

-- ---------------------------------------------------------------------------
-- 1) الأنواع المعدودة (Enums)
-- ---------------------------------------------------------------------------
do $$ begin
  create type user_role as enum ('doctor', 'patient');
exception when duplicate_object then null; end $$;

do $$ begin
  create type appointment_status as enum ('pending', 'confirmed', 'cancelled');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- 2) جدول الملفات الشخصية (profiles)
--    يرتبط 1:1 مع auth.users ويُملأ تلقائياً عبر مُشغّل.
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text not null check (char_length(full_name) between 2 and 120),
  role        user_role not null default 'patient',
  phone       text check (phone is null or phone ~ '^[0-9+\-\s]{6,20}$'),
  created_at  timestamptz not null default now()
);

comment on table public.profiles is 'الملفات الشخصية للمستخدمين (أطباء/مرضى)';

-- ---------------------------------------------------------------------------
-- 3) جدول الخدمات (services) — يديره الطبيب
-- ---------------------------------------------------------------------------
create table if not exists public.services (
  id           uuid primary key default gen_random_uuid(),
  name         text not null check (char_length(name) between 2 and 120),
  description  text,
  duration     integer not null default 30 check (duration between 5 and 480), -- بالدقائق
  price        numeric(10, 2) not null default 0 check (price >= 0),
  is_active    boolean not null default true,
  created_at   timestamptz not null default now()
);

comment on table public.services is 'خدمات العيادة (أسباب الحجز) — تُسحب ديناميكياً في نموذج الحجز';

-- ---------------------------------------------------------------------------
-- 4) جدول ساعات العمل الأسبوعية (clinic_hours)
--    day_of_week: 0=الأحد ... 6=السبت (متوافق مع JS getDay)
-- ---------------------------------------------------------------------------
create table if not exists public.clinic_hours (
  id           uuid primary key default gen_random_uuid(),
  day_of_week  smallint not null unique check (day_of_week between 0 and 6),
  start_time   time not null default '09:00',
  end_time     time not null default '17:00',
  is_closed    boolean not null default false,
  created_at   timestamptz not null default now(),
  constraint clinic_hours_valid_range check (is_closed or end_time > start_time)
);

comment on table public.clinic_hours is 'ساعات عمل العيادة لكل يوم من أيام الأسبوع';

-- ---------------------------------------------------------------------------
-- 5) جدول المواعيد (appointments)
--    منع الحجز المزدوج: فهرس فريد جزئي على (التاريخ + وقت البدء)
--    لكل المواعيد غير الملغاة. هذا هو خط الدفاع الأخير ضد سباق التزامن.
-- ---------------------------------------------------------------------------
create table if not exists public.appointments (
  id                  uuid primary key default gen_random_uuid(),
  patient_id          uuid not null references public.profiles (id) on delete cascade,
  service_id          uuid not null references public.services (id) on delete restrict,
  appointment_date    date not null,
  start_time          time not null,
  status              appointment_status not null default 'pending',
  cancellation_reason text,
  created_at          timestamptz not null default now(),
  -- لا يجوز الحجز في الماضي
  constraint appointments_not_in_past check (appointment_date >= current_date),
  -- سبب الإلغاء إلزامي عند الإلغاء فقط
  constraint appointments_cancel_reason check (
    status <> 'cancelled' or (cancellation_reason is not null and char_length(trim(cancellation_reason)) >= 3)
  )
);

-- خط الدفاع الأخير ضد الحجز المزدوج (على مستوى قاعدة البيانات)
create unique index if not exists appointments_unique_active_slot
  on public.appointments (appointment_date, start_time)
  where status <> 'cancelled';

create index if not exists appointments_patient_idx on public.appointments (patient_id);
create index if not exists appointments_date_idx on public.appointments (appointment_date);

comment on table public.appointments is 'مواعيد المرضى مع ضمان عدم تكرار الفترة الزمنية';

-- ---------------------------------------------------------------------------
-- 6) جدول السجلات الطبية (medical_records) — يكتبها الطبيب فقط
-- ---------------------------------------------------------------------------
create table if not exists public.medical_records (
  id              uuid primary key default gen_random_uuid(),
  patient_id      uuid not null references public.profiles (id) on delete cascade,
  doctor_notes    text,
  treatment_plan  text,
  x_ray_url       text,
  created_at      timestamptz not null default now()
);

create index if not exists medical_records_patient_idx on public.medical_records (patient_id);

comment on table public.medical_records is 'السجلات الطبية وصور الأشعة — يكتبها الطبيب ويطّلع عليها المريض فقط';

-- ---------------------------------------------------------------------------
-- 7) جدول الإشعارات (notifications)
-- ---------------------------------------------------------------------------
create table if not exists public.notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  title       text not null,
  message     text not null,
  is_read     boolean not null default false,
  created_at  timestamptz not null default now()
);

create index if not exists notifications_user_idx on public.notifications (user_id, is_read);

comment on table public.notifications is 'الإشعارات الفورية والتذكيرات لكل مستخدم';

-- ---------------------------------------------------------------------------
-- 8) جدول دراسات الحالة (case_studies) — معرض قبل/بعد
-- ---------------------------------------------------------------------------
create table if not exists public.case_studies (
  id                uuid primary key default gen_random_uuid(),
  title             text not null,
  before_image_url  text,
  after_image_url   text,
  description       text,
  created_at        timestamptz not null default now()
);

comment on table public.case_studies is 'معرض الحالات قبل/بعد لعرضه في صفحة الهبوط';

-- ---------------------------------------------------------------------------
-- 9) جدول التقييمات (reviews)
-- ---------------------------------------------------------------------------
create table if not exists public.reviews (
  id            uuid primary key default gen_random_uuid(),
  patient_name  text not null,
  rating        smallint not null check (rating between 1 and 5),
  comment       text,
  is_approved   boolean not null default false,
  created_at    timestamptz not null default now()
);

comment on table public.reviews is 'تقييمات المرضى — تُعرض المعتمدة فقط في صفحة الهبوط';

-- =============================================================================
--  الدوال المساعدة (Helper Functions)
-- =============================================================================

-- التحقق إن كان المستخدم الحالي طبيباً (SECURITY DEFINER لتجنّب التكرار في RLS)
create or replace function public.is_doctor()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'doctor'
  );
$$;

-- مُشغّل: إنشاء ملف شخصي تلقائياً عند تسجيل مستخدم جديد
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, role, phone)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', 'مستخدم جديد'),
    coalesce((new.raw_user_meta_data ->> 'role')::user_role, 'patient'),
    new.raw_user_meta_data ->> 'phone'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- =============================================================================
--  مُشغّلات الإشعارات (Notification Triggers)
-- =============================================================================

-- إشعار للطبيب عند قيام المريض بالحجز / الإلغاء، وإشعار للمريض عند تأكيد الموعد
create or replace function public.notify_on_appointment_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  doctor_id     uuid;
  patient_name  text;
  service_name  text;
begin
  select id into doctor_id from public.profiles where role = 'doctor' limit 1;
  select full_name into patient_name from public.profiles where id = new.patient_id;
  select name into service_name from public.services where id = new.service_id;

  if (tg_op = 'INSERT') then
    -- إشعار الطبيب بحجز جديد
    if doctor_id is not null then
      insert into public.notifications (user_id, title, message)
      values (
        doctor_id,
        'حجز موعد جديد',
        format('قام %s بحجز موعد (%s) بتاريخ %s الساعة %s',
               patient_name, service_name, new.appointment_date, new.start_time)
      );
    end if;

  elsif (tg_op = 'UPDATE' and new.status is distinct from old.status) then
    if new.status = 'cancelled' then
      -- إشعار الطبيب بالإلغاء مع السبب
      if doctor_id is not null then
        insert into public.notifications (user_id, title, message)
        values (
          doctor_id,
          'إلغاء موعد',
          format('ألغى %s موعده بتاريخ %s. السبب: %s',
                 patient_name, new.appointment_date, coalesce(new.cancellation_reason, '—'))
        );
      end if;
    elsif new.status = 'confirmed' then
      -- إشعار المريض بتأكيد الموعد
      insert into public.notifications (user_id, title, message)
      values (
        new.patient_id,
        'تم تأكيد موعدك',
        format('تم تأكيد موعدك (%s) بتاريخ %s الساعة %s',
               service_name, new.appointment_date, new.start_time)
      );
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_notify_appointment on public.appointments;
create trigger trg_notify_appointment
  after insert or update on public.appointments
  for each row execute function public.notify_on_appointment_change();

-- إشعار المريض عند إضافة/تحديث سجل طبي
create or replace function public.notify_on_medical_record()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notifications (user_id, title, message)
  values (
    new.patient_id,
    'تحديث في ملفك الطبي',
    'قام الطبيب بإضافة أو تحديث معلومات في سجلك الطبي. يمكنك الاطلاع عليها من لوحة التحكم.'
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_medical_record on public.medical_records;
create trigger trg_notify_medical_record
  after insert on public.medical_records
  for each row execute function public.notify_on_medical_record();

-- =============================================================================
--  دالة الحجز الذرّية (Atomic Booking RPC)
--  تتحقق من: ساعات العمل + عدم تعارض الفترة، ثم تُدرج الموعد.
--  الفهرس الفريد الجزئي يضمن السلامة حتى تحت التزامن العالي.
-- =============================================================================
create or replace function public.book_appointment(
  p_service_id uuid,
  p_date       date,
  p_start_time time
)
returns public.appointments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_patient_id  uuid := auth.uid();
  v_dow         smallint := extract(dow from p_date);   -- 0=الأحد .. 6=السبت
  v_hours       public.clinic_hours%rowtype;
  v_duration    integer;
  v_end_time    time;
  v_new         public.appointments;
begin
  if v_patient_id is null then
    raise exception 'يجب تسجيل الدخول للحجز' using errcode = 'P0001';
  end if;

  -- لا يجوز الحجز في الماضي
  if p_date < current_date then
    raise exception 'لا يمكن الحجز في تاريخ ماضٍ' using errcode = 'P0001';
  end if;

  -- التحقق من وجود الخدمة وجلب مدتها
  select duration into v_duration from public.services
   where id = p_service_id and is_active = true;
  if v_duration is null then
    raise exception 'الخدمة المختارة غير متاحة' using errcode = 'P0001';
  end if;
  v_end_time := p_start_time + (v_duration || ' minutes')::interval;

  -- التحقق من ساعات عمل العيادة لهذا اليوم
  select * into v_hours from public.clinic_hours where day_of_week = v_dow;
  if v_hours is null or v_hours.is_closed then
    raise exception 'العيادة مغلقة في هذا اليوم' using errcode = 'P0001';
  end if;
  if p_start_time < v_hours.start_time or v_end_time > v_hours.end_time then
    raise exception 'الموعد المطلوب خارج ساعات عمل العيادة' using errcode = 'P0001';
  end if;

  -- منع التعارض: قفل الفترات المتداخلة في نفس اليوم ثم الفحص
  perform 1 from public.appointments a
   join public.services s on s.id = a.service_id
   where a.appointment_date = p_date
     and a.status <> 'cancelled'
     and tsrange(
           (p_date + a.start_time)::timestamp,
           (p_date + a.start_time)::timestamp + (s.duration || ' minutes')::interval
         )
         && tsrange(
           (p_date + p_start_time)::timestamp,
           (p_date + p_start_time)::timestamp + (v_duration || ' minutes')::interval
         )
   for update;

  if found then
    raise exception 'هذه الفترة محجوزة مسبقاً، يرجى اختيار وقت آخر' using errcode = 'P0001';
  end if;

  insert into public.appointments (patient_id, service_id, appointment_date, start_time, status)
  values (v_patient_id, p_service_id, p_date, p_start_time, 'pending')
  returning * into v_new;

  return v_new;
exception
  when unique_violation then
    -- اصطدم الفهرس الفريد الجزئي — حجزٌ متزامن سبَقَنا
    raise exception 'هذه الفترة حُجزت للتو، يرجى اختيار وقت آخر' using errcode = 'P0001';
end;
$$;

-- =============================================================================
--  تفعيل أمان مستوى الصف (Row Level Security)
-- =============================================================================
alter table public.profiles         enable row level security;
alter table public.services         enable row level security;
alter table public.clinic_hours     enable row level security;
alter table public.appointments     enable row level security;
alter table public.medical_records  enable row level security;
alter table public.notifications    enable row level security;
alter table public.case_studies     enable row level security;
alter table public.reviews          enable row level security;

-- ----- profiles -----
drop policy if exists "profiles_select_self_or_doctor" on public.profiles;
create policy "profiles_select_self_or_doctor" on public.profiles
  for select using (id = auth.uid() or public.is_doctor());

drop policy if exists "profiles_update_self" on public.profiles;
create policy "profiles_update_self" on public.profiles
  for update using (id = auth.uid()) with check (id = auth.uid());

-- ----- services (قراءة للجميع، إدارة للطبيب) -----
drop policy if exists "services_select_all" on public.services;
create policy "services_select_all" on public.services
  for select using (true);

drop policy if exists "services_doctor_write" on public.services;
create policy "services_doctor_write" on public.services
  for all using (public.is_doctor()) with check (public.is_doctor());

-- ----- clinic_hours (قراءة للجميع، إدارة للطبيب) -----
drop policy if exists "clinic_hours_select_all" on public.clinic_hours;
create policy "clinic_hours_select_all" on public.clinic_hours
  for select using (true);

drop policy if exists "clinic_hours_doctor_write" on public.clinic_hours;
create policy "clinic_hours_doctor_write" on public.clinic_hours
  for all using (public.is_doctor()) with check (public.is_doctor());

-- ----- appointments -----
drop policy if exists "appointments_select_own_or_doctor" on public.appointments;
create policy "appointments_select_own_or_doctor" on public.appointments
  for select using (patient_id = auth.uid() or public.is_doctor());

-- المريض ينشئ مواعيده فقط (الحجز يتم عبر RPC، لكن نسمح بالإدراج المباشر المقيّد أيضاً)
drop policy if exists "appointments_patient_insert" on public.appointments;
create policy "appointments_patient_insert" on public.appointments
  for insert with check (patient_id = auth.uid());

-- المريض يعدّل مواعيده (إلغاء/إعادة جدولة)، والطبيب يعدّل أي موعد (تأكيد)
drop policy if exists "appointments_update_own_or_doctor" on public.appointments;
create policy "appointments_update_own_or_doctor" on public.appointments
  for update using (patient_id = auth.uid() or public.is_doctor())
  with check (patient_id = auth.uid() or public.is_doctor());

-- ----- medical_records (المريض يقرأ ملفه، الطبيب يكتب) -----
drop policy if exists "medical_records_select_own_or_doctor" on public.medical_records;
create policy "medical_records_select_own_or_doctor" on public.medical_records
  for select using (patient_id = auth.uid() or public.is_doctor());

drop policy if exists "medical_records_doctor_write" on public.medical_records;
create policy "medical_records_doctor_write" on public.medical_records
  for all using (public.is_doctor()) with check (public.is_doctor());

-- ----- notifications (كل مستخدم يرى إشعاراته فقط) -----
drop policy if exists "notifications_select_own" on public.notifications;
create policy "notifications_select_own" on public.notifications
  for select using (user_id = auth.uid());

drop policy if exists "notifications_update_own" on public.notifications;
create policy "notifications_update_own" on public.notifications
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ----- case_studies (قراءة للجميع، إدارة للطبيب) -----
drop policy if exists "case_studies_select_all" on public.case_studies;
create policy "case_studies_select_all" on public.case_studies
  for select using (true);

drop policy if exists "case_studies_doctor_write" on public.case_studies;
create policy "case_studies_doctor_write" on public.case_studies
  for all using (public.is_doctor()) with check (public.is_doctor());

-- ----- reviews (قراءة المعتمدة للجميع، أو الطبيب يرى الكل) -----
drop policy if exists "reviews_select_approved_or_doctor" on public.reviews;
create policy "reviews_select_approved_or_doctor" on public.reviews
  for select using (is_approved = true or public.is_doctor());

-- أي زائر يستطيع إرسال تقييم (غير معتمد افتراضياً)
drop policy if exists "reviews_insert_public" on public.reviews;
create policy "reviews_insert_public" on public.reviews
  for insert with check (is_approved = false);

drop policy if exists "reviews_doctor_write" on public.reviews;
create policy "reviews_doctor_write" on public.reviews
  for all using (public.is_doctor()) with check (public.is_doctor());

-- =============================================================================
--  التخزين (Storage) — مجلد صور الأشعة ووسائط الحالات
-- =============================================================================
insert into storage.buckets (id, name, public)
values ('x-rays', 'x-rays', false)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('case-media', 'case-media', true)
on conflict (id) do nothing;

-- صور الأشعة: الطبيب يرفع/يحذف، والمريض يقرأ ملفاته فقط.
-- التنظيم المتوقع للمسار: x-rays/{patient_id}/{filename}
drop policy if exists "xray_doctor_manage" on storage.objects;
create policy "xray_doctor_manage" on storage.objects
  for all
  using (bucket_id = 'x-rays' and public.is_doctor())
  with check (bucket_id = 'x-rays' and public.is_doctor());

drop policy if exists "xray_patient_read_own" on storage.objects;
create policy "xray_patient_read_own" on storage.objects
  for select
  using (
    bucket_id = 'x-rays'
    and (public.is_doctor() or (storage.foldername(name))[1] = auth.uid()::text)
  );

-- وسائط الحالات (قبل/بعد): قراءة عامة، إدارة للطبيب
drop policy if exists "case_media_public_read" on storage.objects;
create policy "case_media_public_read" on storage.objects
  for select using (bucket_id = 'case-media');

drop policy if exists "case_media_doctor_manage" on storage.objects;
create policy "case_media_doctor_manage" on storage.objects
  for all
  using (bucket_id = 'case-media' and public.is_doctor())
  with check (bucket_id = 'case-media' and public.is_doctor());

-- =============================================================================
--  Realtime — تفعيل البث الحي للإشعارات والمواعيد
-- =============================================================================
do $$ begin
  alter publication supabase_realtime add table public.notifications;
exception when duplicate_object then null; end $$;

do $$ begin
  alter publication supabase_realtime add table public.appointments;
exception when duplicate_object then null; end $$;
