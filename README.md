<div dir="rtl">

# 🦷 نظام إدارة عيادة الأسنان (Dentis)

منصة **SaaS** احترافية متكاملة لإدارة عيادة أسنان، مصمَّمة حصرياً للسوق العربي بواجهة عربية كاملة ودعم أصيل للاتجاه من اليمين إلى اليسار (RTL)، بوضع فاتح أنيق فقط.

---

## 📑 الفهرس

1. [نظرة عامة وإعداد بيئة العمل](#1-نظرة-عامة-وإعداد-بيئة-العمل)
2. [مخطط قاعدة البيانات وأكواد SQL](#2-مخطط-قاعدة-البيانات-وأكواد-sql)
3. [إعداد الحماية (RLS) والتخزين (Storage)](#3-إعداد-الحماية-rls-والتخزين-storage)
4. [سجل الأخطاء وحلولها](#4-سجل-الأخطاء-وحلولها-resolved-bugs-log)

---

## 1. نظرة عامة وإعداد بيئة العمل

### التقنيات المستخدمة (Tech Stack)

| الطبقة | التقنية |
| --- | --- |
| الواجهة الأمامية | React 18 + Vite + TypeScript |
| التنسيق | Tailwind CSS (وضع فاتح فقط، بلا أنماط مضمّنة) |
| المكوّنات والحركة | Shadcn UI (Radix) + Framer Motion |
| الخطوط | Cairo / Tajawal (خطوط عربية من Google Fonts) |
| الخادم وقاعدة البيانات والمصادقة | Supabase (PostgreSQL + Auth + Storage + Realtime) |
| التحقق من المدخلات | Zod + React Hook Form |
| جلب البيانات | TanStack Query |
| التنبيهات | Sonner |

### المعمارية (هيكل المجلدات)

```
dentis/
├── public/
│   └── tooth.svg
├── supabase/
│   └── migrations/
│       ├── 0001_initial_schema.sql      # الجداول + RLS + Triggers + Storage + RPC
│       └── 0002_reminders_and_seed.sql  # منطق التذكيرات + بيانات أولية
├── src/
│   ├── components/
│   │   ├── ui/              # مكوّنات Shadcn الأساسية (button, card, input...)
│   │   ├── landing/         # نموذج الحجز
│   │   ├── dashboard/       # تخطيط اللوحة + جرس الإشعارات الحي
│   │   ├── doctor/          # تفاصيل المريض + رفع الأشعة
│   │   └── ProtectedRoute.tsx
│   ├── context/
│   │   └── AuthContext.tsx  # حالة المصادقة + الدور (طبيب/مريض)
│   ├── hooks/
│   │   ├── useAvailableSlots.ts  # محرّك حساب الفترات ومنع التعارض
│   │   └── useNotifications.ts   # بث الإشعارات الفوري (Realtime)
│   ├── lib/
│   │   ├── supabase.ts      # عميل Supabase
│   │   ├── validations.ts   # مخططات Zod برسائل عربية
│   │   └── utils.ts         # أدوات التنسيق (تاريخ/وقت/سعر عربي)
│   ├── pages/
│   │   ├── Landing.tsx
│   │   ├── auth/            # Login / Register
│   │   ├── doctor/          # لوحة الطبيب (مرضى/مواعيد/إدارة)
│   │   └── patient/         # لوحة المريض
│   ├── types/               # أنواع قاعدة البيانات
│   ├── App.tsx              # المسارات (Routing)
│   ├── main.tsx             # نقطة الدخول + المزوّدات
│   └── index.css            # متغيّرات الثيم (فاتح فقط) + قواعد RTL
└── ...ملفات الإعداد
```

### خطوات التشغيل

```bash
# 1) تثبيت الحزم
npm install

# 2) إعداد متغيّرات البيئة
cp .env.example .env
# املأ VITE_SUPABASE_URL و VITE_SUPABASE_ANON_KEY من لوحة Supabase

# 3) تطبيق هجرات قاعدة البيانات
#    أ) عبر Supabase CLI:
supabase link --project-ref <your-ref>
supabase db push
#    ب) أو يدوياً: انسخ محتوى ملفّي supabase/migrations/*.sql ونفّذهما
#       في SQL Editor داخل لوحة Supabase بالترتيب.

# 4) تشغيل بيئة التطوير
npm run dev          # http://localhost:5173

# 5) البناء للإنتاج
npm run build
```

### تعيين أول طبيب
يُسجَّل كل مستخدم جديد بدور `patient` افتراضياً. لترقية حساب إلى طبيب، نفّذ في SQL Editor:

```sql
update public.profiles set role = 'doctor' where id = '<USER_UUID>';
```

---

## 2. مخطط قاعدة البيانات وأكواد SQL

الكود الكامل في `supabase/migrations/`. ملخّص الجداول والعلاقات:

| الجدول | الوصف | العلاقات الأساسية (FK) |
| --- | --- | --- |
| `profiles` | ملفات المستخدمين والأدوار | `id → auth.users.id` |
| `services` | خدمات العيادة (أسباب الحجز) | — |
| `clinic_hours` | ساعات العمل لكل يوم (0=الأحد..6=السبت) | — |
| `appointments` | المواعيد وحالاتها | `patient_id → profiles`, `service_id → services` |
| `medical_records` | السجلات الطبية وصور الأشعة | `patient_id → profiles` |
| `notifications` | الإشعارات والتذكيرات | `user_id → profiles` |
| `case_studies` | معرض قبل/بعد | — |
| `reviews` | تقييمات المرضى | — |
| `appointment_reminders` | تتبّع التذكيرات المُرسلة (منع التكرار) | `appointment_id → appointments` |

### العلاقة المخطّطية (ERD مبسّط)

```
auth.users ─1:1─ profiles ─1:N─ appointments ─N:1─ services
                    │
                    ├─1:N─ medical_records
                    └─1:N─ notifications

appointments ─1:N─ appointment_reminders
```

### مقتطف: تعريف جدول المواعيد وضمان عدم التكرار

```sql
create table public.appointments (
  id                  uuid primary key default gen_random_uuid(),
  patient_id          uuid not null references public.profiles (id) on delete cascade,
  service_id          uuid not null references public.services (id) on delete restrict,
  appointment_date    date not null,
  start_time          time not null,
  status              appointment_status not null default 'pending',
  cancellation_reason text,
  created_at          timestamptz not null default now(),
  constraint appointments_not_in_past check (appointment_date >= current_date),
  constraint appointments_cancel_reason check (
    status <> 'cancelled'
    or (cancellation_reason is not null and char_length(trim(cancellation_reason)) >= 3)
  )
);

-- خط الدفاع الأخير ضد الحجز المزدوج:
create unique index appointments_unique_active_slot
  on public.appointments (appointment_date, start_time)
  where status <> 'cancelled';
```

> القيد `appointments_cancel_reason` يفرض على مستوى قاعدة البيانات أن **سبب الإلغاء إلزامي** عند الإلغاء — لا يمكن الالتفاف عليه من الواجهة.

---

## 3. إعداد الحماية (RLS) والتخزين (Storage)

### أمان مستوى الصف (Row Level Security)

تم تفعيل RLS على **جميع** الجداول. القاعدة المحورية هي الدالة `is_doctor()`:

```sql
create function public.is_doctor() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and role = 'doctor'
  );
$$;
```

ملخّص السياسات الأمنية:

| الجدول | المريض | الطبيب |
| --- | --- | --- |
| `profiles` | قراءة/تعديل ملفه فقط | قراءة جميع الملفات |
| `appointments` | قراءة/إنشاء/تعديل مواعيده فقط | قراءة وتعديل الكل |
| `medical_records` | **قراءة سجلّه فقط** (لا كتابة) | كتابة وقراءة الكل |
| `notifications` | إشعاراته فقط | إشعاراته فقط |
| `services` / `clinic_hours` | قراءة فقط | إدارة كاملة |
| `reviews` | قراءة المعتمد + إرسال تقييم | إدارة كاملة |

> **منع تسريب البيانات:** سياسة `medical_records_select_own_or_doctor` تضمن أن `patient_id = auth.uid()` — فلا يستطيع مريض رؤية ملف مريض آخر إطلاقاً.

### التخزين (Storage)

| الباكت | الخصوصية | الاستخدام |
| --- | --- | --- |
| `x-rays` | خاص (Private) | صور الأشعة — مسار `x-rays/{patient_id}/{file}` |
| `case-media` | عام (Public) | صور الحالات قبل/بعد |

سياسة صور الأشعة تربط مجلّد الملف بهوية المريض، فلا يقرأ المريض إلا ملفاته:

```sql
create policy "xray_patient_read_own" on storage.objects
  for select using (
    bucket_id = 'x-rays'
    and (public.is_doctor() or (storage.foldername(name))[1] = auth.uid()::text)
  );
```

الرفع والحذف في باكت الأشعة **مقصوران على الطبيب** فقط، والوصول للصور يتم عبر روابط موقّعة (Signed URLs).

### تفعيل البث الحي (Realtime)
الجدولان `notifications` و`appointments` مُضافان إلى `supabase_realtime` لتدفّق الإشعارات الفوري.

---

## 4. سجل الأخطاء وحلولها (Resolved Bugs Log)

### 🐛 BUG-01 — منع الحجز المزدوج (Double-Booking) تحت التزامن

**المشكلة:** التحقق من توفّر الفترة على الواجهة فقط يخلق *حالة سباق* (Race Condition) — مريضان يريان نفس الفترة متاحة ويحجزانها في نفس اللحظة.

**الحل المعماري متعدّد الطبقات:**
1. **الطبقة 1 (تجربة المستخدم):** `useAvailableSlots` يحسب الفترات المتعارضة بناءً على مدة كل خدمة ويُظهر المحجوز بوضوح.
2. **الطبقة 2 (التحقق الذرّي):** الحجز يتم حصرياً عبر دالة الخادم `book_appointment()` التي تتحقق من ساعات العمل والتعارض ثم تُدرج داخل معاملة واحدة مع `FOR UPDATE` لقفل الصفوف المتداخلة.
3. **الطبقة 3 (ضمان قاعدة البيانات):** فهرس فريد جزئي `appointments_unique_active_slot` يجعل إدراج فترة مكرّرة **مستحيلاً** فيزيائياً؛ وعند تصادم سباقين تُلتقط `unique_violation` وتُترجم إلى رسالة عربية واضحة.

النتيجة: حتى لو نجح طلبان متزامنان في تجاوز الطبقتين 1 و2، تضمن الطبقة 3 فوز واحد فقط.

---

### 🐛 BUG-02 — محاكاة منطق التذكيرات الدوري (Cron Simulation)

**المشكلة:** المتصفّح لا يمكنه تشغيل مهام مجدولة موثوقة لإرسال تذكيرات «قبل 24 ساعة» و«قبل ساعة».

**الحل:** نقل المنطق إلى الخادم عبر الدالة `dispatch_appointment_reminders()`:
- تفحص المواعيد القادمة وتُنشئ إشعار تذكير عندما يقع الموعد ضمن نافذة [23h, 24h] أو [0, 1h].
- جدول `appointment_reminders` يضمن **عدم تكرار** التذكير (Idempotency) لنفس الموعد/النوع.
- تُجدول عبر `pg_cron` كل 15 دقيقة:

```sql
select cron.schedule('dispatch-reminders', '*/15 * * * *',
  $$ select public.dispatch_appointment_reminders(); $$);
```

> يمكن بديلاً استدعاؤها من Supabase Scheduled Edge Function. التصميم يفصل «اكتشاف التذكير» عن «التسليم» لسهولة الاختبار.

---

### 🐛 BUG-03 — تعديلات التوافق الصارم مع العربية و RTL

**المشكلة:** الإعداد الافتراضي LTR يكسر محاذاة النماذج، والأيقونات، والعناصر النائبة (placeholders)، وحقول البريد/الهاتف.

**الحلول المطبّقة:**
- `dir="rtl"` و`lang="ar"` على عنصر `<html>` + `direction: rtl` في `index.css` على الجذر.
- حقول التقنية (البريد، الهاتف، الوقت) تُجبَر على `dir="ltr"` مع `text-left` لعرض صحيح للأرقام والرموز اللاتينية ضمن واجهة عربية.
- استبدال `left/right` الثابتة بمحاذاة منطقية تتبع اتجاه RTL، ومحاذاة العناصر النائبة لليمين عبر قاعدة CSS مخصّصة.
- تنسيق التواريخ/الأوقات/الأسعار بالعربية عبر `Intl` (`ar-SA`) بتقويم ميلادي.
- خطوط `Cairo/Tajawal` محمّلة مسبقاً (preconnect) لأداء أفضل ومظهر عربي أصيل.

---

### 🐛 BUG-04 — العلاقات المتداخلة في Supabase (Array vs Object)

**المشكلة:** استعلام `select("*, service:services(duration)")` قد يُعيد العلاقة كمصفوفة أو ككائن، مسبّباً خطأ تحويل أنواع في TypeScript.

**الحل:** تطبيع القيمة في `useAvailableSlots` عبر `Array.isArray(service) ? service[0] : service` قبل الاستخدام، مع نوع اتحادي يغطّي الحالتين.

---

### 🐛 BUG-05 — إنشاء الملف الشخصي تلقائياً بعد التسجيل

**المشكلة:** بعد `auth.signUp` لا يوجد صف في `profiles`، فتفشل قراءة الدور والتوجيه.

**الحل:** مُشغّل `on_auth_user_created` (SECURITY DEFINER) يُنشئ صف `profiles` تلقائياً من `raw_user_meta_data` (الاسم، الهاتف، الدور) فور إنشاء المستخدم في `auth.users`.

---

<div align="center">

صُمّم بعناية لخدمة عيادات الأسنان في العالم العربي 🦷

</div>

</div>
