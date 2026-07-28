-- =============================================================================
--  Migration 0006 — سياسات RLS لجداول العيادة (نهائية من البداية)
--  Dental Clinic Migration 0006 — clinic RLS policies (final form from day one)
--
--  النطاق (Scope): تفعيل RLS + كل السياسات على الجداول الثمانية، معتمدة على
--  public.is_org_member(organization_id) مباشرة منذ البداية — لا "is_doctor()"
--  إطلاقاً، ولا مرحلة انتقالية، لأن لا نسخة سابقة لهذه السياسات في هذا المشروع.
--
--  is_org_member() جرى التحقق من وجودها بالتوقيع الصحيح في Migration 0002 —
--  إن نجحت 0002، فهذه الخطوة آمنة دون فحص إضافي هنا.
--
--  appointment_reminders: RLS مفعَّلة، بلا أي سياسة مستخدمين — الوصول فقط
--  عبر دوال SECURITY DEFINER (dispatch_appointment_reminders).
--
--  خارج النطاق: لا سياسات Storage (Migration 0007 منفصلة).
--
--  قابلة لإعادة التشغيل (Idempotent): drop policy if exists ثم create policy.
-- =============================================================================

alter table clinic.services              enable row level security;
alter table clinic.clinic_hours          enable row level security;
alter table clinic.appointments          enable row level security;
alter table clinic.medical_records       enable row level security;
alter table clinic.notifications         enable row level security;
alter table clinic.case_studies          enable row level security;
alter table clinic.reviews               enable row level security;
alter table clinic.appointment_reminders enable row level security;

-- ----- services (قراءة عامة — تُصفَّى بالعيادة على مستوى الواجهة، إدارة لأعضاء العيادة) -----
drop policy if exists "services_select_all" on clinic.services;
create policy "services_select_all" on clinic.services
  for select using (true);

drop policy if exists "services_org_write" on clinic.services;
create policy "services_org_write" on clinic.services
  for all
  using (public.is_org_member(organization_id))
  with check (public.is_org_member(organization_id));

-- ----- clinic_hours (نفس نمط services) -----
drop policy if exists "clinic_hours_select_all" on clinic.clinic_hours;
create policy "clinic_hours_select_all" on clinic.clinic_hours
  for select using (true);

drop policy if exists "clinic_hours_org_write" on clinic.clinic_hours;
create policy "clinic_hours_org_write" on clinic.clinic_hours
  for all
  using (public.is_org_member(organization_id))
  with check (public.is_org_member(organization_id));

-- ----- appointments -----
drop policy if exists "appointments_select_own_or_member" on clinic.appointments;
create policy "appointments_select_own_or_member" on clinic.appointments
  for select
  using (patient_id = auth.uid() or public.is_org_member(organization_id));

-- المريض ينشئ مواعيده فقط (الحجز يتم عادة عبر book_appointment RPC، لكن
-- نسمح بالإدراج المباشر المقيّد أيضاً)
drop policy if exists "appointments_patient_insert" on clinic.appointments;
create policy "appointments_patient_insert" on clinic.appointments
  for insert with check (patient_id = auth.uid());

-- المريض يعدّل مواعيده (إلغاء/إعادة جدولة)، وعضو العيادة يعدّل أي موعد تابع لعيادته
drop policy if exists "appointments_update_own_or_member" on clinic.appointments;
create policy "appointments_update_own_or_member" on clinic.appointments
  for update
  using (patient_id = auth.uid() or public.is_org_member(organization_id))
  with check (patient_id = auth.uid() or public.is_org_member(organization_id));

-- ----- medical_records (المريض يقرأ ملفه، عضو العيادة يكتب) -----
drop policy if exists "medical_records_select_own_or_member" on clinic.medical_records;
create policy "medical_records_select_own_or_member" on clinic.medical_records
  for select
  using (patient_id = auth.uid() or public.is_org_member(organization_id));

drop policy if exists "medical_records_org_write" on clinic.medical_records;
create policy "medical_records_org_write" on clinic.medical_records
  for all
  using (public.is_org_member(organization_id))
  with check (public.is_org_member(organization_id));

-- ----- notifications (كل مستخدم يرى إشعاراته فقط — ملكية شخصية، لا علاقة بعضوية المنظمة) -----
drop policy if exists "notifications_select_own" on clinic.notifications;
create policy "notifications_select_own" on clinic.notifications
  for select using (user_id = auth.uid());

drop policy if exists "notifications_update_own" on clinic.notifications;
create policy "notifications_update_own" on clinic.notifications
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ----- case_studies (نفس نمط services) -----
drop policy if exists "case_studies_select_all" on clinic.case_studies;
create policy "case_studies_select_all" on clinic.case_studies
  for select using (true);

drop policy if exists "case_studies_org_write" on clinic.case_studies;
create policy "case_studies_org_write" on clinic.case_studies
  for all
  using (public.is_org_member(organization_id))
  with check (public.is_org_member(organization_id));

-- ----- reviews (قراءة المعتمدة للجميع أو لعضو العيادة، إدراج عام غير معتمد) -----
drop policy if exists "reviews_select_approved_or_member" on clinic.reviews;
create policy "reviews_select_approved_or_member" on clinic.reviews
  for select
  using (is_approved = true or public.is_org_member(organization_id));

drop policy if exists "reviews_insert_public" on clinic.reviews;
create policy "reviews_insert_public" on clinic.reviews
  for insert with check (is_approved = false);

drop policy if exists "reviews_org_write" on clinic.reviews;
create policy "reviews_org_write" on clinic.reviews
  for all
  using (public.is_org_member(organization_id))
  with check (public.is_org_member(organization_id));
