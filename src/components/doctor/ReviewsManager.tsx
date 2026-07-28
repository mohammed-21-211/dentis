import { useCallback, useEffect, useState } from "react";
import { Loader2, MessageSquareQuote, Star, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { clinicDb } from "@/lib/supabase";
import { ORGANIZATION_ID } from "@/lib/organization";
import { formatDateAr } from "@/lib/utils";
import type { Review } from "@/types";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";

export function ReviewsManager() {
  const [items, setItems] = useState<Review[]>([]);
  const [loading, setLoading] = useState(true);
  const [busyId, setBusyId] = useState<string | null>(null);

  const load = useCallback(async () => {
    const { data } = await clinicDb
      .from("reviews")
      .select("*")
      .eq("organization_id", ORGANIZATION_ID)
      .order("created_at", { ascending: false });
    setItems((data as Review[]) ?? []);
    setLoading(false);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  async function toggleApprove(r: Review) {
    setBusyId(r.id);
    const { error } = await clinicDb
      .from("reviews")
      .update({ is_approved: !r.is_approved })
      .eq("id", r.id);
    setBusyId(null);
    if (error) {
      toast.error("تعذّر تحديث حالة التقييم");
      return;
    }
    toast.success(!r.is_approved ? "تم اعتماد التقييم وعرضه" : "تم إخفاء التقييم");
    load();
  }

  async function remove(id: string) {
    setBusyId(id);
    const { error } = await clinicDb.from("reviews").delete().eq("id", id);
    setBusyId(null);
    if (error) {
      toast.error("تعذّر حذف التقييم");
      return;
    }
    toast.success("تم حذف التقييم");
    load();
  }

  const pendingCount = items.filter((r) => !r.is_approved).length;

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <MessageSquareQuote className="size-5 text-primary" />
          التقييمات والتعليقات
          {pendingCount > 0 && (
            <Badge variant="warning">{pendingCount} بانتظار الاعتماد</Badge>
          )}
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        {loading ? (
          <div className="flex justify-center py-8">
            <Loader2 className="size-6 animate-spin text-primary" />
          </div>
        ) : items.length === 0 ? (
          <p className="py-4 text-center text-sm text-muted-foreground">
            لا توجد تقييمات بعد.
          </p>
        ) : (
          items.map((r) => (
            <div
              key={r.id}
              className="flex flex-wrap items-start justify-between gap-3 rounded-lg border border-border p-4"
            >
              <div className="min-w-0 space-y-1">
                <div className="flex items-center gap-2">
                  <span className="font-semibold">{r.patient_name}</span>
                  <div className="flex">
                    {Array.from({ length: 5 }).map((_, i) => (
                      <Star
                        key={i}
                        className={
                          i < r.rating
                            ? "size-3.5 fill-amber-400 text-amber-400"
                            : "size-3.5 text-muted-foreground/30"
                        }
                      />
                    ))}
                  </div>
                  <Badge variant={r.is_approved ? "success" : "warning"}>
                    {r.is_approved ? "معتمد" : "قيد المراجعة"}
                  </Badge>
                </div>
                {r.comment && (
                  <p className="text-sm text-muted-foreground">«{r.comment}»</p>
                )}
                <p className="text-[11px] text-muted-foreground/70">
                  {formatDateAr(r.created_at)}
                </p>
              </div>
              <div className="flex items-center gap-2">
                <Button
                  size="sm"
                  variant={r.is_approved ? "outline" : "success"}
                  onClick={() => toggleApprove(r)}
                  disabled={busyId === r.id}
                >
                  {busyId === r.id && <Loader2 className="size-3.5 animate-spin" />}
                  {r.is_approved ? "إخفاء" : "اعتماد"}
                </Button>
                <Button
                  size="icon"
                  variant="ghost"
                  onClick={() => remove(r.id)}
                  disabled={busyId === r.id}
                  className="text-destructive hover:text-destructive"
                  aria-label="حذف"
                >
                  <Trash2 className="size-4" />
                </Button>
              </div>
            </div>
          ))
        )}
      </CardContent>
    </Card>
  );
}
