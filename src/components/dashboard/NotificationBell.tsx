import { useState } from "react";
import { Bell, CheckCheck } from "lucide-react";
import { motion, AnimatePresence } from "framer-motion";
import { useNotifications } from "@/hooks/useNotifications";
import { formatDateAr } from "@/lib/utils";
import { Button } from "@/components/ui/button";

export function NotificationBell() {
  const { items, unreadCount, markAsRead, markAllAsRead } = useNotifications();
  const [open, setOpen] = useState(false);

  return (
    <div className="relative">
      <Button
        variant="ghost"
        size="icon"
        onClick={() => setOpen((o) => !o)}
        aria-label="الإشعارات"
        className="relative"
      >
        <Bell className="size-5" />
        {unreadCount > 0 && (
          <span className="absolute -left-0.5 -top-0.5 flex size-4 items-center justify-center rounded-full bg-destructive text-[10px] font-bold text-destructive-foreground">
            {unreadCount > 9 ? "9+" : unreadCount}
          </span>
        )}
      </Button>

      <AnimatePresence>
        {open && (
          <>
            <div className="fixed inset-0 z-40" onClick={() => setOpen(false)} />
            <motion.div
              initial={{ opacity: 0, y: -8, scale: 0.98 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={{ opacity: 0, y: -8, scale: 0.98 }}
              className="absolute left-0 z-50 mt-2 w-80 overflow-hidden rounded-xl border border-border bg-card shadow-xl"
            >
              <div className="flex items-center justify-between border-b border-border p-3">
                <span className="font-display font-bold">الإشعارات</span>
                {unreadCount > 0 && (
                  <button
                    onClick={markAllAsRead}
                    className="flex items-center gap-1 text-xs text-primary hover:underline"
                  >
                    <CheckCheck className="size-3.5" />
                    تعليم الكل كمقروء
                  </button>
                )}
              </div>
              <div className="max-h-96 overflow-y-auto">
                {items.length === 0 ? (
                  <p className="p-6 text-center text-sm text-muted-foreground">
                    لا توجد إشعارات
                  </p>
                ) : (
                  items.map((n) => (
                    <button
                      key={n.id}
                      onClick={() => markAsRead(n.id)}
                      className={`block w-full border-b border-border p-3 text-right transition-colors hover:bg-accent/40 ${
                        n.is_read ? "opacity-60" : "bg-accent/20"
                      }`}
                    >
                      <div className="flex items-start gap-2">
                        {!n.is_read && (
                          <span className="mt-1.5 size-2 shrink-0 rounded-full bg-primary" />
                        )}
                        <div className="space-y-0.5">
                          <p className="text-sm font-semibold">{n.title}</p>
                          <p className="text-xs leading-relaxed text-muted-foreground">
                            {n.message}
                          </p>
                          <p className="text-[10px] text-muted-foreground/70">
                            {formatDateAr(n.created_at)}
                          </p>
                        </div>
                      </div>
                    </button>
                  ))
                )}
              </div>
            </motion.div>
          </>
        )}
      </AnimatePresence>
    </div>
  );
}
