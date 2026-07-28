-- =============================================================================
--  Migration 0008 — إعادة كتابة الدوال/المشغّلات المتأثرة مباشرة بـ organization_id
--  Dental Clinic Migration 0008 — rewrite organization-scoped functions/triggers
--
--  النطاق (Scope) — أربع دوال فقط، متفق عليها مسبقاً:
--    1) public.book_appointment(...)             — RPC الحجز
--    2) public.notify_on_appointment_change()    — Trigger على appointments
--    3) public.notify_on_medical_record()        — Trigger على medical_records
--    4) public.dispatch_appointment_reminders()  — دالة مجدولة (pg_cron)
--
--  خارج النطاق عمداً (Explicitly out of scope):
--    - لا تعديل على public.is_doctor() — تُستخدم حصراً داخل سياسات RLS/Storage
--      (لا تستدعيها أي من الدوال الأربع أعلاه، مباشرة أو بشكل غير مباشر) —
--      تُراجَع بشكل مستقل ضمن Migration 0010.
--    - لا تعديل على public.handle_new_user().
--    - لا إنشاء أو تعديل أي سياسة RLS.
--    - لا نقل أي جدول إلى schema clinic.
--    - لا تعديل على أي Realtime Publication.
--
--  قابلة لإعادة التشغيل (Idempotent): "create or replace function" آمنة عند
--  إعادة التشغيل لنفس التوقيع. book_appointment تغيّر عدد المعاملات (توقيع
--  جديد)، لذا نُسقط التوقيع القديم صراحة أولاً (drop ... if exists) لتفادي
--  إبقاء نسخة قديمة معطوبة تستدعيها أي جهة عن طريق الخطأ.
--
--  ⚠️ تغيير غير متوافق مع الواجهة الأمامية (Breaking Change في RPC):
--  التوقيع القديم لـ book_appointment(p_service_id, p_date, p_start_time) —
--  بـ 3 معاملات فقط — يُسقَط نهائياً في هذه الـ migration ولن يعود موجوداً.
--  أي استدعاء حالي من الواجهة (مثل supabase.rpc("book_appointment", {...})
--  في src/components/landing/BookingForm.tsx) لا يزال يمرّر 3 معاملات فقط.
--  يجب تحديث كل استدعاء من هذا النوع ليُرسل p_organization_id أيضاً **قبل**
--  نشر هذه الـ migration على بيئة حية — وإلا فسيفشل الحجز بالكامل فوراً بعد
--  النشر (خطأ "function not found" لعدم تطابق أي توقيع مسجَّل). تنسيق نشر
--  الواجهة الأمامية مع نشر هذه الـ migration خارج نطاق ملف SQL هذا نفسه،
--  لكنه شرط أساسي لسلامة الإنتاج ويجب عدم تجاهله.
--
--  ⚠️ عدم إضافة منطق صلاحيات/عضوية داخل هذه الدوال (Business Logic فقط):
--  أي استعلام على public.organization_members داخل هذا الملف (في
--  notify_on_appointment_change) هو عملية بيانات بحتة — "من هي قائمة
--  المستلمين لهذا الإشعار؟" — وليس قرار تفويض/صلاحية ("هل يُسمح لهذا
--  المستخدم بالوصول؟"). لا تحتوي أي من الدوال الأربع أي فحص من نوع
--  is_org_member()/is_doctor() أو ما شابه؛ p_organization_id في
--  book_appointment يُستخدم فقط كقيمة تصفية بيانات (أي خدمة/ساعات عمل/تعارض
--  يخص هذه العيادة تحديداً)، وليس كبوابة صلاحية. أي تحقق فعلي من "هل يحق
--  لهذا المستخدم استخدام هذا organization_id أصلاً؟" متروك بالكامل لسياسات
--  RLS (Migration 0010) أو لدوال الـ Backbone المشتركة، وليس لهذا الملف.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) book_appointment: إضافة p_organization_id + تصفية كل استعلام داخلي به
-- ---------------------------------------------------------------------------

-- التوقيع القديم (3 معاملات) يصبح غير صالح للاستخدام أصلاً بعد هذا التعديل
-- (إدراجه القديم لا يضبط organization_id، وهذا العمود NOT NULL منذ 0006) —
-- يُسقَط صراحة بدل تركه معطوباً وقابلاً للاستدعاء بالخطأ.
drop function if exists public.book_appointment(uuid, date, time);

create or replace function public.book_appointment(
  p_service_id      uuid,
  p_date            date,
  p_start_time      time,
  p_organization_id uuid
)
returns public.appointments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_patient_id  uuid := auth.uid();
  v_dow         smallint := extract(dow from p_date);
  v_hours       public.clinic_hours%rowtype;
  v_duration    integer;
  v_end_time    time;
  v_new         public.appointments;
