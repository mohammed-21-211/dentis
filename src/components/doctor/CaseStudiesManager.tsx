import { useCallback, useEffect, useRef, useState } from "react";
import { ImagePlus, Loader2, Trash2, Upload } from "lucide-react";
import { toast } from "sonner";
import { clinicDb } from "@/lib/supabase";
import { ORGANIZATION_ID } from "@/lib/organization";
import { caseStudySchema } from "@/lib/validations";
import { pathFromPublicUrl, removePublicFiles, uploadPublicFile } from "@/lib/storage";
import type { CaseStudy } from "@/types";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";

const BUCKET = "case-media";

export function CaseStudiesManager() {
  const [items, setItems] = useState<CaseStudy[]>([]);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [beforeFile, setBeforeFile] = useState<File | null>(null);
  const [afterFile, setAfterFile] = useState<File | null>(null);
  const [saving, setSaving] = useState(false);
  const [deletingId, setDeletingId] = useState<string | null>(null);
  const beforeRef = useRef<HTMLInputElement>(null);
  const afterRef = useRef<HTMLInputElement>(null);

  const load = useCallback(async () => {
    const { data } = await clinicDb
      .from("case_studies")
      .select("*")
      .eq("organization_id", ORGANIZATION_ID)
      .order("created_at", { ascending: false });
    setItems((data as CaseStudy[]) ?? []);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  function resetForm() {
    setTitle("");
    setDescription("");
    setBeforeFile(null);
    setAfterFile(null);
    if (beforeRef.current) beforeRef.current.value = "";
    if (afterRef.current) afterRef.current.value = "";
  }

  async function handleSave() {
    const parsed = caseStudySchema.safeParse({ title, description });
    if (!parsed.success) {
      toast.error(parsed.error.issues[0]?.message ?? "تحقق من البيانات");
      return;
    }
    if (!beforeFile || !afterFile) {
      toast.error("يرجى اختيار صورتي «قبل» و«بعد»");
      return;
    }

    if (!ORGANIZATION_ID) {
      toast.error("معرّف العيادة غير مضبوط");
      return;
    }

    setSaving(true);
    try {
      // مسار التخزين: case-media/{organization_id}/{filename} — يطابق سياسات
      // Storage في 0007_clinic_storage.sql التي تتحقق من عضوية العيادة عبر
      // أول segment في المسار.
      const [beforeUrl, afterUrl] = await Promise.all([
        uploadPublicFile(BUCKET, ORGANIZATION_ID, beforeFile),
        uploadPublicFile(BUCKET, ORGANIZATION_ID, afterFile),
      ]);

      const { error } = await clinicDb.from("case_studies").insert({
        organization_id: ORGANIZATION_ID,
        title: parsed.data.title,
        description: parsed.data.description || null,
        before_image_url: beforeUrl,
        after_image_url: afterUrl,
      });
      if (error) throw error;

      toast.success("تمت إضافة الحالة إلى معرض الأعمال");
      resetForm();
      load();
    } catch {
      toast.error("تعذّر رفع الصور أو حفظ الحالة");
    } finally {
      setSaving(false);
    }
  }

  async function handleDelete(c: CaseStudy) {
    setDeletingId(c.id);
    const { error } = await clinicDb.from("case_studies").delete().eq("id", c.id);
    if (error) {
      toast.error("تعذّر حذف الحالة");
      setDeletingId(null);
      return;
    }
    // تنظيف الصور من التخزين (أفضل جهد)
    await removePublicFiles(BUCKET, [
      pathFromPublicUrl(BUCKET, c.before_image_url),
      pathFromPublicUrl(BUCKET, c.after_image_url),
    ]);
    toast.success("تم حذف الحالة");
    setDeletingId(null);
    load();
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <ImagePlus className="size-5 text-primary" />
          معرض الأعمال (قبل / بعد)
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-6">
        {/* نموذج الإضافة */}
        <div className="space-y-4 rounded-xl border border-dashed border-border p-4">
          <div className="space-y-2">
            <Label htmlFor="cs-title">عنوان الحالة</Label>
            <Input
              id="cs-title"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="مثال: تبييض وتجميل الأسنان الأمامية"
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="cs-desc">الوصف (اختياري)</Label>
            <Textarea
              id="cs-desc"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="وصف موجز للحالة والعلاج المُقدّم..."
            />
          </div>
          <div className="grid gap-4 sm:grid-cols-2">
            <FilePicker
              label="صورة «قبل»"
              file={beforeFile}
              inputRef={beforeRef}
              onChange={setBeforeFile}
            />
            <FilePicker
              label="صورة «بعد»"
              file={afterFile}
              inputRef={afterRef}
              onChange={setAfterFile}
            />
          </div>
          <Button onClick={handleSave} disabled={saving} className="w-full">
            {saving ? <Loader2 className="size-4 animate-spin" /> : <Upload className="size-4" />}
            نشر الحالة
          </Button>
        </div>

        {/* القائمة */}
        <div className="space-y-3">
          <p className="text-sm font-medium text-muted-foreground">
            الحالات المنشورة ({items.length})
          </p>
          {items.length === 0 ? (
            <p className="py-4 text-center text-sm text-muted-foreground">
              لا توجد حالات بعد. أضف أول حالة من النموذج أعلاه.
            </p>
          ) : (
            <div className="grid gap-3 sm:grid-cols-2">
              {items.map((c) => (
                <div
                  key={c.id}
                  className="overflow-hidden rounded-lg border border-border"
                >
                  <div className="grid grid-cols-2">
                    <img
                      src={c.before_image_url ?? ""}
                      alt="قبل"
                      className="aspect-square w-full object-cover"
                    />
                    <img
                      src={c.after_image_url ?? ""}
                      alt="بعد"
                      className="aspect-square w-full object-cover"
                    />
                  </div>
                  <div className="flex items-center justify-between gap-2 p-3">
                    <div className="min-w-0">
                      <p className="truncate text-sm font-semibold">{c.title}</p>
                      {c.description && (
                        <p className="truncate text-xs text-muted-foreground">
                          {c.description}
                        </p>
                      )}
                    </div>
                    <Button
                      variant="ghost"
                      size="icon"
                      onClick={() => handleDelete(c)}
                      disabled={deletingId === c.id}
                      className="shrink-0 text-destructive hover:text-destructive"
                      aria-label="حذف"
                    >
                      {deletingId === c.id ? (
                        <Loader2 className="size-4 animate-spin" />
                      ) : (
                        <Trash2 className="size-4" />
                      )}
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </CardContent>
    </Card>
  );
}

function FilePicker({
  label,
  file,
  inputRef,
  onChange,
}: {
  label: string;
  file: File | null;
  inputRef: React.RefObject<HTMLInputElement>;
  onChange: (f: File | null) => void;
}) {
  return (
    <div className="space-y-2">
      <Label>{label}</Label>
      <input
        ref={inputRef}
        type="file"
        accept="image/*"
        onChange={(e) => onChange(e.target.files?.[0] ?? null)}
        className="block w-full text-sm text-muted-foreground file:ml-3 file:rounded-lg file:border-0 file:bg-secondary file:px-3 file:py-2 file:text-xs file:font-medium hover:file:bg-secondary/80"
      />
      {file && (
        <img
          src={URL.createObjectURL(file)}
          alt="معاينة"
          className="h-24 w-full rounded-lg object-cover"
        />
      )}
    </div>
  );
}
