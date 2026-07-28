import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { motion } from "framer-motion";
import {
  ShieldCheck,
  Sparkles,
  Star,
  Clock3,
  HeartPulse,
  Smile,
  ArrowLeft,
} from "lucide-react";
import { clinicDb } from "@/lib/supabase";
import { ORGANIZATION_ID } from "@/lib/organization";
import { useAuth } from "@/context/AuthContext";
import type { CaseStudy, Review } from "@/types";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Logo } from "@/components/Logo";
import { BookingForm } from "@/components/landing/BookingForm";
import { ReviewForm } from "@/components/landing/ReviewForm";

const fadeUp = {
  hidden: { opacity: 0, y: 24 },
  visible: { opacity: 1, y: 0 },
};

const FEATURES = [
  {
    icon: HeartPulse,
    title: "عناية متكاملة",
    desc: "فحص شامل وخطط علاجية مخصصة تحافظ على صحة فمك وأسنانك.",
  },
  {
    icon: ShieldCheck,
    title: "تعقيم وأمان",
    desc: "أعلى معايير التعقيم والسلامة في كل خطوة من رحلة علاجك.",
  },
  {
    icon: Clock3,
    title: "مواعيد مرنة",
    desc: "احجز موعدك إلكترونياً واختر الوقت المناسب لك بكل سهولة.",
  },
  {
    icon: Smile,
    title: "ابتسامة مثالية",
    desc: "تجميل وتبييض وتقويم لابتسامة تفخر بها أمام الجميع.",
  },
];