begin
  if v_patient_id is null then
    raise exception 'يجب تسجيل الدخول للحجز' using errcode = 'P0001';
  end if;

  if p_date < current_date then
    raise exception 'لا يمكن الحجز في تاريخ ماضٍ' using errcode = 'P0001';
  end if;

  -- تصفية بالعيادة: تمنع أيضاً حجز خدمة تابعة لعيادة أخرى بالخطأ
  select duration into v_duration from public.services
   where id = p_service_id and is_active = true and organization_id = p_organization_id;
  if v_duration is null then
    raise exception 'الخدمة المختارة غير متاحة' using errcode = 'P0001';
  end if;
  v_end_time := p_start_time + (v_duration || ' minutes')::interval;

  -- تصفية بالعيادة: ساعات عمل عيادة أخرى لا يجوز أن تُستخدم لهذا الحجز
  select * into v_hours from public.clinic_hours
   where day_of_week = v_dow and organization_id = p_organization_id;
  if v_hours is null or v_hours.is_closed then
    raise exception 'العيادة مغلقة في هذا اليوم' using errcode = 'P0001';
  end if;
  if p_start_time < v_hours.start_time or v_end_time > v_hours.end_time then
    raise exception 'الموعد المطلوب خارج ساعات عمل العيادة' using errcode = 'P0001';
  end if;

  -- فحص التعارض يبقى مقيّداً بنفس العيادة فقط (القيد الفريد في 0007 متوافق)
  perform 1 from public.appointments a
   join public.services s on s.id = a.service_id
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

  insert into public.appointments
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
-- 2) notify_on_appointment_change: إشعار كل أعضاء عيادة الموعد بدل "طبيب واحد"
-- ---------------------------------------------------------------------------
-- التغيير الجوهري: كانت تفترض طبيباً واحداً في كامل النظام عبر
-- "select id from profiles where role='doctor' limit 1". الآن تُشعِر كل
-- صف في organization_members مطابق لـ new.organization_id، وتُضيف
-- organization_id إلى كل إدراج في notifications (عمود NOT NULL منذ 0006).
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
  select name into service_name from public.services where id = new.service_id;

  if (tg_op = 'INSERT') then
    -- إشعار كل أعضاء عيادة هذا الموعد بحجز جديد
    -- "distinct" احترازي: لا يوجد تأكيد بوجود قيد يمنع أكثر من صف عضوية
    -- لنفس (organization_id, user_id) في organization_members (نفس نوع
    -- الشك الموثَّق سابقاً في Migration 0003 حول تفرّد عضوية المستخدم).
    -- لو وُجد صفّان لنفس العضو بالخطأ، سيُرسل بدون distinct إشعاران
    -- متطابقان لنفس الشخص لنفس الحدث. هذا الاحتراز لا علاقة له بسيناريو
    -- "المريض عضو أيضاً" — ذلك السيناريو لا يُنتج تكراراً أصلاً لأن كل فرع
    -- (INSERT / cancelled عبر الحلقة، وconfirmed عبر إدراج مباشر للمريض)
    -- يُنفَّذ بشكل حصري (elsif)، فلا يجتمع إدراج الحلقة وإدراج المريض
    -- المباشر في نفس الاستدعاء أبداً.
    for v_member in
      select distinct user_id from public.organization_members
       where organization_id = new.organization_id
    loop
      insert into public.notifications (user_id, organization_id, title, message)
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
      -- إشعار كل أعضاء العيادة بالإلغاء مع السبب (distinct لنفس سبب الاحتراز أعلاه)
      for v_member in
        select distinct user_id from public.organization_members
         where organization_id = new.organization_id
      loop
        insert into public.notifications (user_id, organization_id, title, message)
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
      insert into public.notifications (user_id, organization_id, title, message)
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
-- 3) notify_on_medical_record: تمرير organization_id فقط، بلا تغيير منطقي آخر
-- ---------------------------------------------------------------------------
create or replace function public.notify_on_medical_record()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notifications (user_id, organization_id, title, message)
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
-- 4) dispatch_appointment_reminders: إصلاح كسر فعلي (كانت تُدرج بلا organization_id)
-- ---------------------------------------------------------------------------
-- منذ Migration 0006، عمود notifications.organization_id أصبح NOT NULL —
-- النسخة القديمة من هذه الدالة كانت تُدرج بدونه، فتفشل بخطأ "not-null
-- violation" في أي تشغيل فعلي حالياً. الإصلاح: اشتقاق organization_id من
-- صف الموعد نفسه (r.organization_id متاح مباشرة لأن r هو a.* من appointments).
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
    from public.appointments a
    join public.services s on s.id = a.service_id
    where a.status in ('pending', 'confirmed')
      and (a.appointment_date + a.start_time) > now()
  loop
    v_service := r.service_name;
    v_when := (r.appointment_date + r.start_time)::timestamptz;

    -- تذكير 24 ساعة
    if v_when - now() <= interval '24 hours'
       and v_when - now() > interval '23 hours'
       and not exists (
         select 1 from public.appointment_reminders
         where appointment_id = r.id and kind = '24h'
       ) then
      insert into public.notifications (user_id, organization_id, title, message)
      values (r.patient_id, r.organization_id, 'تذكير: موعدك غداً',
              format('لديك موعد (%s) غداً الساعة %s. نتطلّع لرؤيتك!', v_service, r.start_time));
      insert into public.appointment_reminders (appointment_id, kind) values (r.id, '24h');
      v_count := v_count + 1;
    end if;

    -- تذكير ساعة واحدة
    if v_when - now() <= interval '1 hour'
       and v_when - now() > interval '0 minutes'
       and not exists (
         select 1 from public.appointment_reminders
         where appointment_id = r.id and kind = '1h'
       ) then
      insert into public.notifications (user_id, organization_id, title, message)
      values (r.patient_id, r.organization_id, 'تذكير: موعدك بعد ساعة',
              format('موعدك (%s) بعد ساعة تقريباً الساعة %s.', v_service, r.start_time));
      insert into public.appointment_reminders (appointment_id, kind) values (r.id, '1h');
      v_count := v_count + 1;
    end if;
  end loop;

  return v_count;
end;
$$;
