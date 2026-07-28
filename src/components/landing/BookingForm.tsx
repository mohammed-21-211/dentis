import { useEffect, useMemo, useState } from "react";
import { motion } from "framer-motion";
import { CalendarDays, Clock, Loader2, Stethoscope } from "lucide-react";
import { toast } from "sonner";
import { supabase, clinicDb } from "@/lib/supabase";
import { ORGANIZATION_ID } from "@/lib/organization";
import { useAuth } from "@/context/AuthContext";
import { useAvailableSlots } from "@/hooks/useAvailableSlots";
import { bookingSchema } from "@/lib/validations";
import { formatTimeAr } from "@/lib/utils";
import type { Service } from "@/types";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Label } from "@/components/ui/label";

/** الحد الأدنى لتاريخ الحجز = اليوم (بصيغة YYYY-MM-DD) */
function todayISO() {
  return new Date().toISOString().slice(0, 10);
}

export function BookingForm() {
  const { user } = useAuth();
  const [services, setServices] = useState<Service[]>([]);
  const [serviceId, setServiceId] = useState<string>("");
  const [date, setDate] = useState<string>(todayISO());
  const [selectedTime, setSelectedTime] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const selectedService = useMemo(
    () => services.find((s) => s.id === serviceId) ?? null,
    [services, serviceId],
  );

  const { slots, loading, closed } = useAvailableSlots(
    serviceId ? date : null,
    selectedService,
  );

  useEffect(() => {
    clinicDb
      .from("services")
      .select("*")
      .eq("organization_id", ORGANIZATION_ID)
      .eq("is_active", true)
      .order("name")
      .then(({ data }) => setServices((data as Service[]) ?? []));
  }, []);

  // إعادة تعيين الوقت المختار عند تغيّر اليوم/الخدمة
  useEffect(() => setSelectedTime(null), [date, serviceId]);

  async function handleSubmit() {
    if (!user) {
      toast.error("يرجى تسجيل الدخول أولاً لإتمام الحجز");
      return;
    }
    const parsed = bookingSchema.safeParse({
      serviceId,
      date,
      startTime: selectedTime ?? "",
    });
    if (!parsed.success) {
      toast.error(parsed.error.issues[0]?.message ?? "بيانات الحجز غير مكتملة");
      return;
    }

    setSubmitting(true);
    // الحجز الذرّي عبر دالة الخادم — الضمان النهائي ضد التزامن
    const { error } = await supabase.rpc("book_appointment", {
      p_service_id: serviceId,
      p_date: date,
      p_start_time: selectedTime,
      p_organization_id: ORGANIZATION_ID,
    });
    setSubmitting(false);

    if (error) {
      toast.error(error.message || "تعذّر إتمام الحجز");
      return;
    }
    toast.success("تم حجز موعدك بنجاح! ستصلك إشعارات التذكير قبل الموعد.");
    setSelectedTime(null);
  }

  return (
    <Card className="overflow-hidden shadow-lg">
      <CardHeader className="bg-accent/40">
        <CardTitle className="flex items-center gap-2">
          <Stethoscope className="size-5 text-primary" />
          احجز موعدك الآن
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-5 pt-6">
        {/* اختيار الخدمة */}
        <div className="space-y-2">
          <Label htmlFor="service">سبب الزيارة (الخدمة)</Label>
          <select
            id="service"
            value={serviceId}
            onChange={(e) => setServiceId(e.target.value)}
            className="flex h-10 w-full rounded-lg border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          >
            <option value="">اختر الخدمة...</option>
            {services.map((s) => (
              <option key={s.id} value={s.id}>
                {s.name} — {s.duration} دقيقة
              </option>
            ))}
          </select>
        </div>

        {/* اختيار التاريخ */}
        <div className="space-y-2">
          <Label htmlFor="date" className="flex items-center gap-1.5">
            <CalendarDays className="size-4 text-muted-foreground" />
            التاريخ
          </Label>
          <input
            id="date"
            type="date"
            min={todayISO()}
            value={date}
            onChange={(e) => setDate(e.target.value)}
            className="flex h-10 w-full rounded-lg border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          />
        </div>

        {/* شبكة الأوقات المتاحة */}
        <div className="space-y-2">
          <Label className="flex items-center gap-1.5">
            <Clock className="size-4 text-muted-foreground" />
            الأوقات المتاحة
          </Label>

          {!serviceId ? (
            <p className="rounded-lg bg-muted px-3 py-6 text-center text-sm text-muted-foreground">
              اختر الخدمة لعرض الأوقات المتاحة
            </p>
          ) : loading ? (
            <div className="flex items-center justify-center py-6">
              <Loader2 className="size-5 animate-spin text-primary" />
            </div>
          ) : closed ? (
            <p className="rounded-lg bg-destructive/10 px-3 py-6 text-center text-sm text-destructive">
              العيادة مغلقة في هذا اليوم، يرجى اختيار يوم آخر
            </p>
          ) : slots.length === 0 ? (
            <p className="rounded-lg bg-muted px-3 py-6 text-center text-sm text-muted-foreground">
              لا توجد فترات متاحة لهذه المدة في هذا اليوم
            </p>
          ) : (
            <div className="grid grid-cols-3 gap-2 sm:grid-cols-4">
              {slots.map((slot) => (
                <motion.button
                  key={slot.time}
                  type="button"
                  whileTap={{ scale: 0.95 }}
                  disabled={!slot.available}
                  onClick={() => setSelectedTime(slot.time)}
                  className={[
                    "rounded-lg border px-2 py-2 text-sm font-medium transition-colors",
                    !slot.available
                      ? "cursor-not-allowed border-border bg-muted text-muted-foreground line-through"
                      : selectedTime === slot.time
                        ? "border-primary bg-primary text-primary-foreground"
                        : "border-input bg-background hover:border-primary hover:bg-accent",
                  ].join(" ")}
                >
                  {formatTimeAr(slot.time)}
                </motion.button>
              ))}
            </div>
          )}
        </div>

        <Button
          className="w-full"
          size="lg"
          disabled={submitting || !selectedTime}
          onClick={handleSubmit}
        >
          {submitting && <Loader2 className="size-4 animate-spin" />}
          {user ? "تأكيد الحجز" : "سجّل الدخول للحجز"}
        </Button>
      </CardContent>
    </Card>
  );
}
