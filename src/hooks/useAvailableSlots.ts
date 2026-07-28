import { useEffect, useState } from "react";
import { clinicDb } from "@/lib/supabase";
import { ORGANIZATION_ID } from "@/lib/organization";
import { addMinutes } from "@/lib/utils";
import type { Appointment, ClinicHour, Service, TimeSlot } from "@/types";

interface UseAvailableSlotsResult {
  slots: TimeSlot[];
  loading: boolean;
  closed: boolean; // العيادة مغلقة في هذا اليوم
  error: string | null;
}

const SLOT_STEP_MINUTES = 30; // دقّة شبكة الفترات

/**
 * محرّك حساب الفترات المتاحة — منطق منع الحجز المزدوج وساعات العمل.
 *
 * الخطوات:
 * 1) جلب ساعات العمل لليوم المختار (day_of_week = JS getDay).
 * 2) إن كانت العيادة مغلقة → لا فترات.
 * 3) توليد شبكة فترات من start_time إلى end_time مع مراعاة مدة الخدمة
 *    (بحيث لا تتجاوز الفترة + المدة وقت الإغلاق).
 * 4) جلب المواعيد غير الملغاة لهذا التاريخ وتعليم أي فترة متعارضة (تداخل
 *    زمني) بأنها غير متاحة.
 *
 * هذا التحقق على الواجهة لتجربة المستخدم؛ والضمان النهائي للتزامن في دالة
 * book_appointment على الخادم + الفهرس الفريد الجزئي في قاعدة البيانات.
 */
export function useAvailableSlots(
  date: string | null,
  service: Pick<Service, "id" | "duration"> | null,
): UseAvailableSlotsResult {
  const [slots, setSlots] = useState<TimeSlot[]>([]);
  const [loading, setLoading] = useState(false);
  const [closed, setClosed] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!date || !service) {
      setSlots([]);
      setClosed(false);
      return;
    }

    let cancelled = false;
    setLoading(true);
    setError(null);

    (async () => {
      try {
        const dow = new Date(date).getDay(); // 0=الأحد .. 6=السبت

        const [{ data: hours }, { data: appts }] = await Promise.all([
          clinicDb
            .from("clinic_hours")
            .select("*")
            .eq("organization_id", ORGANIZATION_ID)
            .eq("day_of_week", dow)
            .maybeSingle(),
          clinicDb
            .from("appointments")
            .select("id, start_time, status, service:services(duration)")
            .eq("organization_id", ORGANIZATION_ID)
            .eq("appointment_date", date)
            .neq("status", "cancelled"),
        ]);

        if (cancelled) return;

        const clinic = hours as ClinicHour | null;
        if (!clinic || clinic.is_closed) {
          setClosed(true);
          setSlots([]);
          return;
        }
        setClosed(false);

        // الفترات المحجوزة كأزواج [بداية، نهاية] بالدقائق من منتصف الليل
        type Reserved = { start: number; end: number };
        // العلاقة المتداخلة قد تُعاد كمصفوفة أو كائن حسب Supabase — نطبّعها
        type ApptRow = Pick<Appointment, "start_time"> & {
          service: { duration: number } | { duration: number }[] | null;
        };
        const reserved: Reserved[] = ((appts ?? []) as unknown as ApptRow[]).map((a) => {
          const svc = Array.isArray(a.service) ? a.service[0] : a.service;
          const start = toMinutes(a.start_time);
          const dur = svc?.duration ?? SLOT_STEP_MINUTES;
          return { start, end: start + dur };
        });

        const open = toMinutes(clinic.start_time);
        const close = toMinutes(clinic.end_time);
        const duration = service.duration;

        const generated: TimeSlot[] = [];
        for (let t = open; t + duration <= close; t += SLOT_STEP_MINUTES) {
          const slotStart = t;
          const slotEnd = t + duration;
          const overlaps = reserved.some(
            (r) => slotStart < r.end && slotEnd > r.start,
          );
          generated.push({
            time: fromMinutes(slotStart),
            available: !overlaps,
          });
        }

        setSlots(generated);
      } catch {
        if (!cancelled) setError("تعذّر تحميل الأوقات المتاحة");
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [date, service?.id, service?.duration]);

  return { slots, loading, closed, error };
}

function toMinutes(time: string): number {
  const [h, m] = time.split(":").map(Number);
  return h * 60 + m;
}

function fromMinutes(total: number): string {
  return addMinutes("00:00", total);
}
