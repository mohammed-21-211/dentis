/**
 * معرّف المنظمة (العيادة) التي تخدمها هذه الواجهة.
 * هذا تطبيق أحادي العيادة على مستوى الواجهة (نشر واحد = عيادة واحدة)، فوق
 * قاعدة بيانات متعددة العيادات (organization_id على مستوى الصف). لا يوجد
 * توجيه بحسب subdomain/slug في هذا الكود، لذا معرّف العيادة يأتي من بيئة
 * النشر مباشرة — نفس نمط VITE_SUPABASE_URL.
 */

export const ORGANIZATION_ID = import.meta.env.VITE_ORGANIZATION_ID as
  | string
  | undefined;

export const isOrganizationConfigured = Boolean(
  ORGANIZATION_ID && !ORGANIZATION_ID.includes("your-organization"),
);
