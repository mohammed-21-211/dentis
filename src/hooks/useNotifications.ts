import { useCallback, useEffect, useState } from "react";
import { supabase, clinicDb } from "@/lib/supabase";
import { useAuth } from "@/context/AuthContext";
import type { AppNotification } from "@/types";

/**
 * بث الإشعارات الحيّ (Realtime) لكل مستخدم.
 * يشترك في قناة postgres_changes على جدول notifications المُفلتر بـ user_id،
 * ويحدّث القائمة وعدّاد غير المقروء فورياً.
 */
export function useNotifications() {
  const { user } = useAuth();
  const [items, setItems] = useState<AppNotification[]>([]);
  const [loading, setLoading] = useState(true);

  const unreadCount = items.filter((n) => !n.is_read).length;

  const fetchAll = useCallback(async () => {
    if (!user) return;
    const { data } = await clinicDb
      .from("notifications")
      .select("*")
      .eq("user_id", user.id)
      .order("created_at", { ascending: false })
      .limit(50);
    setItems((data as AppNotification[]) ?? []);
    setLoading(false);
  }, [user]);

  useEffect(() => {
    if (!user) {
      setItems([]);
      setLoading(false);
      return;
    }

    fetchAll();

    const channel = supabase
      .channel(`notifications:${user.id}`)
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "clinic",
          table: "notifications",
          filter: `user_id=eq.${user.id}`,
        },
        (payload) => {
          setItems((prev) => [payload.new as AppNotification, ...prev]);
        },
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [user, fetchAll]);

  const markAsRead = useCallback(async (id: string) => {
    setItems((prev) => prev.map((n) => (n.id === id ? { ...n, is_read: true } : n)));
    await clinicDb.from("notifications").update({ is_read: true }).eq("id", id);
  }, []);

  const markAllAsRead = useCallback(async () => {
    if (!user) return;
    setItems((prev) => prev.map((n) => ({ ...n, is_read: true })));
    await clinicDb
      .from("notifications")
      .update({ is_read: true })
      .eq("user_id", user.id)
      .eq("is_read", false);
  }, [user]);

  return { items, unreadCount, loading, markAsRead, markAllAsRead, refresh: fetchAll };
}
