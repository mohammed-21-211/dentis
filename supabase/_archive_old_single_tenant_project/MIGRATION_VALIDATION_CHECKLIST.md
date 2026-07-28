# قائمة تحقق نهائية — هجرة عيادة الأسنان إلى Multi-Tenant (organization_id + schema clinic)

> هذه الوثيقة **ليست migration** ولا تحتوي أي SQL يُنفَّذ تلقائياً. كل استعلام
> مذكور هنا هو استعلام **قراءة فقط (Read-only)** يُستخدم يدوياً للتحقق، وليس
> جزءاً من أي ملف `supabase/migrations/*.sql`. تُعتبر عملية النقل (Migrations
> 0003–0011) مكتملة فقط بعد اجتياز كل بند أدناه فعلياً على البيئة المستهدفة.

---

## 1) قاعدة البيانات (Database)

### 1.1 الجداول الثمانية داخل `clinic`
```sql
select table_schema, table_name
from information_schema.tables
where table_name in (
  'services', 'clinic_hours', 'appointments', 'medical_records',
  'notifications', 'case_studies', 'reviews', 'appointment_reminders'
)
order by table_name;
```
**متوقَّع:** `table_schema = 'clinic'` لكل الثمانية، ولا وجود لأي منها في `public`.

### 1.2 سلامة الـ Foreign Keys
```sql
select conname, conrelid::regclass as table_name,
       confrelid::regclass as references_table, convalidated
from pg_constraint
where contype = 'f'
  and connamespace = 'clinic'::regnamespace
order by conrelid::regclass::text;
```
**تحقق من:**
- كل الـ 8 قيود `*_organization_id_fkey` (من 0004) موجودة وتشير إلى `public.organizations`.
- `appointments_patient_id_fkey`, `medical_records_patient_id_fkey` تشير إلى `public.profiles` (عبر schema).
- `appointments_service_id_fkey`, `appointment_reminders_appointment_id_fkey` تشير إلى جداول داخل `clinic`.
- `convalidated = true` على الكل (لا قيود معلَّقة/غير مُتحقَّق منها).

### 1.3 القيود الفريدة المعدَّلة (من 0007)
```sql
select conname, conrelid::regclass, pg_get_constraintdef(oid)
from pg_constraint
where conname in (
  'clinic_hours_organization_id_day_of_week_key'
) or conname = 'appointments_unique_active_slot';
```
تحقق يدوياً أيضاً من الفهرس الجزئي:
```sql
select indexname, indexdef from pg_indexes
where indexname = 'appointments_unique_active_slot' and schemaname = 'clinic';
```
**متوقَّع:** كلاهما يتضمّن `organization_id` كعمود أول، ولا وجود لأي نسخة قديمة عالمية.

### 1.4 سياسات RLS موجودة ومفعَّلة
```sql
select schemaname, tablename, policyname, cmd
from pg_policies
where schemaname = 'clinic'
order by tablename, policyname;

select relname, relrowsecurity
from pg_class
where relnamespace = 'clinic'::regnamespace and relkind = 'r';
```
**متوقَّع:** `relrowsecurity = true` على كل الجداول الثمانية، والسياسات الـ 16 (9 معدَّلة + 7 بلا تغيير) كلها موجودة تحت `schemaname = 'clinic'` وليس `public`.

### 1.5 الدوال الأربع تشير إلى `clinic.*`
```sql
select proname, prosrc
from pg_proc
where proname in (
  'book_appointment', 'notify_on_appointment_change',
  'notify_on_medical_record', 'dispatch_appointment_reminders'
);
```
**تحقق يدوي من النص المُعاد:** يحتوي `clinic.` قبل كل جدول من الثمانية، ولا يحتوي أي `public.services`/`public.appointments`/... متبقٍّ (باستثناء `public.profiles` و`public.organization_members` المقصودتين).

### 1.6 `is_org_member()` و`current_organization_id()` تعملان كما هو متوقَّع
يُنفَّذ هذا كمستخدم مصادَق تجريبي (ليس service_role):
```sql
select public.current_organization_id();          -- يجب أن تُعيد organization_id الصحيح
select public.is_org_member('<uuid منظمة حقيقية>'); -- true لعضو فعلي، false لغير عضو
```
**تحقق إضافي:** استدعاء `is_org_member()` من مستخدم **مريض غير عضو** يُعيد `false` بلا خطأ (لا استثناء، لا NULL غير متوقَّع).

