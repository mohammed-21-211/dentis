import { Component, type ErrorInfo, type ReactNode } from "react";

interface Props {
  children: ReactNode;
}
interface State {
  hasError: boolean;
  message: string;
}

/**
 * حدّ أخطاء عام — يمنع «الصفحة البيضاء» عند حدوث خطأ تشغيلي،
 * ويعرض رسالة عربية واضحة بدلاً منها.
 */
export class ErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false, message: "" };

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, message: error.message };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    // تسجيل للمطوّر في الكونسول
    console.error("[ErrorBoundary]", error, info);
  }

  render() {
    if (this.state.hasError) {
      return (
        <div className="flex min-h-screen items-center justify-center bg-background px-4">
          <div className="w-full max-w-md rounded-xl border border-destructive/30 bg-card p-6 text-center shadow-sm">
            <h1 className="mb-2 font-display text-xl font-extrabold text-destructive">
              حدث خطأ غير متوقع
            </h1>
            <p className="mb-4 text-sm text-muted-foreground">
              نأسف، واجه التطبيق مشكلة. حاول تحديث الصفحة.
            </p>
            <pre className="mb-4 overflow-x-auto rounded-lg bg-muted p-3 text-left text-xs text-muted-foreground" dir="ltr">
              {this.state.message}
            </pre>
            <button
              onClick={() => window.location.reload()}
              className="rounded-lg bg-primary px-5 py-2 text-sm font-medium text-primary-foreground hover:bg-primary/90"
            >
              تحديث الصفحة
            </button>
          </div>
        </div>
      );
    }
    return this.props.children;
  }
}
