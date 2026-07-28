import { z } from "zod";

/**
 * مخططات التحقق (Zod) — رسائل الخطأ بالعربية.
 * تدعم الإدخال العربي وقيود التاريخ/الوقت الصحيحة.
 */

// أنماط مساعدة
const arabicNameRegex = /^[؀-ۿ\sݐ-ݿ a-zA-Z]{2,}$/; // عربي/إنجليزي
const phoneRegex = /^[0-9+\-\s]{6,20}$/;
const timeRegex = /^([01]\d|2[0-3]):[0-5]\d$/; // HH:mm

export const loginSchema = z.object({
  email: z.string().min(1, "البريد الإلكتروني مطلوب").email("صيغة البريد غير صحيحة"),
  password: z.string().min(6, "كلمة المرور يجب ألا تقل عن 6 أحرف"),
});
export type LoginInput = z.infer<typeof loginSchema>;

export const registerSchema = z
  .object({
    fullName: z
      .string()
      .min(2, "الاسم قصير جداً")
      .max(120, "الاسم طويل جداً")
      .regex(arabicNameRegex, "الرجاء إدخال اسم صحيح"),
    email: z.string().min(1, "البريد الإلكتروني مطلوب").email("صيغة البريد غير صحيحة"),
    phone: z.string().regex(phoneRegex, "رقم الهاتف غير صحيح"),
    password: z.string().min(6, "كلمة المرور يجب ألا تقل عن 6 أحرف"),
    confirmPassword: z.string().min(6, "تأكيد كلمة المرور مطلوب"),
  })
  .refine((d) => d.password === d.confirmPassword, {
    message: "كلمتا المرور غير متطابقتين",
    path: ["confirmPassword"],
  });
export type RegisterInput = z.infer<typeof registerSchema>;

export const bookingSchema = z.object({
  serviceId: z.string().uuid("الرجاء اختيار الخدمة"),
  date: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/, "التاريخ غير صحيح")
    .refine((d) => new Date(d) >= new Date(new Date().toDateString()), {
      message: "لا يمكن الحجز في تاريخ ماضٍ",
    }),
  startTime: z.string().regex(timeRegex, "الوقت غير صحيح"),
  // حقول اختيارية للزائر غير المسجّل في نموذج صفحة الهبوط
  fullName: z.string().min(2, "الاسم مطلوب").optional(),
  phone: z.string().regex(phoneRegex, "رقم الهاتف غير صحيح").optional(),
});
export type BookingInput = z.infer<typeof bookingSchema>;

export const cancellationSchema = z.object({
  reason: z
    .string()
    .min(3, "يرجى كتابة سبب الإلغاء (3 أحرف على الأقل)")
    .max(500, "السبب طويل جداً"),
});
export type CancellationInput = z.infer<typeof cancellationSchema>;

export const serviceSchema = z.object({
  name: z.string().min(2, "اسم الخدمة مطلوب").max(120),
  description: z.string().max(1000).optional().or(z.literal("")),
  duration: z.coerce
    .number()
    .int("المدة يجب أن تكون رقماً صحيحاً")
    .min(5, "المدة لا تقل عن 5 دقائق")
    .max(480, "المدة لا تزيد عن 8 ساعات"),
  price: z.coerce.number().min(0, "السعر لا يمكن أن يكون سالباً"),
});
export type ServiceInput = z.infer<typeof serviceSchema>;

export const clinicHourSchema = z
  .object({
    day_of_week: z.coerce.number().int().min(0).max(6),
    start_time: z.string().regex(timeRegex, "وقت البدء غير صحيح"),
    end_time: z.string().regex(timeRegex, "وقت الانتهاء غير صحيح"),
    is_closed: z.boolean(),
  })
  .refine((d) => d.is_closed || d.end_time > d.start_time, {
    message: "وقت الانتهاء يجب أن يكون بعد وقت البدء",
    path: ["end_time"],
  });
export type ClinicHourInput = z.infer<typeof clinicHourSchema>;

export const medicalRecordSchema = z
  .object({
    patient_id: z.string().uuid(),
    doctor_notes: z.string().max(2000).optional().or(z.literal("")),
    treatment_plan: z.string().max(2000).optional().or(z.literal("")),
  })
  .refine((d) => (d.doctor_notes && d.doctor_notes.length > 0) || (d.treatment_plan && d.treatment_plan.length > 0), {
    message: "يجب إدخال ملاحظات الطبيب أو خطة العلاج على الأقل",
    path: ["doctor_notes"],
  });
export type MedicalRecordInput = z.infer<typeof medicalRecordSchema>;

export const caseStudySchema = z.object({
  title: z.string().min(2, "عنوان الحالة مطلوب").max(120, "العنوان طويل جداً"),
  description: z.string().max(1000, "الوصف طويل جداً").optional().or(z.literal("")),
});
export type CaseStudyInput = z.infer<typeof caseStudySchema>;

export const reviewSchema = z.object({
  patient_name: z.string().min(2, "الاسم مطلوب").max(120),
  rating: z.coerce.number().int().min(1, "التقييم مطلوب").max(5),
  comment: z.string().max(1000).optional().or(z.literal("")),
});
export type ReviewInput = z.infer<typeof reviewSchema>;
