-- =============================================================================
--  Migration 0002 — التحقق من دوال الـ Backbone المشتركة (بلا إنشاء)
--  Dental Clinic Migration 0002 — verify (not create) shared backbone functions
--
--  النطاق (Scope): فحص وجود public.current_organization_id() وpublic.is_org_member(uuid)
--  فقط. هاتان الدالتان موجودتان بالفعل في هذا المشروع (أنشأهما على الأرجح
--  مشروع expense القائم مسبقاً) — لذلك هذه الـ migration لا تُنشئهما ولا
--  تُعدّل تعريفهما إطلاقاً، فقط تتأكد أن التوقيع المفترَض مطابق قبل أن تبني
--  عليه بقية سلسلة العيادة (RLS في 0006، الدوال في 0004).
--
--  إن فشل أي فحص أدناه، فهذا يعني أن الافتراض حول توقيع الدالتين غير دقيق —
--  التوقف هنا مقصود بدل الاستمرار وكتابة SQL يعتمد على افتراض خاطئ.
--
--  خارج النطاق عمداً: لا CREATE FUNCTION، لا CREATE OR REPLACE — لا لمس
--  لتعريف أي من الدالتين، لأنهما ملك مشترك للـ Backbone وقد يعتمد عليهما
--  تطبيق expense بسلوك محدَّد لا يجوز لنا تغييره.
--
--  قابلة لإعادة التشغيل (Idempotent): فحوصات قراءة فقط، لا تُغيّر أي حالة.
-- =============================================================================

do $$
begin
  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'current_organization_id'
      and p.pronargs = 0
  ) then
    raise exception
      'public.current_organization_id() غير موجودة بلا معاملات — توقّف وراجع الـ Backbone قبل المتابعة';
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'is_org_member'
      and p.pronargs = 1
      and p.proargtypes[0] = 'uuid'::regtype
  ) then
    raise exception
      'public.is_org_member(uuid) غير موجودة بهذا التوقيع — توقّف وراجع الـ Backbone قبل المتابعة';
  end if;
end $$;
