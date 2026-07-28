-- =============================================================================
--  Migration 0011 — تحديث مراجع الجداول داخل الدوال لتصبح clinic.*
--  Dental Clinic Migration 0011 — repoint function bodies at the clinic schema
--
--  النطاق (Scope): تحديث التأهيل (schema qualification) فقط داخل أجسام أربع
--  دوال، من "public.<table>" إلى "clinic.<table>" للجداول الثمانية المنقولة
--  في Migration 0010. لا تغيير في أي منطق عمل، شرط، أو سلوك:
--    1) public.book_appointment(...)
--    2) public.notify_on_appointment_change()
--    3) public.notify_on_medical_record()
--    4) public.dispatch_appointment_reminders()
--
--  تبقى كل الدوال نفسها في schema public (الدوال لا تنتقل، الجداول فقط
--  انتقلت) — فقط مراجعها الداخلية لتلك الجداول أصبحت "clinic.<table>".
--  مراجع public.profiles وpublic.organization_members تبقى بلا أي تغيير
--  (لم تنتقل، لا تزال في public).
--
--  خصائص مُبقاة كما هي كما طُلب صراحةً على الأربعة:
--    - security definer
--    - set search_path = public   (لم يُوسَّع ليشمل clinic؛ كل مرجع لجدول
--      منقول مؤهَّل صراحةً بـ "clinic." بدل الاعتماد على search_path — أكثر
--      أماناً وأوضح قراءةً، كما أُوصي به سابقاً وتمت الموافقة عليه ضمنياً)
--    - أسماء مؤهّلة بالكامل (clinic.table_name) في كل مرجع
--
--  خارج النطاق عمداً: لا تعديل على is_doctor()، handle_new_user()، أي RLS،
--  أي Trigger attachment، أي فهرس/قيد، ولا أي نقل schema إضافي.
--
--  ⚠️ ملاحظة توقيع: book_appointment() تتطلب DROP صريحاً قبل CREATE OR
--  REPLACE، لأن نوع الإرجاع تغيّر من "returns public.appointments" إلى
--  "returns clinic.appointments" بعد نقل الجدول في 0010 — وPostgres يرفض
--  "create or replace function" إن تغيّر نوع الإرجاع (يجب DROP أولاً).
--  الدوال الثلاث الأخرى تُعيد "trigger"/"integer" (نوع لا يتغيّر بنقل schema)،
--  فتبقى create or replace كافية بلا حاجة لأي DROP.
--
--  قابلة لإعادة التشغيل (Idempotent): create or replace لثلاث دوال؛
--  drop if exists + create للرابعة (book_appointment) بسبب تغيّر نوع الإرجاع.
--
--  ⚠️ تذكير: هذه الـ migration هي الجزء الثاني من زوج منشور مترابط مع
--  Migration 0010 (انظر تعليق "الترتيب التشغيلي" في رأس ذلك الملف) — لا
--  يجوز تطبيق 0010 دون تطبيق هذه مباشرة بعدها ضمن نفس نافذة النشر.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) book_appointment: DROP إلزامي بسبب تغيّر نوع الإرجاع، ثم CREATE بمراجع clinic.*
-- ---------------------------------------------------------------------------
drop function if exists public.book_appointment(uuid, date, time, uuid);

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
  v_dow         smallint := extract(dow from p_date);
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
    raise exception 'هذه الفترة حُجزت للتو، يرجى اختيار وقت آخر' using errcode = 'P0001';
end;
$$;

-- ---------------------------------------------------------------------------
-- 2) notify_on_appointment_change: تحديث مراجع services/notifications فقط
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
-- 3) notify_on_medical_record: تحديث مرجع notifications فقط
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
-- 4) dispatch_appointment_reminders: تحديث مراجع appointments/services/
--    appointment_reminders/notifications
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

  return v_count;
end;
$$;
