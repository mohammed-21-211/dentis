-- =============================================================================
--  Migration 0007 — تخزين الملفات (Storage) بتصميم مسار يدعم تعدد العيادات من البداية
--  Dental Clinic Migration 0007 — storage buckets/policies, org-aware path from day one
--
--  النطاق (Scope): buckets `x-rays` (خاص) و`case-media` (عام) + سياساتهما.
--
--  تصميم المسار الجديد (مختلف عن المشروع القديم الذي لم يكن يدعم تعدد
--  العيادات في المسار إطلاقاً):
--    x-rays:      x-rays/{organization_id}/{patient_id}/{filename}
--    case-media:  case-media/{organization_id}/{filename}
--
--  ⚠️ يتطلب تعديل كود الواجهة الأمامية (خارج نطاق SQL): أي مكان يبني مسار
--  رفع لهذين الـ bucket (مثل PatientDetail.tsx لصور الأشعة، وCaseStudiesManager
--  عبر storage.ts لوسائط الحالات) يجب أن يُضيف organization_id كأول segment
--  في المسار — وإلا فسترفض RLS أدناه أي رفع/قراءة لعدم تطابق segment أول
--  مع أي عضوية فعلية.
--
--  ملاحظة تقنية: (storage.foldername(name))[1]::uuid يفشل بخطأ صريح (وليس
--  false بهدوء) إن كان أول segment في المسار ليس UUID صالحاً — هذا سلوك
--  "fail closed" مقبول أمنياً (لا وصول يُمنح لمسار مشوَّه)، لكنه يظهر كخطأ
--  وليس كرفض هادئ.
--
--  قابلة لإعادة التشغيل (Idempotent): insert ... on conflict do nothing
--  للـ buckets، drop policy if exists ثم create policy للسياسات.
-- =============================================================================

insert into storage.buckets (id, name, public)
values ('x-rays', 'x-rays', false)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('case-media', 'case-media', true)
on conflict (id) do nothing;

-- ----- x-rays: عضو العيادة يرفع/يحذف صور عيادته، المريض يقرأ ملفاته فقط -----
drop policy if exists "xray_org_manage" on storage.objects;
create policy "xray_org_manage" on storage.objects
  for all
  using (
    bucket_id = 'x-rays'
    and public.is_org_member(((storage.foldername(name))[1])::uuid)
  )
  with check (
    bucket_id = 'x-rays'
    and public.is_org_member(((storage.foldername(name))[1])::uuid)
  );

drop policy if exists "xray_patient_read_own" on storage.objects;
create policy "xray_patient_read_own" on storage.objects
  for select
  using (
    bucket_id = 'x-rays'
    and (
      public.is_org_member(((storage.foldername(name))[1])::uuid)
      or (storage.foldername(name))[2] = auth.uid()::text
    )
  );

-- ----- case-media: قراءة عامة، إدارة لعضو العيادة صاحبة الملف -----
drop policy if exists "case_media_public_read" on storage.objects;
create policy "case_media_public_read" on storage.objects
  for select using (bucket_id = 'case-media');

drop policy if exists "case_media_org_manage" on storage.objects;
create policy "case_media_org_manage" on storage.objects
  for all
  using (
    bucket_id = 'case-media'
    and public.is_org_member(((storage.foldername(name))[1])::uuid)
  )
  with check (
    bucket_id = 'case-media'
    and public.is_org_member(((storage.foldername(name))[1])::uuid)
  );