---

## 2) Supabase (تشغيلي — خارج SQL بالكامل)

- [ ] **إضافة `clinic` إلى Exposed Schemas** (Project Settings → Data API → Exposed schemas) — بدون هذه الخطوة، كل ما يلي سيفشل.
- [ ] **التحقق من عمل REST API على `clinic`**: طلب مباشر (مثلاً عبر `curl` بترويسة `Accept-Profile: clinic`) على أحد الجداول (مثل `services`) والتأكد من إرجاع بيانات فعلية بدل خطأ 404/schema not found.
- [ ] **⚠️ اختبار حرج: تضمين الموارد عبر Schemas مختلفة (PostgREST Embedding)**
  الاستعلام الحالي في `DoctorDashboard.tsx` يستخدم:
  `select("*, service:services(...), patient:profiles!appointments_patient_id_fkey(...)")`
  بعد النقل، `appointments`/`services` في `clinic` بينما `profiles` في `public`.
  **PostgREST قد لا يدعم تضمين مورد من schema مختلفة تلقائياً بنفس هذه الصياغة.**
  يجب اختبار هذا الاستعلام تحديداً فعلياً بعد التفعيل؛ إن فشل، الحل البديل هو تقسيمه
  إلى استعلامين منفصلين (جلب `patient_id` ثم استعلام `profiles` بشكل مستقل)، وهذا
  تعديل كود إضافي غير مشمول في migrations الحالية.
- [ ] **التحقق من عمل Realtime**: فتح اشتراك `postgres_changes` على `clinic.notifications` و`clinic.appointments` والتأكد من وصول أحداث فعلية بعد إدراج/تحديث صف تجريبي.
- [ ] **التحقق من عمل RPC**: استدعاء `book_appointment` (يبقى في `public`، غير متأثر بـ Exposed Schemas) والتأكد من نجاح الحجز فعلياً بمعامله الرابع الجديد.

---

## 3) الواجهة الأمامية (Frontend)

### 3.1 تحديث كل استدعاء `.from(...)` ليصبح `supabase.schema("clinic").from(...)`
قائمة كل موقع فعلي في الكود الحالي يحتاج هذا التحديث:

| الملف | الأسطر (تقريبية) | الجدول |
|---|---|---|
| `src/components/landing/BookingForm.tsx` | 40 | `services` |
| `src/components/landing/ReviewForm.tsx` | 37 | `reviews` |
| `src/components/doctor/ReviewsManager.tsx` | 18, 32, 46 | `reviews` |
| `src/components/doctor/CaseStudiesManager.tsx` | 29, 66, 86 | `case_studies` |
| `src/components/doctor/PatientDetail.tsx` | 66, 84, 97, 102, 147 | `medical_records`, `appointments` |
| `src/hooks/useNotifications.ts` | 21, 62, 69 | `notifications` |
| `src/hooks/useAvailableSlots.ts` | 55, 60 | `clinic_hours`, `appointments` |
| `src/pages/doctor/DoctorDashboard.tsx` | 183, 197, 283–284, 300, 315, 320 | `appointments`, `services`, `clinic_hours` |
| `src/pages/Landing.tsx` | 58, 63 | `case_studies`, `reviews` |
| `src/pages/patient/PatientDashboard.tsx` | 35, 40, 70 | `appointments`, `medical_records` |

**لا تُغيَّر** (تبقى `public` الافتراضية بلا `supabase.schema(...)`):
- `src/context/AuthContext.tsx:40` و`src/pages/auth/Login.tsx:34` (`profiles`).
- `src/lib/storage.ts` وكل استدعاءات `supabase.storage.from(...)` (Storage buckets ليست جزءاً من schema exposure، غير متأثرة أصلاً).

### 3.2 تحديث استدعاء `book_appointment`
`src/components/landing/BookingForm.tsx:67` — إضافة `p_organization_id` إلى جسم `supabase.rpc("book_appointment", {...})`. تحديد من أين يأتي هذا المعرّف في الواجهة (سياق العيادة الحالية/subdomain/اختيار) قرار منتج منفصل يجب حسمه قبل هذا التعديل تحديداً.

