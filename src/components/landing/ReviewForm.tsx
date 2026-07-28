import { useState } from "react";
import { Loader2, Star } from "lucide-react";
import { toast } from "sonner";
import { clinicDb } from "@/lib/supabase";
import { ORGANIZATION_ID } from "@/lib/organization";
import { reviewSchema } from "@/lib/validations";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";

/**
 * نموذج إرسال تقييم حقيقي من الزائر.
 * يُدرج التقييم بحالة is_approved = false (سياسة RLS العامة)،
 * ولا يظهر في الموقع إلا بعد اعتماد الطبيب.
 */
export function ReviewForm({ onSubmitted }: { onSubmitted?: () => void }) {
  const [name, setName] = useState("");
  const [rating, setRating] = useState(0);
  const [hover, setHover] = useState(0);
  const [comment, setComment] = useState("");
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const parsed = reviewSchema.safeParse({
      patient_name: name,
      rating,
      comment,
    });
    if (!parsed.success) {
      toast.error(parsed.error.issues[0]?.message ?? "تحقق من البيانات");
      return;
    }

    setSubmitting(true);
    const { error } = await clinicDb.from("reviews").insert({
      organization_id: ORGANIZATION_ID,
      patient_name: parsed.data.patient_name,
      rating: parsed.data.rating,
      comment: parsed.data.comment || null,
      is_approved: false,
    });
    setSubmitting(false);

    if (error) {
      toast.error("تعذّر إرسال التقييم");
      return;
    }
    toast.success("شكراً لك! سيظهر تقييمك بعد مراجعته من العيادة.");
    setName("");
    setRating(0);
    setComment("");
    onSubmitted?.();
  }

  return (
    <Card className="mx-auto max-w-xl">
      <CardContent className="pt-6">
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="r-name">اسمك</Label>
            <Input
              id="r-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="مثال: محمد أحمد"
            />
          </div>

          <div className="space-y-2">
            <Label>تقييمك</Label>
            <div className="flex gap-1">
              {Array.from({ length: 5 }).map((_, i) => {
                const value = i + 1;
                return (
                  <button
                    key={value}
                    type="button"
                    onClick={() => setRating(value)}
                    onMouseEnter={() => setHover(value)}
                    onMouseLeave={() => setHover(0)}
                    aria-label={`${value} نجوم`}
                    className="transition-transform hover:scale-110"
                  >
                    <Star
                      className={
                        value <= (hover || rating)
                          ? "size-7 fill-amber-400 text-amber-400"
                          : "size-7 text-muted-foreground/30"
                      }
                    />
                  </button>
                );
              })}
            </div>
          </div>

          <div className="space-y-2">
            <Label htmlFor="r-comment">تعليقك</Label>
            <Textarea
              id="r-comment"
              value={comment}
              onChange={(e) => setComment(e.target.value)}
              placeholder="شاركنا تجربتك في العيادة..."
            />
          </div>

          <Button type="submit" className="w-full" disabled={submitting}>
            {submitting && <Loader2 className="size-4 animate-spin" />}
            إرسال التقييم
          </Button>
        </form>
      </CardContent>
    </Card>
  );
}
