-- =============================================================================
--  Migration 0005 — Backfill عمود organization_id
--  Dental Clinic Migration 0005 — organization_id backfill (data-only)
--
--  النطاق (Scope):
--    التعامل مع أي صفوف قائمة في الجداول السبعة (من 0004) لا تزال
--    organization_id فيها NULL.
--
--  القرار المعتمد (لا UUID ثابت داخل السكربت):
--    public.organizations فارغ حالياً بالكامل، ولا توجد أي وسيلة موثوقة
--    لتحديد "المنظمة الصحيحة" لأي صف يتيم قائم (مثل بيانات seed التجريبية
--    من 0002_reminders_and_seed.sql: خدمات/ساعات عمل/تقييمات/حالات افتراضية
--    لم تُربط يوماً بمنظمة حقيقية). لذلك لا يوجد "Backfill" فعلي ممكن هنا —
--    القرار المعتمد صراحةً: حذف أي صف بلا organization_id بدل تركه يتيماً
--    أو اختراع منظمة وهمية لربطه بها.
--
--  ترتيب الحذف مقصود: appointments تُحذف قبل services لأن
--  appointments.service_id يشير إلى services بقيد "on delete restrict"
--  (من 0001) — حذف services أولاً وهي لا تزال مُشاراً إليها من appointments
--  يتيمة سيفشل. appointment_reminders لا تُذكر صراحة هنا لأنها تُحذف تلقائياً
--  عبر "on delete cascade" الموجود أصلاً على appointment_id (من 0002) عند
--  حذف صف appointments المرتبط بها.
--
--  خارج النطاق عمداً (Explicitly out of scope):
--    - لا "not null" على organization_id (يأتي في migration لاحقة).
--    - لا فهارس جديدة، لا تعديل قيود UNIQUE، لا تعديل دوال/Trigger/RLS.
--    - لا نقل أي جدول إلى schema clinic.
--    - لا تعديل على 0002_reminders_and_seed.sql نفسها (يُترك لمرحلة تنظيف لاحقة).
--
--  قابلة لإعادة التشغيل (Idempotent): كل DELETE مشروط بـ
--  "where organization_id is null" — التشغيل الثاني لن يجد صفوفاً مطابقة.
--
--  ⚠️ حالة هذه الـ migration على قاعدة البيانات الحية الحالية (target DB):
--  بما أن كل بيانات الاختبار حُذفت مسبقاً يدوياً، فالجداول السبعة فارغة
--  الآن فعلياً — هذه الـ migration ستُنفَّذ كـ "no-op" (0 صف متأثر) عند
--  تطبيقها على هذه القاعدة تحديداً. هي مُبقاة رغم ذلك (وليست زائدة) لأن
--  0002_reminders_and_seed.sql لا يزال يُدرج بيانات seed غير مرتبطة بأي
--  منظمة (on conflict do nothing، بلا شرط)، وأي بيئة أخرى تُعيد تشغيل كل
--  الـ migrations من الصفر (بيئة CI، جهاز مطوّر جديد، أو supabase db reset)
--  ستُنتج تلك الصفوف اليتيمة من جديد. بدون هذه الخطوة، ستفشل Migration 0006
--  (فرض NOT NULL) في أي بيئة كهذه بسبب وجود صفوف NULL فعلية.
-- =============================================================================

delete from public.appointments      where organization_id is null;
delete from public.medical_records   where organization_id is null;
delete from public.notifications     where organization_id is null;
delete from public.services          where organization_id is null;
delete from public.clinic_hours      where organization_id is null;
delete from public.case_studies      where organization_id is null;
delete from public.reviews           where organization_id is null;