### 3.3 مراجعة أي منطق متبقٍّ يفترض عيادة واحدة عالمياً
- `src/context/AuthContext.tsx` (`isDoctor: profile?.role === "doctor"`): `profiles` الحقيقي (Backbone) لا يملك عمود `role` أصلاً — هذا السطر سيُعيد `false` دائماً أو يفشل. يحتاج إعادة تصميم لاحقاً ليعتمد على عضوية `organization_members` بدل `profile.role` — **خارج نطاق migrations SQL، تعديل كود منفصل**.
- `src/components/ProtectedRoute.tsx:28` (`profile?.role !== role`): نفس الاعتماد المكسور، يحتاج نفس إعادة التصميم.
- `src/types/database.ts` (`Profile.role`, `UserRole` enum): يجب تحديثها لتعكس أن `role` لم يعد موجوداً على `profiles` الفعلي.

> هذه البنود الثلاثة **ليست جزءاً من نقل قاعدة البيانات** لكنها ستُسبّب أعطالاً وظيفية في الواجهة فور تفعيل Exposed Schemas إن لم تُعالَج — يُنصح بمعالجتها في مرحلة عمل منفصلة قبل اعتبار المشروع "منتهياً" فعلياً من منظور المستخدم النهائي، حتى لو كانت خارج نطاق هذا التقرير التقني لقاعدة البيانات.

---

## 4) اختبارات وظيفية شاملة (End-to-End)

يجب تنفيذها على بيئة تحتوي **منظمتين حقيقيتين مختلفتين على الأقل** (وليس منظمة واحدة فقط)، لأن أي اختبار بمنظمة واحدة لا يكشف أخطاء العزل.

- [ ] **إنشاء موعد** عبر `book_appointment` بمنظمة A — ينجح، ويظهر فقط لأعضاء A.
- [ ] **تعديل حالة موعد** (تأكيد/إلغاء من طبيب في A) — يُنشئ إشعاراً لأعضاء A فقط، ولا يظهر لأي عضو في B.
- [ ] **إنشاء سجل طبي** لمريض في A — يُنشئ إشعاراً للمريض، ولا يظهر لطبيب في B حتى لو حاول الوصول المباشر (اختبار RLS فعلي، ليس فقط واجهة).
- [ ] **إرسال إشعار وقراءته** (`markAsRead`/`markAllAsRead`) — يعمل ضمن نفس المنظمة، ولا يتأثر بإشعارات منظمة أخرى لنفس المستخدم لو كان عضواً في الاثنتين.
- [ ] **تشغيل `dispatch_appointment_reminders`** يدوياً (`select public.dispatch_appointment_reminders();`) مع وجود مواعيد قريبة في A وB معاً — يُنشئ تذكيرات صحيحة النطاق لكل منظمة على حدة، بلا تسرّب.
- [ ] **اختبار العزل الصريح بين منظمتين (الأهم):**
  - عضو في A يحاول قراءة/تعديل `services`, `appointments`, `medical_records`, `case_studies`, `reviews` تابعة لـ B مباشرة (عبر طلب REST يدوي وليس فقط عبر الواجهة) → يجب أن يُرفض بالكامل (0 صفوف أو خطأ صلاحية، حسب نوع العملية).
  - مريض في A لا يظهر في قائمة "المرضى" التي يراها طبيب B (`DoctorDashboard.tsx` PatientsTab) — **ملاحظة:** هذا الاستعلام حالياً (`profiles where role='patient'`) لا يُصفَّى بعيادة إطلاقاً أصلاً (خارج نطاق migrations SQL، يحتاج إعادة تصميم في الكود لاحقاً — مرتبط ببند 3.3).
  - حجز في نفس التاريخ/الوقت مسموح لعيادتين مختلفتين (A وB) في آن واحد دون تعارض — تأكيد فعلي لعمل القيد الفريد الجديد من 0007.

---

## معيار الإتمام النهائي
النقل يُعتبر **مكتملاً** فقط عند تحقق **كل** بند في الأقسام 1–4 فعلياً على البيئة المستهدفة — وليس عند نجاح تطبيق ملفات SQL فقط. نجاح `supabase db push` بلا أخطاء **شرط ضروري غير كافٍ**.
