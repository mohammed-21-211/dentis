import { useCallback, useEffect, useState } from "react";
import { Loader2, Users, CalendarCheck, Settings2, LayoutGrid, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { supabase, clinicDb } from "@/lib/supabase";
import { ORGANIZATION_ID } from "@/lib/organization";
import {
  appointmentStatusAr,
  formatDateAr,
  formatTimeAr,
  formatPrice,
  trimSeconds,
} from "@/lib/utils";
import { serviceSchema } from "@/lib/validations";
import { WEEKDAYS_AR } from "@/types";
import type {
  AppointmentWithRelations,
  ClinicHour,
  Profile,
  Service,
} from "@/types";
import { DashboardLayout } from "@/components/dashboard/DashboardLayout";
import { PatientDetail } from "@/components/doctor/PatientDetail";
import { CaseStudiesManager } from "@/components/doctor/CaseStudiesManager";
import { ReviewsManager } from "@/components/doctor/ReviewsManager";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";

type Tab = "patients" | "appointments" | "clinic" | "content";

/**
 * ترجمة أخطاء الكتابة الشائعة إلى رسالة عربية قابلة للتنفيذ. مفيدة خصوصاً
 * لتمييز حالتَي 42501 (لهما نفس الرمز، تختلفان بالنص):
 *   - "permission denied for table ..." → صلاحيات جداول clinic غير ممنوحة.
 *   - "row-level security policy" → الحساب ليس عضواً في العيادة (كادر).
 */
function writeErrorAr(prefix: string, error: { message?: string } | null): string {
  const msg = (error?.message ?? "").toLowerCase();
  if (msg.includes("row-level security")) {
    return `${prefix}: حسابك ليس مُضافاً ككادر لهذه العيادة (organization_members).`;
  }
  if (msg.includes("permission denied")) {
    return `${prefix}: صلاحيات جداول clinic غير مكتملة — طبّق migration الصلاحيات 0008.`;
  }
  return error?.message ? `${prefix}: ${error.message}` : prefix;
}

/** ساعات العمل الافتراضية عند تفعيل يوم جديد (٩ صباحاً – ٥ مساءً). */
const DEFAULT_OPEN = "09:00";
const DEFAULT_CLOSE = "17:00";

export default function DoctorDashboard() {
  const [tab, setTab] = useState<Tab>("patients");

  const nav = (
    <div className="flex gap-1 rounded-lg bg-muted p-1">
      <TabButton active={tab === "patients"} onClick={() => setTab("patients")} icon={Users}>
        المرضى
      </TabButton>
      <TabButton
        active={tab === "appointments"}
        onClick={() => setTab("appointments")}
        icon={CalendarCheck}
      >
        المواعيد
      </TabButton>
      <TabButton active={tab === "clinic"} onClick={() => setTab("clinic")} icon={Settings2}>
        إدارة العيادة
      </TabButton>
      <TabButton active={tab === "content"} onClick={() => setTab("content")} icon={LayoutGrid}>
        محتوى الموقع
      </TabButton>
    </div>
  );

  return (
    <DashboardLayout title="لوحة تحكم الطبيب" nav={nav}>
      {tab === "patients" && <PatientsTab />}
      {tab === "appointments" && <AppointmentsTab />}
      {tab === "clinic" && <ClinicTab />}
      {tab === "content" && (
        <div className="grid gap-6 lg:grid-cols-2">
          <CaseStudiesManager />
          <ReviewsManager />
        </div>
      )}
    </DashboardLayout>
  );
}

function TabButton({
  active,
  onClick,
  icon: Icon,
  children,
}: {
  active: boolean;
  onClick: () => void;
  icon: React.ComponentType<{ className?: string }>;
  children: React.ReactNode;
}) {
  return (
    <button
      onClick={onClick}
      className={`flex items-center gap-1.5 rounded-md px-3 py-1.5 text-sm font-medium transition-colors ${
        active
          ? "bg-background text-foreground shadow-sm"
          : "text-muted-foreground hover:text-foreground"
      }`}
    >
      <Icon className="size-4" />
      {children}
    </button>
  );
}

/* ------------------------------- المرضى ------------------------------- */
/**
 * "مريض" لم يعد دوراً مخزَّناً على profiles — يُشتق من وجود موعد واحد على
 * الأقل مع هذه العيادة (organization_id) في clinic.appointments. هذا يطابق
 * النموذج الجديد: المريض ليس عضواً في organization_members، وعلاقته بالعيادة
 * تُعرَّف حصراً عبر بيانات المواعيد/السجلات، وليس عبر عمود دور.
 */
function PatientsTab() {
  const [patients, setPatients] = useState<Profile[]>([]);
  const [loading, setLoading] = useState(true);
  const [selected, setSelected] = useState<Profile | null>(null);

  useEffect(() => {
    (async () => {
      const { data: apptRows } = await clinicDb
        .from("appointments")
        .select("patient_id")
        .eq("organization_id", ORGANIZATION_ID);

      const patientIds = Array.from(
        new Set(((apptRows as { patient_id: string }[]) ?? []).map((r) => r.patient_id)),
      );

      if (patientIds.length === 0) {
        setPatients([]);
        setLoading(false);
        return;
      }

      const { data: profiles } = await supabase
        .from("profiles")
        .select("*")
        .in("id", patientIds)
        .order("created_at", { ascending: false });

      setPatients((profiles as Profile[]) ?? []);
      setLoading(false);
    })();
  }, []);

  if (loading)
    return (
      <div className="flex justify-center py-20">
        <Loader2 className="size-8 animate-spin text-primary" />
      </div>
    );

  return (
    <>
      <Card>
        <CardHeader>
          <CardTitle>جميع المرضى ({patients.length})</CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          <div className="overflow-x-auto">
            <table className="w-full text-right text-sm">
              <thead className="border-b border-border text-muted-foreground">
                <tr>
                  <th className="p-4 font-medium">الاسم</th>
                  <th className="p-4 font-medium">رقم الهاتف</th>
                  <th className="p-4 font-medium">تاريخ التسجيل</th>
                  <th className="p-4 font-medium"></th>
                </tr>
              </thead>
              <tbody>
                {patients.length === 0 ? (
                  <tr>
                    <td colSpan={4} className="p-8 text-center text-muted-foreground">
                      لا يوجد مرضى مسجّلون بعد.
                    </td>
                  </tr>
                ) : (
                  patients.map((p) => (
                    <tr
                      key={p.id}
                      onClick={() => setSelected(p)}
                      className="cursor-pointer border-b border-border/60 transition-colors hover:bg-accent/30"
                    >
                      <td className="p-4 font-medium">{p.full_name}</td>
                      <td className="p-4 text-muted-foreground" dir="ltr">
                        {p.phone ?? "—"}
                      </td>
                      <td className="p-4 text-muted-foreground">
                        {formatDateAr(p.created_at)}
                      </td>
                      <td className="p-4 text-primary">عرض الملف ←</td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </CardContent>
      </Card>
      {selected && (
        <PatientDetail patient={selected} onClose={() => setSelected(null)} />
      )}
    </>
  );
}

/* ------------------------------ المواعيد ------------------------------ */
function AppointmentsTab() {
  const [appointments, setAppointments] = useState<AppointmentWithRelations[]>([]);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    // ملاحظة: لا نُضمّن "profiles" داخل نفس الاستعلام (embedding) لأن
    // appointments أصبح في schema "clinic" وprofiles في "public" — PostgREST
    // لا يدعم تضمين موارد عبر schemas مختلفة. نجلب الملفات الشخصية بطلب
    // منفصل وندمجها يدوياً بدل الاعتماد على تضمين قد يفشل بصمت.
    const { data } = await clinicDb
      .from("appointments")
      .select("*, service:services(id,name,duration,price)")
      .eq("organization_id", ORGANIZATION_ID)
      .order("appointment_date", { ascending: true });

    const rows = (data as Omit<AppointmentWithRelations, "patient">[]) ?? [];
    const patientIds = Array.from(new Set(rows.map((r) => r.patient_id)));

    let profileMap = new Map<string, Pick<Profile, "id" | "full_name" | "phone">>();
    if (patientIds.length > 0) {
      const { data: profiles } = await supabase
        .from("profiles")
        .select("id, full_name, phone")
        .in("id", patientIds);
      profileMap = new Map(
        ((profiles as Pick<Profile, "id" | "full_name" | "phone">[]) ?? []).map((p) => [p.id, p]),
      );
    }

    setAppointments(
      rows.map((r) => ({ ...r, patient: profileMap.get(r.patient_id) ?? null })),
    );
    setLoading(false);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  async function setStatus(id: string, status: "confirmed" | "cancelled") {
    const patch: Record<string, unknown> = { status };
    if (status === "cancelled") patch.cancellation_reason = "أُلغي من قبل العيادة";
    const { error } = await clinicDb.from("appointments").update(patch).eq("id", id);
    if (error) {
      toast.error("تعذّر تحديث الموعد");
      return;
    }
    toast.success(status === "confirmed" ? "تم تأكيد الموعد" : "تم إلغاء الموعد");
    load();
  }

  if (loading)
    return (
      <div className="flex justify-center py-20">
        <Loader2 className="size-8 animate-spin text-primary" />
      </div>
    );

  return (
    <Card>
      <CardHeader>
        <CardTitle>كل المواعيد</CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        {appointments.length === 0 ? (
          <p className="py-6 text-center text-muted-foreground">لا توجد مواعيد.</p>
        ) : (
          appointments.map((a) => (
            <div
              key={a.id}
              className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-border p-4"
            >
              <div className="space-y-1">
                <p className="font-semibold">
                  {a.patient?.full_name}{" "}
                  <span className="font-normal text-muted-foreground">
                    — {a.service?.name}
                  </span>
                </p>
                <p className="text-sm text-muted-foreground">
                  {formatDateAr(a.appointment_date)} — {formatTimeAr(a.start_time)}
                </p>
              </div>
              <div className="flex items-center gap-2">
                <Badge
                  variant={
                    a.status === "confirmed"
                      ? "success"
                      : a.status === "cancelled"
                        ? "destructive"
                        : "warning"
                  }
                >
                  {appointmentStatusAr(a.status)}
                </Badge>
                {a.status === "pending" && (
                  <>
                    <Button size="sm" variant="success" onClick={() => setStatus(a.id, "confirmed")}>
                      تأكيد
                    </Button>
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => setStatus(a.id, "cancelled")}
                    >
                      رفض
                    </Button>
                  </>
                )}
              </div>
            </div>
          ))
        )}
      </CardContent>
    </Card>
  );
}

/* --------------------------- إدارة العيادة --------------------------- */
function ClinicTab() {
  const [services, setServices] = useState<Service[]>([]);
  const [hours, setHours] = useState<ClinicHour[]>([]);
  const [name, setName] = useState("");
  const [duration, setDuration] = useState("30");
  const [price, setPrice] = useState("100");

  const load = useCallback(async () => {
    const [{ data: svc }, { data: hrs }] = await Promise.all([
      clinicDb.from("services").select("*").eq("organization_id", ORGANIZATION_ID).order("name"),
      clinicDb
        .from("clinic_hours")
        .select("*")
        .eq("organization_id", ORGANIZATION_ID)
        .order("day_of_week"),
    ]);
    setServices((svc as Service[]) ?? []);
    setHours((hrs as ClinicHour[]) ?? []);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  async function addService() {
    const parsed = serviceSchema.safeParse({ name, duration, price, description: "" });
    if (!parsed.success) {
      toast.error(parsed.error.issues[0]?.message ?? "تحقق من البيانات");
      return;
    }
    const { error } = await clinicDb.from("services").insert({
      organization_id: ORGANIZATION_ID,
      name: parsed.data.name,
      duration: parsed.data.duration,
      price: parsed.data.price,
    });
    if (error) {
      toast.error(writeErrorAr("تعذّر إضافة الخدمة", error));
      return;
    }
    toast.success("تمت إضافة الخدمة");
    setName("");
    load();
  }

  async function toggleService(s: Service) {
    const { error } = await clinicDb
      .from("services")
      .update({ is_active: !s.is_active })
      .eq("id", s.id);
    if (error) {
      toast.error(writeErrorAr("تعذّر تحديث الخدمة", error));
      return;
    }
    load();
  }

  async function deleteService(s: Service) {
    if (!window.confirm(`حذف خدمة "${s.name}" نهائياً؟`)) return;
    const { error } = await clinicDb.from("services").delete().eq("id", s.id);
    if (error) {
      // 23503 = مفتاح خارجي: الخدمة مرتبطة بمواعيد (appointments.service_id ON DELETE RESTRICT)
      if (error.code === "23503") {
        toast.error("لا يمكن حذف خدمة مرتبطة بمواعيد — عطّلها بدلاً من الحذف.");
      } else {
        toast.error(writeErrorAr("تعذّر حذف الخدمة", error));
      }
      return;
    }
    toast.success("تم حذف الخدمة");
    load();
  }

  // ساعات العمل مفهرسة حسب اليوم (0=الأحد .. 6=السبت). يوم بلا صفّ = مغلق
  // في محرّك المواعيد، لذا نعرض الأيام السبعة دائماً وننشئ الصفّ عند أول تعديل.
  const hoursByDay = new Map(hours.map((h) => [h.day_of_week, h]));

  type HourPatch = Partial<Pick<ClinicHour, "start_time" | "end_time" | "is_closed">>;

  /** إنشاء صفّ اليوم إن لم يوجد، أو تعديله — عبر upsert على (organization_id, day_of_week). */
  async function upsertHour(day: number, patch: HourPatch) {
    const existing = hoursByDay.get(day);
    const base = existing
      ? {
          start_time: trimSeconds(existing.start_time),
          end_time: trimSeconds(existing.end_time),
          is_closed: existing.is_closed,
        }
      : { start_time: DEFAULT_OPEN, end_time: DEFAULT_CLOSE, is_closed: false };
    const { error } = await clinicDb
      .from("clinic_hours")
      .upsert(
        { organization_id: ORGANIZATION_ID, day_of_week: day, ...base, ...patch },
        { onConflict: "organization_id,day_of_week" },
      );
    if (error) {
      toast.error(writeErrorAr("تعذّر حفظ ساعات العمل", error));
      return;
    }
    load();
  }

  /** تهيئة كل الأيام غير المحدّدة كأيام عمل افتراضية (٩ص–٥م) بضغطة واحدة. */
  async function seedWeek() {
    const rows = WEEKDAYS_AR.map((_, day) => day)
      .filter((day) => !hoursByDay.has(day))
      .map((day) => ({
        organization_id: ORGANIZATION_ID,
        day_of_week: day,
        start_time: DEFAULT_OPEN,
        end_time: DEFAULT_CLOSE,
        is_closed: false,
      }));
    if (rows.length === 0) return;
    const { error } = await clinicDb
      .from("clinic_hours")
      .upsert(rows, { onConflict: "organization_id,day_of_week" });
    if (error) {
      toast.error(writeErrorAr("تعذّر تهيئة أيام العمل", error));
      return;
    }
    toast.success("تم تفعيل أيام الأسبوع");
    load();
  }

  return (
    <div className="grid gap-6 lg:grid-cols-2">
      {/* الخدمات */}
      <Card>
        <CardHeader>
          <CardTitle>الخدمات (أسباب الحجز)</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid grid-cols-2 gap-2">
            <div className="col-span-2 space-y-1">
              <Label htmlFor="svc-name">اسم الخدمة</Label>
              <Input
                id="svc-name"
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="مثال: حشو الأسنان"
              />
            </div>
            <div className="space-y-1">
              <Label htmlFor="svc-dur">المدة (دقيقة)</Label>
              <Input
                id="svc-dur"
                type="number"
                value={duration}
                onChange={(e) => setDuration(e.target.value)}
              />
            </div>
            <div className="space-y-1">
              <Label htmlFor="svc-price">السعر</Label>
              <Input
                id="svc-price"
                type="number"
                value={price}
                onChange={(e) => setPrice(e.target.value)}
              />
            </div>
          </div>
          <Button onClick={addService} className="w-full">
            إضافة خدمة
          </Button>

          <div className="space-y-2 pt-2">
            {services.map((s) => (
              <div
                key={s.id}
                className="flex items-center justify-between rounded-lg border border-border p-3 text-sm"
              >
                <div>
                  <p className="font-medium">{s.name}</p>
                  <p className="text-xs text-muted-foreground">
                    {s.duration} دقيقة — {formatPrice(s.price)}
                  </p>
                </div>
                <div className="flex items-center gap-1">
                  <Button
                    size="sm"
                    variant={s.is_active ? "outline" : "secondary"}
                    onClick={() => toggleService(s)}
                  >
                    {s.is_active ? "مفعّلة" : "معطّلة"}
                  </Button>
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={() => deleteService(s)}
                    className="text-destructive hover:text-destructive"
                    aria-label={`حذف ${s.name}`}
                  >
                    <Trash2 className="size-4" />
                  </Button>
                </div>
              </div>
            ))}
          </div>
        </CardContent>
      </Card>

      {/* ساعات العمل */}
      <Card>
        <CardHeader className="flex flex-row items-center justify-between gap-2 space-y-0">
          <CardTitle>ساعات العمل الأسبوعية</CardTitle>
          {hoursByDay.size < WEEKDAYS_AR.length && (
            <Button size="sm" variant="outline" onClick={seedWeek}>
              فتح كل الأيام
            </Button>
          )}
        </CardHeader>
        <CardContent className="space-y-2">
          {WEEKDAYS_AR.map((label, day) => {
            const h = hoursByDay.get(day);
            const notSet = !h; // بلا صفّ = مغلق في محرّك المواعيد
            const isClosed = h?.is_closed ?? true;
            return (
              <div
                key={day}
                className="flex items-center gap-2 rounded-lg border border-border p-2 text-sm"
              >
                <span className="w-16 font-medium">{label}</span>
                {isClosed ? (
                  <span className="flex-1 text-center text-destructive">
                    {notSet ? "غير محدّدة" : "مغلق"}
                  </span>
                ) : (
                  <div className="flex flex-1 items-center justify-center gap-2">
                    <Input
                      type="time"
                      value={trimSeconds(h!.start_time)}
                      onChange={(e) => upsertHour(day, { start_time: e.target.value })}
                      className="h-8 w-28"
                    />
                    <span className="text-muted-foreground">إلى</span>
                    <Input
                      type="time"
                      value={trimSeconds(h!.end_time)}
                      onChange={(e) => upsertHour(day, { end_time: e.target.value })}
                      className="h-8 w-28"
                    />
                  </div>
                )}
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={() => upsertHour(day, { is_closed: !isClosed })}
                >
                  {isClosed ? "فتح" : "إغلاق"}
                </Button>
              </div>
            );
          })}
        </CardContent>
      </Card>
    </div>
  );
}
