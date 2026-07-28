export * from "./database";

/** فترة زمنية قابلة للحجز تُعرض في نموذج الحجز */
export interface TimeSlot {
  /** "HH:mm" */
  time: string;
  available: boolean;
}

/** أيام الأسبوع بالعربية مفهرسة حسب day_of_week (0=الأحد) */
export const WEEKDAYS_AR = [
  "الأحد",
  "الإثنين",
  "الثلاثاء",
  "الأربعاء",
  "الخميس",
  "الجمعة",
  "السبت",
] as const;
