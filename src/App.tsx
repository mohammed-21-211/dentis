import { Routes, Route, Navigate } from "react-router-dom";
import { isSupabaseConfigured } from "@/lib/supabase";
import { isOrganizationConfigured } from "@/lib/organization";
import { ProtectedRoute } from "@/components/ProtectedRoute";
import SetupNotice from "@/pages/SetupNotice";
import LandingPage from "@/pages/Landing";
import LoginPage from "@/pages/auth/Login";
import RegisterPage from "@/pages/auth/Register";
import DoctorDashboard from "@/pages/doctor/DoctorDashboard";
import PatientDashboard from "@/pages/patient/PatientDashboard";

export default function App() {
  // بوّابة التهيئة: بدل صفحة بيضاء عند غياب إعداد Supabase أو معرّف العيادة
  if (!isSupabaseConfigured || !isOrganizationConfigured) {
    return <SetupNotice />;
  }

  return (
    <Routes>
      {/* عام */}
      <Route path="/" element={<LandingPage />} />
      <Route path="/login" element={<LoginPage />} />
      <Route path="/register" element={<RegisterPage />} />

      {/* لوحة الطبيب/الكادر — عضو في organization_members */}
      <Route
        path="/doctor/*"
        element={
          <ProtectedRoute requireStaff>
            <DoctorDashboard />
          </ProtectedRoute>
        }
      />

      {/* لوحة المريض — أي مستخدم مصادَق ليس عضواً في المنظمة */}
      <Route
        path="/patient/*"
        element={
          <ProtectedRoute requireStaff={false}>
            <PatientDashboard />
          </ProtectedRoute>
        }
      />

      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
