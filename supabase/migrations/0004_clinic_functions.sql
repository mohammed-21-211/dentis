-- =============================================================================
--  Migration 0004 — دوال منطق العيادة (مكتوبة نهائياً بـ organization_id من البداية)
--  Dental Clinic Migration 0004 — clinic business-logic functions
--
--  النطاق (Scope): أربع دوال، كل مرجع جدول فيها مؤهَّل بالكامل (clinic.* أو
--  public.profiles/public.organization_members)، بلا أي حاجة لتوقيع "قديم"
--  لأن لا نسخة سابقة لهذه الدوال في هذا المشروع:
--    1) public.book_appointment(p_service_id, p_date, p_start_time, p_organization_id)
--    2) public.notify_on_appointment_change()
--    3) public.notify_on_medical_record()
--    4) public.dispatch_appointment_reminders()
--
--  لماذا في public وليس clinic: هذه دوال RPC/Trigger تُستدعى عبر PostgREST
--  والمشغّلات؛ نفس نمط الـ Backbone (current_organization_id, is_org_member)
--  حيث تبقى الدوال في public بينما تشير لبيانات في clinic.
--
--  لا منطق عضوية/صلاحيات داخل أي منها (Business Logic فقط؛ التفويض بالكامل
--  في RLS — Migration 0006):
--    - p_organization_id في book_appointment قيمة تصفية بيانات فقط.
--    - استعلام organization_members في notify_on_appointment_change عملية
--      بيانات بحتة (قائمة مستلمي إشعار)، وليس قرار تفويض.
--
--  خارج النطاق: لا is_doctor()، لا handle_new_user() — لا علاقة لهما بهذا
--  التصميم إطلاقاً.
--
--  قابلة لإعادة التشغيل (Idempotent): create or replace لكل الأربعة (لا حاجة
--  لأي DROP مسبق، لأنه لا توجد نسخة سابقة بتوقيع مختلف في هذا المشروع).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) book_appointment — RPC الحجز الذرّي
-- ---------------------------------------------------------------------------
create or replace function public.book_appointment(
  p_service_id      uuid,
  p_date            date,
  p_start_time      time,
  p_organization_id uuid
)
returns clinic.appointments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_patient_id  uuid := auth.uid();
  v_dow         smallint := extract(dow from p_date);   -- 0=الأحد .. 6=السبت
  v_hours       clinic.clinic_hours%rowtype;
  v_duration    integer;
  v_end_time    time;
  v_new         clinic.appointments;
begin
  if v_patient_id is null then
    raise exception 'يجب تسجيل الدخول للحجز' using errcode = 'P0001';
  end if;

  if p_date < current_date then
    raise exception 'لا يمكن الحجز في تاريخ ماضٍ' using errcode = 'P0001';
  end if;

  -- تصفية بالعيادة: تمنع أيضاً حجز خدمة تابعة لعيادة أخرى بالخطأ
  select duration into v_duration from clinic.services
   where id = p_service_id and is_active = true and organization_id = p_organization_id;
  if v_duration is null then
    raise exception 'الخدمة المختارة غير متاحة' using errcode = 'P0001';
  end if;
  v_end_time := p_start_time + (v_duration || ' minutes')::interval;

  select * into v_hours from clinic.clinic_hours
   where day_of_week = v_dow and organization_id = p_organization_id;
  if v_hours is null or v_hours.is_closed then
    raise exception 'العيادة مغلقة في هذا اليوم' using errcode = 'P0001';
  end if;
  if p_start_time < v_hours.start_time or v_end_time > v_hours.end_time then
    raise exception 'الموعد المطلوب خارج ساعات عمل العيادة' using errcode = 'P0001';
  end if;

  -- منع التعارض: قفل الفترات المتداخلة داخل نفس العيادة ثم الفحص
  perform 1 from clinic.appointments a
   join clinic.services s on s.id = a.service_id
   where a.organization_id = p_organization_id
     and a.appointment_date = p_date
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

  insert into clinic.appointments
    (patient_id, service_id, organization_id, appointment_date, start_time, status)
  values
    (v_patient_id, p_service_id, p_organization_id, p_date, p_start_time, 'pending')
  returning * into v_new;

  return v_new;
exception
  when unique_violation then
    -- اصطدم الفهرس الفريد الجزئي — حجزٌ متزامن سبَقَنا داخل نفس العيادة
    raise exception 'هذه الفترة حُجزت للتو، يرجى اختيار وقت آخر' using errcode = 'P0001';
end;
$$;

-- ---------------------------------------------------------------------------
-- 2) notify_on_appointment_change — Trigger على appointments
--    يُشعِر كل أعضاء عيادة الموعد (عبر organization_members)، وليس "طبيباً
--    واحداً عالمياً" كما في التصميم أحادي العيادة القديم.
-- ---------------------------------------------------------------------------
create or replace function public.notify_on_appointment_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  patient_name  text;
  service_name  text;
  v_member      record;
