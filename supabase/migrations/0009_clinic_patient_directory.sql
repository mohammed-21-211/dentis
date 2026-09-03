-- =============================================================================
--  Migration 0009 — دليل مرضى العيادة لكادرها (clinic.org_patients)
--  clinic.org_patients() — SECURITY DEFINER, org-scoped patient directory
--
--  السبب (Root cause): public.profiles جدول Backbone مشترك، وسياسة RLS عليه
--  تسمح لكل مستخدم بقراءة ملفه الشخصي فقط. لذلك كادر العيادة لا يستطيع قراءة
--  ملفات مرضاه مباشرةً عبر profiles — فيظهر "سجل المرضى" وأسماء المرضى في
--  المواعيد فارغة رغم وجود المواعيد. كذلك رقم الهاتف يُخزَّن في
--  auth.users.raw_user_meta_data (يُلتقط عند التسجيل) وليس عموداً في profiles.
--
--  الحل: دالة SECURITY DEFINER داخل schema clinic تُرجِع ملفات المرضى الذين
--  لهم موعد أو سجل طبي في عيادة ينتمي إليها المتصل (public.is_org_member) —
--  مع الهاتف من الـ metadata. مقيّدة بالعضوية فلا تسرّب بيانات لغير الكادر،
--  ولا تلمس RLS جدول الـ Backbone المشترك (يبقى آمناً كما هو).
--
--  ملاحظة تعدّد العيادات: التصفية بـ is_org_member(organization_id) تضمن أن
--  المتصل يرى فقط مرضى العيادات التي هو عضو فيها، لا كل profiles في القاعدة.
--
--  قابلة لإعادة التشغيل (Idempotent): create or replace + grant.
-- =============================================================================

create or replace function clinic.org_patients()
returns table (
  id         uuid,
  full_name  text,
  phone      text,
  created_at timestamptz
)
language sql
security definer
set search_path = public
stable
as $$
  select p.id,
         p.full_name,
         u.raw_user_meta_data ->> 'phone' as phone,
         p.created_at
  from public.profiles p
  join auth.users u on u.id = p.id
  where p.id in (
    select a.patient_id
      from clinic.appointments a
     where public.is_org_member(a.organization_id)
    union
    select m.patient_id
      from clinic.medical_records m
     where public.is_org_member(m.organization_id)
  )
  order by p.created_at desc;
$$;

comment on function clinic.org_patients() is
  'دليل مرضى العيادة لكادرها: يُرجِع ملفات (id, full_name, phone, created_at) للمرضى الذين لهم موعد أو سجل طبي في عيادة ينتمي إليها المتصل. SECURITY DEFINER لتجاوز RLS جدول profiles المشترك بأمان، مقيَّد بـ public.is_org_member، والهاتف من auth metadata.';

grant execute on function clinic.org_patients() to authenticated;
