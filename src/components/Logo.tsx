import { cn } from "@/lib/utils";

interface LogoProps {
  /** md للترويسات، lg لصفحات المصادقة */
  size?: "md" | "lg";
  className?: string;
}

/**
 * لوقو العيادة كمكوّن — الأيقونة المتجهة + الاسم كنص HTML حقيقي.
 *
 * لماذا ليس صورة SVG واحدة؟ لأن النص العربي داخل ملف SVG المُحمّل عبر <img>
 * لا يُشكَّل بشكل موثوق (تتفكك الحروف على بعض الأجهزة/الموبايل) ولا تُحمَّل
 * خطوط الويب داخله. بجعل الاسم نص HTML نضمن تشكيلاً عربياً صحيحاً دائماً.
 */
export function Logo({ size = "md", className }: LogoProps) {
  const isLg = size === "lg";

  return (
    <div className={cn("flex items-center gap-2 sm:gap-2.5", className)}>
      <img
        src="/logo-2.svg"
        alt=""
        aria-hidden
        className={cn(
          "w-auto shrink-0",
          isLg ? "h-12 sm:h-16" : "h-8 sm:h-11 md:h-12",
        )}
      />
      <div className="min-w-0 text-right leading-none">
        <span
          className={cn(
            "block truncate font-display font-extrabold text-[#0B3B39]",
            isLg ? "text-xl sm:text-3xl" : "text-sm sm:text-lg md:text-xl",
          )}
        >
          عيادة طبيب الأسنان
        </span>
        <span
          dir="ltr"
          className={cn(
            "mt-0.5 hidden truncate font-medium uppercase tracking-[0.18em] text-[#7A8898] sm:mt-1 sm:block",
            isLg ? "text-[11px]" : "text-[9px] md:text-[10px]",
          )}
        >
          DENTIST CLINIC
        </span>
      </div>
    </div>
  );
}