begin
  select full_name into patient_name from public.profiles where id = new.patient_id;
  select name into service_name from clinic.services where id = new.service_id;

  if (tg_op = 'INSERT') then
    -- distinct احترازي: لا يوجد تأكيد بقيد يمنع أكثر من صف عضوية لنفس
    -- (organization_id, user_id) في organization_members
    for v_member in
      select distinct user_id from public.organization_members
       where organization_id = new.organization_id
    loop
      insert into clinic.notifications (user_id, organization_id, title, message)
      values (
        v_member.user_id,
        new.organization_id,
        'حجز موعد جديد',
        format('قام %s بحجز موعد (%s) بتاريخ %s الساعة %s',
               patient_name, service_name, new.appointment_date, new.start_time)
      );
    end loop;

  elsif (tg_op = 'UPDATE' and new.status is distinct from old.status) then
    if new.status = 'cancelled' then
      for v_member in
        select distinct user_id from public.organization_members
         where organization_id = new.organization_id
      loop
        insert into clinic.notifications (user_id, organization_id, title, message)
        values (
          v_member.user_id,
          new.organization_id,
          'إلغاء موعد',
          format('ألغى %s موعده بتاريخ %s. السبب: %s',
                 patient_name, new.appointment_date, coalesce(new.cancellation_reason, '—'))
        );
      end loop;
    elsif new.status = 'confirmed' then
      -- إشعار المريض بتأكيد الموعد (لا علاقة له بعضوية المنظمة)
      insert into clinic.notifications (user_id, organization_id, title, message)
      values (
        new.patient_id,
        new.organization_id,
        'تم تأكيد موعدك',
        format('تم تأكيد موعدك (%s) بتاريخ %s الساعة %s',
               service_name, new.appointment_date, new.start_time)
      );
    end if;
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3) notify_on_medical_record — Trigger على medical_records
-- ---------------------------------------------------------------------------
create or replace function public.notify_on_medical_record()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into clinic.notifications (user_id, organization_id, title, message)
  values (
    new.patient_id,
    new.organization_id,
    'تحديث في ملفك الطبي',
    'قام الطبيب بإضافة أو تحديث معلومات في سجلك الطبي. يمكنك الاطلاع عليها من لوحة التحكم.'
  );
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4) dispatch_appointment_reminders — دالة مجدولة (pg_cron)
-- ---------------------------------------------------------------------------
create or replace function public.dispatch_appointment_reminders()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  r            record;
  v_count      integer := 0;
  v_service    text;
  v_when       timestamptz;
begin
  for r in
    select a.*, s.name as service_name
    from clinic.appointments a
    join clinic.services s on s.id = a.service_id
    where a.status in ('pending', 'confirmed')
      and (a.appointment_date + a.start_time) > now()
  loop
    v_service := r.service_name;
    v_when := (r.appointment_date + r.start_time)::timestamptz;

    -- تذكير 24 ساعة: ضمن النافذة [23h, 24h] من الآن
    if v_when - now() <= interval '24 hours'
       and v_when - now() > interval '23 hours'
       and not exists (
         select 1 from clinic.appointment_reminders
         where appointment_id = r.id and kind = '24h'
       ) then
      insert into clinic.notifications (user_id, organization_id, title, message)
      values (r.patient_id, r.organization_id, 'تذكير: موعدك غداً',
              format('لديك موعد (%s) غداً الساعة %s. نتطلّع لرؤيتك!', v_service, r.start_time));
      insert into clinic.appointment_reminders (appointment_id, kind) values (r.id, '24h');
      v_count := v_count + 1;
    end if;

    -- تذكير ساعة واحدة: ضمن النافذة [0, 1h] من الآن
    if v_when - now() <= interval '1 hour'
       and v_when - now() > interval '0 minutes'
       and not exists (
         select 1 from clinic.appointment_reminders
         where appointment_id = r.id and kind = '1h'
       ) then
      insert into clinic.notifications (user_id, organization_id, title, message)
      values (r.patient_id, r.organization_id, 'تذكير: موعدك بعد ساعة',
              format('موعدك (%s) بعد ساعة تقريباً الساعة %s.', v_service, r.start_time));
      insert into clinic.appointment_reminders (appointment_id, kind) values (r.id, '1h');
      v_count := v_count + 1;
    end if;
  end loop;

  return v_count; -- عدد التذكيرات المُرسلة في هذه الدورة
end;
$$;

-- جدولة التشغيل كل 15 دقيقة عبر pg_cron (إن كانت الإضافة مفعّلة).
-- في Supabase: فعّل pg_cron من Database > Extensions ثم نفّذ:
--   select cron.schedule('dispatch-reminders', '*/15 * * * *',
--                        $$ select public.dispatch_appointment_reminders(); $$);
