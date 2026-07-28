-- =============================================================================
--  Migration 0005 — ربط المشغّلات (Triggers) + تفعيل Realtime
--  Dental Clinic Migration 0005 — attach triggers + enable realtime publication
--
--  النطاق (Scope):
--    - trg_notify_appointment على clinic.appointments → notify_on_appointment_change()
--    - trg_notify_medical_record على clinic.medical_records → notify_on_medical_record()
--    - إضافة clinic.notifications وclinic.appointments إلى publication
--      supabase_realtime (بث حي للإشعارات والمواعيد، كما في التصميم الأصلي).
--
--  يأتي بعد 0003 (الجداول) و0004 (الدوال) لأن ربط Trigger يتطلب وجود الجدول
--  والدالة معاً.
--
--  قابلة لإعادة التشغيل (Idempotent): drop trigger if exists ثم create trigger
--  (نفس نمط 0001 الأصلي)؛ alter publication add table داخل exception handler
--  يتجاهل duplicate_object عند إعادة التشغيل.
-- =============================================================================

drop trigger if exists trg_notify_appointment on clinic.appointments;
create trigger trg_notify_appointment
  after insert or update on clinic.appointments
  for each row execute function public.notify_on_appointment_change();

drop trigger if exists trg_notify_medical_record on clinic.medical_records;
create trigger trg_notify_medical_record
  after insert on clinic.medical_records
  for each row execute function public.notify_on_medical_record();

do $$ begin
  alter publication supabase_realtime add table clinic.notifications;
exception when duplicate_object then null; end $$;

do $$ begin
  alter publication supabase_realtime add table clinic.appointments;
exception when duplicate_object then null; end $$;
