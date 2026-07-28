import { useCallback, useEffect, useRef, useState } from "react";
import { Loader2, Pencil, Trash2, Upload, X } from "lucide-react";
import { toast } from "sonner";
import { supabase, clinicDb } from "@/lib/supabase";
import { ORGANIZATION_ID } from "@/lib/organization";
import { medicalRecordSchema } from "@/lib/validations";
import {
  appointmentStatusAr,
  formatDateAr,
  formatTimeAr,
} from "@/lib/utils";
import type {
  AppointmentWithRelations,
  MedicalRecord,
  Profile,
} from "@/types";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";

interface PatientDetailProps {
  patient: Profile;
  onClose: () => void;
}

export function PatientDetail({ patient, onClose }: PatientDetailProps) {
  const [appointments, setAppointments] = useState<AppointmentWithRelations[]>([]);
  const [records, setRecords] = useState<MedicalRecord[]>([]);
  const [notes, setNotes] = useState("");
  const [plan, setPlan] = useState("");
  const [file, setFile] = useState<File | null>(null);
  const [saving, setSaving] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);

  // حالة تعديل سجل قائم
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editNotes, setEditNotes] = useState("");
  const [editPlan, setEditPlan] = useState("");
  const [rowBusy, setRowBusy] = useState<string | null>(null);

  function startEdit(r: MedicalRecord) {
    setEditingId(r.id);
    setEditNotes(r.doctor_notes ?? "");
    setEditPlan(r.treatment_plan ?? "");
  }

  function cancelEdit() {
    setEditingId(null);
    setEditNotes("");
    setEditPlan("");
  }

  async function saveEdit(id: string) {
    const parsed = medicalRecordSchema.safeParse({
      patient_id: patient.id,
      doctor_notes: editNotes,
      treatment_plan: editPlan,
    });
    if (!parsed.success) {
      toast.error(parsed.error.issues[0]?.message ?? "تحقق من البيانات");
      return;
    }
    setRowBusy(id);
    const { error } = await clinicDb
      .from("medical_records")
      .update({
        doctor_notes: editNotes || null,
        treatment_plan: editPlan || null,
      })
      .eq("id", id);
    setRowBusy(null);
    if (error) {
      toast.error("تعذّر تعديل السجل");
      return;
    }
    toast.success("تم تعديل السجل الطبي");
    cancelEdit();
    load();
  }

  async function deleteRecord(id: string) {
    setRowBusy(id);
    const { error } = await clinicDb.from("medical_records").delete().eq("id", id);
    setRowBusy(null);
    if (error) {
      toast.error("تعذّر حذف السجل");
      return;
    }
    toast.success("تم حذف السجل الطبي");
    load();
  }

  const load = useCallback(async () => {
    const [{ data: appts }, { data: recs }] = await Promise.all([
      clinicDb
        .from("appointments")
        .select("*, service:services(id,name,duration,price)")
        .eq("organization_id", ORGANIZATION_ID)
        .eq("patient_id", patient.id)
        .order("appointment_date", { ascending: false }),
      clinicDb
        .from("medical_records")
        .select("*")
        .eq("organization_id", ORGANIZATION_ID)
        .eq("patient_id", patient.id)
        .order("created_at", { ascending: false }),
    ]);
    setAppointments((appts as AppointmentWithRelations[]) ?? []);
    setRecords((recs as MedicalRecord[]) ?? []);
  }, [patient.id]);

  useEffect(() => {
    load();
  }, [load]);

  async function handleSave() {
    const parsed = medicalRecordSchema.safeParse({
      patient_id: patient.id,
      doctor_notes: notes,
      treatment_plan: plan,
    });
    if (!parsed.success) {
      toast.error(parsed.error.issues[0]?.message ?? "تحقق من البيانات");
      return;
    }

    if (!ORGANIZATION_ID) {
      toast.error("معرّف العيادة غير مضبوط");
      return;
    }

    setSaving(true);
    let xRayUrl: string | null = null;

    // رفع صورة الأشعة إلى Storage بمسار x-rays/{organization_id}/{patient_id}/{timestamp}-{name}
    // يطابق سياسات Storage في 0007_clinic_storage.sql
    if (file) {
      const path = `${ORGANIZATION_ID}/${patient.id}/${Date.now()}-${file.name}`;
      const { error: upErr } = await supabase.storage
        .from("x-rays")
        .upload(path, file, { upsert: false });
      if (upErr) {
        setSaving(false);
        toast.error("تعذّر رفع صورة الأشعة");
        return;
      }
      // رابط موقّع صالح لسنة (الباكت خاص)
      const { data: signed } = await supabase.storage
        .from("x-rays")
        .createSignedUrl(path, 60 * 60 * 24 * 365);
      xRayUrl = signed?.signedUrl ?? null;
    }

    const { error } = await clinicDb.from("medical_records").insert({
      organization_id: ORGANIZATION_ID,
      patient_id: patient.id,
      doctor_notes: notes || null,
      treatment_plan: plan || null,
      x_ray_url: xRayUrl,
    });
    setSaving(false);

    if (error) {
      toast.error("تعذّر حفظ السجل الطبي");
      return;
    }
    toast.success("تمت إضافة السجل الطبي وإشعار المريض");
    setNotes("");
    setPlan("");
    setFile(null);
    if (fileRef.current) fileRef.current.value = "";
    load();
  }

  return (
    <div className="fixed inset-0 z-50 flex justify-start overflow-y-auto bg-foreground/40">
      <div className="ml-auto h-full w-full max-w-2xl bg-background shadow-2xl">
        <div className="sticky top-0 flex items-center justify-between border-b border-border bg-background p-4">
          <div>
            <h2 className="font-display text-xl font-extrabold">{patient.full_name}</h2>
            <p className="text-sm text-muted-foreground" dir="ltr">
              {patient.phone ?? "—"}
            </p>
          </div>
          <Button variant="ghost" size="icon" onClick={onClose} aria-label="إغلاق">
            <X className="size-5" />
          </Button>
        </div>

        <div className="space-y-6 p-4">
          {/* إضافة سجل طبي */}
          <Card>
            <CardHeader>
              <CardTitle>إضافة سجل طبي جديد</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="notes">ملاحظات الطبيب</Label>
                <Textarea
                  id="notes"
                  value={notes}
                  onChange={(e) => setNotes(e.target.value)}
                  placeholder="التشخيص والملاحظات السريرية..."
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="plan">خطة العلاج</Label>
                <Textarea
                  id="plan"
                  value={plan}
                  onChange={(e) => setPlan(e.target.value)}
                  placeholder="الخطوات العلاجية القادمة..."
                />
              </div>
              <div className="space-y-2">
                <Label>صورة الأشعة (اختياري)</Label>
                <input
                  ref={fileRef}
                  type="file"
                  accept="image/*,.pdf"
                  onChange={(e) => setFile(e.target.files?.[0] ?? null)}
                  className="block w-full text-sm text-muted-foreground file:ml-3 file:rounded-lg file:border-0 file:bg-secondary file:px-4 file:py-2 file:text-sm file:font-medium hover:file:bg-secondary/80"
                />
              </div>
              <Button onClick={handleSave} disabled={saving} className="w-full">
                {saving ? (
                  <Loader2 className="size-4 animate-spin" />
                ) : (
                  <Upload className="size-4" />
                )}
                حفظ السجل
              </Button>
            </CardContent>
          </Card>

          {/* تاريخ السجلات */}
          <Card>
            <CardHeader>
              <CardTitle>السجلات الطبية السابقة</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              {records.length === 0 ? (
                <p className="text-sm text-muted-foreground">لا توجد سجلات بعد.</p>
              ) : (
                records.map((r) => (
                  <div key={r.id} className="rounded-lg border border-border p-3 text-sm">
                    {editingId === r.id ? (
                      /* وضع التعديل */
                      <div className="space-y-3">
                        <div className="space-y-1">
                          <Label htmlFor={`edit-notes-${r.id}`}>ملاحظات الطبيب</Label>
                          <Textarea
                            id={`edit-notes-${r.id}`}
                            value={editNotes}
                            onChange={(e) => setEditNotes(e.target.value)}
                          />
                        </div>
                        <div className="space-y-1">
                          <Label htmlFor={`edit-plan-${r.id}`}>خطة العلاج</Label>
                          <Textarea
                            id={`edit-plan-${r.id}`}
                            value={editPlan}
                            onChange={(e) => setEditPlan(e.target.value)}
                          />
                        </div>
                        <div className="flex justify-end gap-2">
                          <Button variant="outline" size="sm" onClick={cancelEdit}>
                            إلغاء
                          </Button>
                          <Button
                            size="sm"
                            onClick={() => saveEdit(r.id)}
                            disabled={rowBusy === r.id}
                          >
                            {rowBusy === r.id && <Loader2 className="size-3.5 animate-spin" />}
                            حفظ التعديل
                          </Button>
                        </div>
                      </div>
                    ) : (
                      /* وضع العرض */
                      <>
                        <div className="mb-1 flex items-center justify-between">
                          <p className="text-xs text-muted-foreground">
                            {formatDateAr(r.created_at)}
                          </p>
                          <div className="flex items-center gap-1">
                            <Button
                              variant="ghost"
                              size="icon"
                              className="size-7"
                              onClick={() => startEdit(r)}
                              aria-label="تعديل"
                            >
                              <Pencil className="size-3.5" />
                            </Button>
                            <Button
                              variant="ghost"
                              size="icon"
                              className="size-7 text-destructive hover:text-destructive"
                              onClick={() => deleteRecord(r.id)}
                              disabled={rowBusy === r.id}
                              aria-label="حذف"
                            >
                              {rowBusy === r.id ? (
                                <Loader2 className="size-3.5 animate-spin" />
                              ) : (
                                <Trash2 className="size-3.5" />
                              )}
                            </Button>
                          </div>
                        </div>
                        {r.doctor_notes && <p>ملاحظات: {r.doctor_notes}</p>}
                        {r.treatment_plan && <p>خطة العلاج: {r.treatment_plan}</p>}
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
                      </>
                    )}
                  </div>
                ))
              )}
            </CardContent>
          </Card>

          {/* سجل المواعيد */}
          <Card>
            <CardHeader>
              <CardTitle>سجل المواعيد</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2">
              {appointments.length === 0 ? (
                <p className="text-sm text-muted-foreground">لا توجد مواعيد.</p>
              ) : (
                appointments.map((a) => (
                  <div
                    key={a.id}
                    className="flex items-center justify-between rounded-lg border border-border p-3 text-sm"
                  >
                    <span>
                      {a.service?.name} — {formatDateAr(a.appointment_date)}{" "}
                      {formatTimeAr(a.start_time)}
                    </span>
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
                  </div>
                ))
              )}
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}
