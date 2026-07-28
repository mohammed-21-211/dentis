import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

/** دمج أصناف Tailwind بأمان (shadcn) */
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

/** تنسيق السعر بالريال السعودي */
export function formatPrice(value: number): string {
  return new Intl.NumberFormat("ar-SA", {
    style: "currency",
    currency: "SAR",
    maximumFractionDigits: 0,
  }).format(value);
}

/** تنسيق التاريخ بالعربية (مثال: 13 يونيو 2026) */
export function formatDateAr(date: string | Date): string {
  const d = typeof date === "string" ? new Date(date) : date;
  return new Intl.DateTimeFormat("ar-SA-u-ca-gregory", {
    day: "numeric",
    month: "long",
    year: "numeric",
  }).format(d);
}

/** تحويل "HH:mm:ss" أو "HH:mm" إلى صيغة 12 ساعة عربية (مثال: 2:30 مساءً) */
export function formatTimeAr(time: string): string {
  const [h, m] = time.split(":");
  const date = new Date();
  date.setHours(Number(h), Number(m), 0, 0);
  return new Intl.DateTimeFormat("ar-SA", {
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  }).format(date);
}

/** اختصار "HH:mm:ss" إلى "HH:mm" */
export function trimSeconds(time: string): string {
  return time.slice(0, 5);
}

/** إضافة دقائق إلى وقت "HH:mm" وإرجاع "HH:mm" */
export function addMinutes(time: string, minutes: number): string {
  const [h, m] = time.split(":").map(Number);
  const total = h * 60 + m + minutes;
  const hh = Math.floor(total / 60) % 24;
  const mm = total % 60;
  return `${String(hh).padStart(2, "0")}:${String(mm).padStart(2, "0")}`;
}

/** ترجمة حالة الموعد إلى العربية */
export function appointmentStatusAr(status: string): string {
  switch (status) {
    case "pending":
      return "قيد الانتظار";
    case "confirmed":
      return "مؤكّد";
    case "cancelled":
      return "ملغى";
    default:
      return status;
  }
}
