-- =============================================================================
--  Migration 0007 — تعديل القيود الفريدة لتشمل organization_id
--  Dental Clinic Migration 0007 — scope unique constraints to organization_id
--
--  النطاق (Scope):
--    استبدال قيدين فريدين كانا يفترضان "عيادة واحدة عالمياً"، بحيث يصبح
--    التفرّد داخل كل منظمة على حدة بدل النظام كله:
--
--    1) appointments_unique_active_slot: كانت (appointment_date, start_time)
--       حيث status <> 'cancelled' — تمنع أي عيادتين من الحجز في نفس التاريخ
--       والوقت، حتى لو كانتا منظمتين مختلفتين تماماً. تصبح:
--       (organization_id, appointment_date, start_time) بنفس شرط status.
--
--    2) clinic_hours على day_of_week: كان unique عالمياً — يمنع عيادة ثانية
--       من إدخال ساعات عملها لنفس يوم الأسبوع. يصبح:
--       unique (organization_id, day_of_week).
--
--  لماذا هذه Migration منفصلة عن 0006:
--    خلافاً لفهارس 0006 (إضافة فقط)، هذان القيدان يجب إسقاطهما أولاً قبل
--    إنشاء البديل — الإبقاء على القديم كما هو إلى جانب الجديد يجعل القيد
--    القديم (الأكثر تقييداً) لا يزال فعّالاً ويمنع سيناريوهات صحيحة متعددة
--    العيادات. هذا تغيير سلوك فعلي على قاعدة البيانات، وليس تحسين أداء فقط.
--
--  ⚠️ اعتماد صريح على Migration 0006 (لا يوجد تحقق برمجي داخل هذا الملف):
--  القيدان الجديدان يتضمّنان organization_id كعمود أساسي فيهما. هذا يفترض
--  أن Migration 0006 نُفِّذت بنجاح قبل هذه الخطوة، وأن organization_id على
--  appointments وclinic_hours لم يعد NULL في أي صف (فُرض NOT NULL في 0006).
--  إن لم تُطبَّق 0006 أولاً، فالقيدان الجديدان سيُنشآن رغم ذلك تقنياً (UNIQUE
--  لا يمنع NULL، وPostgres يعامل كل NULL كقيمة مختلفة عن غيرها في القيد
--  الفريد) — لكن هذا يعني عملياً أن التفرّد لا يُطبَّق فعلياً على أي صف
--  organization_id فيه NULL، فيعود الخطر الأصلي (تعارض حجوزات بلا عزل حقيقي)
--  دون أن تفشل هذه الـ migration بأي خطأ ظاهر. لذلك يجب التأكد من تطبيق 0006
--  قبل 0007 دائماً، وليس فقط الاعتماد على نجاح تنفيذ هذا الملف كدليل صحة.
--
--  ⚠️ متطلب سلامة البيانات قبل إنشاء كل قيد فريد جديد (لا تحقق برمجي هنا،
--  توثيق فقط — القيد نفسه سيرفض المخالفات عند التنفيذ):
--    - لا يجوز وجود صفّين في appointments بنفس القيمة الثلاثية
--      (organization_id, appointment_date, start_time) وكلاهما status <>
--      'cancelled' — وإلا فشل "create unique index" بخطأ "duplicate key value".
--    - لا يجوز وجود صفّين في clinic_hours بنفس القيمة الثنائية
--      (organization_id, day_of_week) — وإلا فشل "alter table add constraint"
--      بنفس نوع الخطأ.
--  هذا التعارض غير متوقَّع على القاعدة الحالية (فارغة بعد 0005)، لكن على أي
--  قاعدة تحتوي بيانات تاريخية فعلية، فشل الإنشاء بهذا السبب تحديداً هو سلوك
--  صحيح ومقصود — يكشف تعارضاً حقيقياً موجوداً بالفعل في البيانات (حجزان
--  متزامنان لنفس العيادة، أو يوم عمل مكرّر لنفس العيادة) يجب حلّه يدوياً في
--  البيانات نفسها (دمج/حذف/تصحيح الصف المكرّر)، وليس بتعديل هذا الملف لتخفيف
--  القيد أو تجاوز الخطأ.
--
--  خارج النطاق عمداً (Explicitly out of scope):
--    - لا تعديل على أي دالة/Trigger/RLS (تأتي في 0009/0010).
--    - لا نقل أي جدول إلى schema clinic.
--
--  قابلة لإعادة التشغيل (Idempotent): كل خطوة تتحقق من الحالة الحالية قبل
--  أي إسقاط/إنشاء، فلا تفشل عند تشغيلها أكثر من مرة.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) appointments: القيد الفريد الجزئي على الفترة الزمنية
-- ---------------------------------------------------------------------------
drop index if exists public.appointments_unique_active_slot;

create unique index if not exists appointments_unique_active_slot
  on public.appointments (organization_id, appointment_date, start_time)
  where status <> 'cancelled';

-- ---------------------------------------------------------------------------
-- 2) clinic_hours: القيد الفريد على day_of_week
-- ---------------------------------------------------------------------------

-- الاسم التلقائي المتوقَّع لقيد "unique" المُعرَّف ضمنياً في العمود
-- (0001_initial_schema.sql: "day_of_week smallint not null unique check (...)")
-- هو clinic_hours_day_of_week_key وفق تسمية Postgres الافتراضية. للاحتياط —
-- بما أنه لم يُسمَّ صراحةً في 0001 — نبحث عنه ديناميكياً عبر pg_constraint
-- بدل افتراض الاسم حرفياً، لضمان إسقاط القيد الصحيح بغض النظر عن اسمه الفعلي.
do $$
declare
  v_conname text;
begin
  select con.conname into v_conname
  from pg_constraint con
  join pg_class rel on rel.oid = con.conrelid
  join pg_namespace nsp on nsp.oid = rel.relnamespace
  where nsp.nspname = 'public'
    and rel.relname = 'clinic_hours'
    and con.contype = 'u'
    and con.conkey = (
      select array_agg(attnum order by attnum)
      from pg_attribute
      where attrelid = rel.oid
        and attname = 'day_of_week'
    );

  if v_conname is not null then
    execute format('alter table public.clinic_hours drop constraint %I', v_conname);
  end if;
end $$;

-- القيد البديل: التفرّد على مستوى المنظمة بدل النظام كله
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'clinic_hours_organization_id_day_of_week_key'
      and conrelid = 'public.clinic_hours'::regclass
  ) then
    alter table public.clinic_hours
      add constraint clinic_hours_organization_id_day_of_week_key
      unique (organization_id, day_of_week);
  end if;
end $$;
