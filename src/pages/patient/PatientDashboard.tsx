import { useCallback, useEffect, useState } from "react";
import { CalendarClock, FileText, Loader2, XCircle } from "lucide-react";
import { toast } from "sonner";
import { clinicDb } from "@/lib/supabase";
import { ORGANIZATION_ID } from "@/lib/organization";
import { useAuth } from "@/context/AuthContext";
import { cancellationSchema } from "@/lib/validations";
import { appointmentStatusAr, formatDateAr, formatTimeAr } from "@/lib/utils";
import type { AppointmentWithRelations, MedicalRecord } from "@/types";
import { DashboardLayout } from "@/components/dashboard/DashboardLayout";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";

function statusVariant(status: string) {
  if (status === "confirmed") return "success" as const;
  if (status === "cancelled") return "destructive" as const;
  return "warning" as const;
}

export default function PatientDashboard() {
  const { user } = useAuth();
  const [appointments, setAppointments] = useState<AppointmentWithRelations[]>([]);
  const [records, setRecords] = useState<MedicalRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [cancelId, setCancelId] = useState<string | null>(null);
  const [reason, setReason] = useState("");
  const [submitting, setSubmitting] = useState(false);

  const load = useCallback(async () => {
    if (!user) return;
    setLoading(true);
    const [{ data: appts }, { data: recs }] = await Promise.all([
      clinicDb
        .from("appointments")
        .select("*, service:services(id,name,duration,price)")
        .eq("organization_id", ORGANIZATION_ID)
        .eq("patient_id", user.id)
        .order("appointment_date", { ascending: false }),
      clinicDb
        .from("medical_records")
        .select("*")
        .eq("organization_id", ORGANIZATION_ID)
        .eq("patient_id", user.id)
        .order("created_at", { ascending: false }),
    ]);
    setAppointments((appts as AppointmentWithRelations[]) ?? []);
    setRecords((recs as MedicalRecord[]) ?? []);
    setLoading(false);
  }, [user]);

  useEffect(() => {
    load();
  }, [load]);

  const now = new Date();
  const upcoming = appointments.filter(
    (a) => new Date(`${a.appointment_date}T${a.start_time}`) >= now && a.status !== "cancelled",
  );
  const past = appointments.filter(
    (a) => new Date(`${a.appointment_date}T${a.start_time}`) < now || a.status === "cancelled",
  );

  async function confirmCancel() {
    const parsed = cancellationSchema.safeParse({ reason });
    if (!parsed.success) {
      toast.error(parsed.error.issues[0]?.message ?? "سبب الإلغاء مطلوب");
      return;
    }
    setSubmitting(true);
    const { error } = await clinicDb
      .from("appointments")
      .update({ status: "cancelled", cancellation_reason: reason })
      .eq("id", cancelId);
    setSubmitting(false);
    if (error) {
      toast.error("تعذّر إلغاء الموعد");
      return;
    }
    toast.success("تم إلغاء الموعد");
    setCancelId(null);
    setReason("");
    load();
  }

  return (
    <DashboardLayout title="لوحة المريض">
      {loading ? (
        <div className="flex justify-center py-20">
          <Loader2 className="size-8 animate-spin text-primary" />
        </div>
      ) : (
        <div className="grid gap-6 lg:grid-cols-3">
          {/* المواعيد */}
          <div className="space-y-6 lg:col-span-2">
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <CalendarClock className="size-5 text-primary" />
                  المواعيد القادمة
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-3">
                {upcoming.length === 0 ? (
                  <p className="py-4 text-center text-sm text-muted-foreground">
                    لا توجد مواعيد قادمة. يمكنك الحجز من الصفحة الرئيسية.
                  </p>
                ) : (
                  upcoming.map((a) => (
                    <div
                      key={a.id}
                      className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-border p-4"
                    >
                      <div className="space-y-1">
                        <p className="font-semibold">{a.service?.name}</p>
                        <p className="text-sm text-muted-foreground">
                          {formatDateAr(a.appointment_date)} — {formatTimeAr(a.start_time)}
                        </p>
                      </div>
                      <div className="flex items-center gap-2">
                        <Badge variant={statusVariant(a.status)}>
                          {appointmentStatusAr(a.status)}
                        </Badge>
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => setCancelId(a.id)}
                          className="text-destructive hover:text-destructive"
                        >
                          <XCircle className="size-4" />
                          إلغاء
                        </Button>
                      </div>
                    </div>
                  ))
                )}
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle>المواعيد السابقة</CardTitle>
              </CardHeader>
              <CardContent className="space-y-3">
                {past.length === 0 ? (
                  <p className="py-4 text-center text-sm text-muted-foreground">
                    لا يوجد سجل مواعيد بعد.
                  </p>
                ) : (
                  past.map((a) => (
                    <div
                      key={a.id}
                      className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-border/60 bg-muted/30 p-4"
                    >
                      <div className="space-y-1">
                        <p className="font-medium">{a.service?.name}</p>
                        <p className="text-sm text-muted-foreground">
                          {formatDateAr(a.appointment_date)} — {formatTimeAr(a.start_time)}
                        </p>
                        {a.status === "cancelled" && a.cancellation_reason && (
                          <p className="text-xs text-destructive">
                            سبب الإلغاء: {a.cancellation_reason}
                          </p>
                        )}
                      </div>
                      <Badge variant={statusVariant(a.status)}>
                        {appointmentStatusAr(a.status)}
                      </Badge>
                    </div>
                  ))
                )}
              </CardContent>
            </Card>
          </div>

          {/* السجل الطبي (قراءة فقط) */}
          <Card className="h-fit">
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <FileText className="size-5 text-primary" />
                سجلي الطبي
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              {records.length === 0 ? (
                <p className="py-4 text-center text-sm text-muted-foreground">
                  لا توجد سجلات طبية بعد.
                </p>
              ) : (
                records.map((r) => (
                  <div key={r.id} className="rounded-lg border border-border p-4 text-sm">
                    <p className="mb-1 text-xs text-muted-foreground">
                      {formatDateAr(r.created_at)}
                    </p>
                    {r.doctor_notes && (
                      <p className="mb-1">
                        <span className="font-semibold">ملاحظات: </span>
                        {r.doctor_notes}
                      </p>
                    )}
                    {r.treatment_plan && (
                      <p className="mb-1">
                        <span className="font-semibold">خطة العلاج: </span>
                        {r.treatment_plan}
                      </p>
                    )}
                    {r.x_ray_url && (
                      <a
                        href={r.x_ray_url}
                        target="_blank"
                        rel="noreferrer"
                        className="text-primary hover:underline"
                      >
                        عرض صورة الأشعة
                      </a>
                    )}
                  </div>
                ))
              )}
            </CardContent>
          </Card>
        </div>
      )}

      {/* نافذة الإلغاء — سبب الإلغاء إلزامي */}
      {cancelId && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-foreground/40 p-4">
          <Card className="w-full max-w-md">
            <CardHeader>
              <CardTitle>إلغاء الموعد</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <p className="text-sm text-muted-foreground">
                يرجى كتابة سبب الإلغاء (إلزامي):
              </p>
              <Textarea
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                placeholder="مثال: ظرف طارئ، تعارض في الموعد..."
              />
              <div className="flex justify-end gap-2">
                <Button
                  variant="outline"
                  onClick={() => {
                    setCancelId(null);
                    setReason("");
                  }}
                >
                  تراجع
                </Button>
                <Button
                  variant="destructive"
                  onClick={confirmCancel}
                  disabled={submitting}
                >
                  {submitting && <Loader2 className="size-4 animate-spin" />}
                  تأكيد الإلغاء
                </Button>
              </div>
            </CardContent>
          </Card>
        </div>
      )}
    </DashboardLayout>
  );
}