export default function LandingPage() {
  const { user, isStaff } = useAuth();
  const [cases, setCases] = useState<CaseStudy[]>([]);
  const [reviews, setReviews] = useState<Review[]>([]);
  const [showReviewForm, setShowReviewForm] = useState(false);

  useEffect(() => {
    clinicDb
      .from("case_studies")
      .select("*")
      .eq("organization_id", ORGANIZATION_ID)
      .order("created_at", { ascending: false })
      .then(({ data }) => setCases((data as CaseStudy[]) ?? []));
    clinicDb
      .from("reviews")
      .select("*")
      .eq("organization_id", ORGANIZATION_ID)
      .eq("is_approved", true)
      .order("created_at", { ascending: false })
      .then(({ data }) => setReviews((data as Review[]) ?? []));
  }, []);

  const dashboardHref = isStaff ? "/doctor" : "/patient";

  return (
    <div className="min-h-screen bg-background">
      {/* الشريط العلوي */}
      <header className="sticky top-0 z-40 border-b border-border bg-background/80 backdrop-blur">
        <div className="container flex h-16 items-center justify-between gap-3 sm:h-20">
          <Logo className="min-w-0 flex-shrink" />
          <nav className="flex shrink-0 items-center gap-1.5 sm:gap-2">
            {user ? (
              <Button asChild size="sm" className="sm:h-10 sm:px-5">
                <Link to={dashboardHref}>لوحة التحكم</Link>
              </Button>
            ) : (
              <>
                <Button asChild variant="ghost" size="sm" className="hidden sm:inline-flex sm:h-10 sm:px-5">
                  <Link to="/login">تسجيل الدخول</Link>
                </Button>
                <Button asChild size="sm" className="sm:h-10 sm:px-5">
                  <Link to="/register">إنشاء حساب</Link>
                </Button>
              </>
            )}
          </nav>
        </div>
      </header>

      {/* القسم البطولي + نموذج الحجز */}
      <section className="bg-hero-gradient">
        <div className="container grid items-center gap-10 py-16 lg:grid-cols-2 lg:py-24">
          <motion.div
            initial="hidden"
            animate="visible"
            variants={fadeUp}
            transition={{ duration: 0.6 }}
            className="space-y-6 text-center lg:text-right"
          >
            <span className="inline-flex items-center gap-2 rounded-full bg-accent px-4 py-1.5 text-sm font-medium text-accent-foreground">
              <Sparkles className="size-4" />
              رعاية أسنان بمعايير عالمية
            </span>
            <h1 className="font-display text-4xl font-extrabold leading-tight text-balance md:text-5xl">
              ابتسامتك تبدأ من هنا
              <span className="block text-primary">عناية تثق بها لأسنانك</span>
            </h1>
            <p className="mx-auto max-w-lg text-lg text-muted-foreground lg:mx-0">
              نقدّم لك تجربة علاجية متكاملة بأحدث التقنيات وأمهر الأطباء، مع نظام حجز
              ذكي يحفظ وقتك ويذكّرك بمواعيدك.
            </p>
            <div className="flex flex-wrap items-center justify-center gap-3 lg:justify-start">
              <Button asChild size="lg">
                <a href="#booking">
                  احجز موعدك
                  <ArrowLeft className="size-4" />
                </a>
              </Button>
              <Button asChild size="lg" variant="outline">
                <a href="#cases">شاهد أعمالنا</a>
              </Button>
            </div>
          </motion.div>

          <motion.div
            id="booking"
            initial="hidden"
            animate="visible"
            variants={fadeUp}
            transition={{ duration: 0.6, delay: 0.15 }}
          >
            <BookingForm />
          </motion.div>
        </div>
      </section>

      {/* المزايا */}
      <section className="container py-16">
        <SectionTitle
          eyebrow="لماذا نحن"
          title="أهمية العناية بصحة الفم والأسنان"
          subtitle="صحة فمك مرآة لصحة جسدك — نحرص على كل تفصيل."
        />
        <div className="mt-10 grid gap-6 sm:grid-cols-2 lg:grid-cols-4">
          {FEATURES.map((f, i) => (
            <motion.div
              key={f.title}
              initial="hidden"
              whileInView="visible"
              viewport={{ once: true, margin: "-80px" }}
              variants={fadeUp}
              transition={{ duration: 0.5, delay: i * 0.08 }}
            >
              <Card className="h-full transition-shadow hover:shadow-md">
                <CardContent className="space-y-3 p-6">
                  <div className="flex size-12 items-center justify-center rounded-xl bg-accent">
                    <f.icon className="size-6 text-primary" />
                  </div>
                  <h3 className="font-display text-lg font-bold">{f.title}</h3>
                  <p className="text-sm leading-relaxed text-muted-foreground">{f.desc}</p>
                </CardContent>
              </Card>
            </motion.div>
          ))}
        </div>
      </section>

      {/* معرض قبل / بعد */}
      <section id="cases" className="bg-muted/40 py-16">
        <div className="container">
          <SectionTitle
            eyebrow="معرض الأعمال"
            title="نتائج تتحدث عن نفسها"
            subtitle="مرّر لمشاهدة الفرق قبل وبعد العلاج."
          />
          <div className="mt-10 grid gap-6 md:grid-cols-2">
            {cases.length === 0 ? (
              <p className="col-span-full text-center text-muted-foreground">
                سيتم عرض حالات قبل/بعد هنا قريباً.
              </p>
            ) : (
              cases.map((c, i) => (
                <motion.div
                  key={c.id}
                  initial="hidden"
                  whileInView="visible"
                  viewport={{ once: true }}
                  variants={fadeUp}
                  transition={{ duration: 0.5, delay: i * 0.1 }}
                >
                  <BeforeAfterCard caseStudy={c} />
                </motion.div>
              ))
            )}
          </div>
        </div>
      </section>

      {/* التقييمات */}
      <section className="container py-16">
        <SectionTitle
          eyebrow="آراء المرضى"
          title="ثقة تشرّفنا"
          subtitle="ماذا قال مرضانا عن تجربتهم معنا."
        />
        {reviews.length === 0 ? (
          <p className="mt-10 text-center text-muted-foreground">
            كن أول من يشاركنا تجربته — أضف تقييمك أدناه.
          </p>
        ) : (
          <div className="mt-10 grid gap-6 md:grid-cols-3">
            {reviews.map((r, i) => (
              <motion.div
                key={r.id}
                initial="hidden"
                whileInView="visible"
                viewport={{ once: true }}
                variants={fadeUp}
                transition={{ duration: 0.5, delay: i * 0.08 }}
              >
                <Card className="h-full">
                  <CardContent className="space-y-3 p-6">
                    <div className="flex gap-0.5">
                      {Array.from({ length: 5 }).map((_, idx) => (
                        <Star
                          key={idx}
                          className={
                            idx < r.rating
                              ? "size-4 fill-amber-400 text-amber-400"
                              : "size-4 text-muted-foreground/30"
                          }
                        />
                      ))}
                    </div>
                    <p className="text-sm leading-relaxed text-muted-foreground">
                      «{r.comment}»
                    </p>
                    <p className="font-medium text-foreground">{r.patient_name}</p>
                  </CardContent>
                </Card>
              </motion.div>
            ))}
          </div>
        )}

        {/* إضافة تقييم حقيقي */}
        <div className="mt-10">
          {showReviewForm ? (
            <ReviewForm onSubmitted={() => setShowReviewForm(false)} />
          ) : (
            <div className="text-center">
              <Button size="lg" variant="outline" onClick={() => setShowReviewForm(true)}>
                أضف تقييمك
              </Button>
            </div>
          )}
        </div>
      </section>

      <footer className="border-t border-border bg-card">
        <div className="container flex flex-col items-center justify-between gap-4 py-8 text-sm text-muted-foreground sm:flex-row">
          <p>© {new Date().getFullYear()} عيادة الطبيب مشهور. جميع الحقوق محفوظة.</p>
          <p>صُمّم بعناية لراحة مرضانا.</p>
        </div>
      </footer>
    </div>
  );
}

