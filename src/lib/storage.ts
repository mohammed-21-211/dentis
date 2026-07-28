import { supabase } from "@/lib/supabase";

/**
 * يرفع ملفاً إلى باكت عام ويُعيد رابطه العام الدائم.
 * يُستخدم لصور الحالات (قبل/بعد) في باكت case-media.
 */
export async function uploadPublicFile(
  bucket: string,
  folder: string,
  file: File,
): Promise<string> {
  const ext = file.name.split(".").pop() ?? "jpg";
  const path = `${folder}/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`;
  const { error } = await supabase.storage.from(bucket).upload(path, file, {
    upsert: false,
    cacheControl: "3600",
  });
  if (error) throw error;
  return supabase.storage.from(bucket).getPublicUrl(path).data.publicUrl;
}

/**
 * يستخرج مسار الكائن داخل الباكت من رابط عام، لحذفه من التخزين.
 * مثال: .../object/public/case-media/before/123.jpg → before/123.jpg
 */
export function pathFromPublicUrl(bucket: string, url: string | null): string | null {
  if (!url) return null;
  const marker = `/${bucket}/`;
  const idx = url.indexOf(marker);
  return idx === -1 ? null : url.slice(idx + marker.length);
}

/** حذف كائنات من باكت (أفضل جهد — يتجاهل الأخطاء) */
export async function removePublicFiles(bucket: string, paths: (string | null)[]) {
  const valid = paths.filter((p): p is string => Boolean(p));
  if (valid.length === 0) return;
  await supabase.storage.from(bucket).remove(valid);
}
