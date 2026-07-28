-- =============================================================================
--  منطق التذكيرات (Reminders) + بيانات أولية (Seed)
--
--  التذكيرات: دالة تُستدعى دورياً (عبر pg_cron أو Supabase Scheduled Edge
--  Function) لإدراج إشعارات تذكير قبل الموعد بـ 24 ساعة وبـ ساعة واحدة.
--  نستخدم جدول تتبّع لمنع تكرار التذكير لنفس الموعد/النوع.
-- =============================================================================

-- جدول تتبّع التذكيرات المُرسلة (لمنع التكرار / idempotency)
create table if not exists public.appointment_reminders (
  appointment_id  uuid not null references public.appointments (id) on delete cascade,
  kind            text not null check (kind in ('24h', '1h')),
  sent_at         timestamptz not null default now(),
  primary key (appointment_id, kind)
);

alter table public.appointment_reminders enable row level security;
-- لا توجد سياسات للمستخدمين — الوصول عبر دوال SECURITY DEFINER فقط.

-- الدالة الدورية: تفحص المواعيد القادمة وتُنشئ إشعارات التذكير المستحقة
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

    -- تذكير 24 ساعة: ضمن النافذة [23h, 24h] من الآن
    if v_when - now() <= interval '24 hours'
       and v_when - now() > interval '23 hours'
       and not exists (
         select 1 from public.appointment_reminders
         where appointment_id = r.id and kind = '24h'
       ) then
      insert into public.notifications (user_id, title, message)
      values (r.patient_id, 'تذكير: موعدك غداً',
              format('لديك موعد (%s) غداً الساعة %s. نتطلّع لرؤيتك!', v_service, r.start_time));
      insert into public.appointment_reminders (appointment_id, kind) values (r.id, '24h');
      v_count := v_count + 1;
    end if;

    -- تذكير ساعة واحدة: ضمن النافذة [0, 1h] من الآن
    if v_when - now() <= interval '1 hour'
       and v_when - now() > interval '0 minutes'
       and not exists (
         select 1 from public.appointment_reminders
         where appointment_id = r.id and kind = '1h'
       ) then
      insert into public.notifications (user_id, title, message)
      values (r.patient_id, 'تذكير: موعدك بعد ساعة',
              format('موعدك (%s) بعد ساعة تقريباً الساعة %s.', v_service, r.start_time));
      insert into public.appointment_reminders (appointment_id, kind) values (r.id, '1h');
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

-- =============================================================================
--  بيانات أولية (Seed)
-- =============================================================================

-- ساعات العمل الأسبوعية (0=الأحد .. 6=السبت). الجمعة مغلق.
insert into public.clinic_hours (day_of_week, start_time, end_time, is_closed) values
  (0, '09:00', '17:00', false),  -- الأحد
  (1, '09:00', '17:00', false),  -- الإثنين
  (2, '09:00', '17:00', false),  -- الثلاثاء
  (3, '09:00', '17:00', false),  -- الأربعاء
  (4, '09:00', '14:00', false),  -- الخميس
  (5, '00:00', '00:00', true),   -- الجمعة (مغلق)
  (6, '10:00', '15:00', false)   -- السبت
on conflict (day_of_week) do nothing;

-- خدمات افتراضية (أسباب الحجز)
insert into public.services (name, description, duration, price) values
  ('كشف وتشخيص', 'فحص شامل للأسنان واللثة مع خطة علاجية', 30, 100),
  ('تنظيف وتلميع الأسنان', 'إزالة الجير والتصبغات وتلميع الأسنان', 45, 200),
  ('حشو الأسنان', 'حشو تجميلي بمادة الكومبوزيت', 60, 250),
  ('علاج عصب', 'علاج جذور الأسنان (سحب العصب)', 90, 600),
  ('تبييض الأسنان', 'جلسة تبييض احترافية بالليزر', 60, 800),
  ('تقويم الأسنان — استشارة', 'استشارة وتقييم لحالة التقويم', 30, 150)
on conflict do nothing;

-- تقييمات معتمدة للعرض في صفحة الهبوط
insert into public.reviews (patient_name, rating, comment, is_approved) values
  ('أحمد العتيبي', 5, 'تجربة رائعة وطاقم محترف، أنصح الجميع بزيارة العيادة.', true),
  ('سارة المالكي', 5, 'أفضل عيادة أسنان زرتها، نظافة ودقة في المواعيد.', true),
  ('خالد الدوسري', 4, 'خدمة ممتازة ونتائج تبييض مبهرة.', true)
on conflict do nothing;

-- حالات قبل/بعد (روابط الصور تُحدّث بعد رفعها إلى Storage)
insert into public.case_studies (title, description, before_image_url, after_image_url) values
  ('تبييض وتجميل الأسنان الأمامية', 'نتيجة جلسة تبييض احترافية مع تركيب فينير.', null, null),
  ('علاج تقويم الأسنان', 'تصحيح اصطفاف الأسنان خلال 12 شهراً.', null, null)
on conflict do nothing;
