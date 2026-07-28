/**
 * أنواع قاعدة البيانات — تعكس مخطط Supabase.
 * يمكن توليدها لاحقاً عبر:  supabase gen types typescript --linked > src/types/database.ts
 * هذا الإصدار مكتوب يدوياً ليطابق ملفات الهجرة (migrations).
 */

export type AppointmentStatus = "pending" | "confirmed" | "cancelled";

/**
 * profiles هو جدول الهوية المشترك للـ Backbone (public.profiles) — لا يحمل
 * دوراً (role) مخزَّناً؛ "طبيب/كادر" مقابل "مريض" يُشتق ديناميكياً من عضوية
 * public.organization_members (انظر AuthContext.isStaff)، وليس من عمود هنا.
 */
export interface Profile {
  id: string;
  full_name: string;
  phone: string | null;
  created_at: string;
}

export interface Service {
  id: string;
  organization_id: string;
  name: string;
  description: string | null;
  duration: number; // بالدقائق
  price: number;
  is_active: boolean;
  created_at: string;
}

export interface ClinicHour {
  id: string;
  organization_id: string;
  day_of_week: number; // 0=الأحد .. 6=السبت
  start_time: string; // "HH:mm:ss"
  end_time: string;
  is_closed: boolean;
  created_at: string;
}

export interface Appointment {
  id: string;
  organization_id: string;
  patient_id: string;
  service_id: string;
  appointment_date: string; // "YYYY-MM-DD"
  start_time: string; // "HH:mm:ss"
  status: AppointmentStatus;
  cancellation_reason: string | null;
  created_at: string;
}

/** موعد مع بياناته المرتبطة (للعرض في الجداول) */
export interface AppointmentWithRelations extends Appointment {
  service: Pick<Service, "id" | "name" | "duration" | "price"> | null;
  patient: Pick<Profile, "id" | "full_name" | "phone"> | null;
}

export interface MedicalRecord {
  id: string;
  organization_id: string;
  patient_id: string;
  doctor_notes: string | null;
  treatment_plan: string | null;
  x_ray_url: string | null;
  created_at: string;
}

export interface AppNotification {
  id: string;
  organization_id: string;
  user_id: string;
  title: string;
  message: string;
  is_read: boolean;
  created_at: string;
}

export interface CaseStudy {
  id: string;
  organization_id: string;
  title: string;
  before_image_url: string | null;
  after_image_url: string | null;
  description: string | null;
  created_at: string;
}

export interface Review {
  id: string;
  organization_id: string;
  patient_name: string;
  rating: number;
  comment: string | null;
  is_approved: boolean;
  created_at: string;
}