function SectionTitle({
  eyebrow,
  title,
  subtitle,
}: {
  eyebrow: string;
  title: string;
  subtitle: string;
}) {
  return (
    <div className="mx-auto max-w-2xl text-center">
      <span className="text-sm font-semibold uppercase tracking-wide text-primary">
        {eyebrow}
      </span>
      <h2 className="mt-2 font-display text-3xl font-extrabold text-balance">{title}</h2>
      <p className="mt-3 text-muted-foreground">{subtitle}</p>
    </div>
  );
}

/** بطاقة قبل/بعد تفاعلية — تمرير المؤشر يكشف صورة "بعد" */
function BeforeAfterCard({ caseStudy }: { caseStudy: CaseStudy }) {
  const [reveal, setReveal] = useState(50);
  const placeholder =
    "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='600' height='400'%3E%3Crect width='100%25' height='100%25' fill='%23e2e8f0'/%3E%3C/svg%3E";

  return (
    <Card className="overflow-hidden">
      <div className="relative aspect-[3/2] select-none">
        <img
          src={caseStudy.after_image_url ?? placeholder}
          alt="بعد"
          className="absolute inset-0 size-full object-cover"
        />
        <div
          className="absolute inset-0 overflow-hidden"
          style={{ clipPath: `inset(0 0 0 ${100 - reveal}%)` }}
        >
          <img
            src={caseStudy.before_image_url ?? placeholder}
            alt="قبل"
            className="size-full object-cover"
          />
        </div>
        <input
          type="range"
          min={0}
          max={100}
          value={reveal}
          onChange={(e) => setReveal(Number(e.target.value))}
          aria-label="مقارنة قبل وبعد"
          className="absolute inset-x-0 bottom-3 mx-auto w-[90%] cursor-ew-resize accent-primary"
        />
        <span className="absolute right-3 top-3 rounded bg-foreground/70 px-2 py-0.5 text-xs text-background">
          قبل
        </span>
        <span className="absolute left-3 top-3 rounded bg-primary px-2 py-0.5 text-xs text-primary-foreground">
          بعد
        </span>
      </div>
      <CardContent className="space-y-1 p-4">
        <h3 className="font-display font-bold">{caseStudy.title}</h3>
        {caseStudy.description && (
          <p className="text-sm text-muted-foreground">{caseStudy.description}</p>
        )}
      </CardContent>
    </Card>
  );
}
