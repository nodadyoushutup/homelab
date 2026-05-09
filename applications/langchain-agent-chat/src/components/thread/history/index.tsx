import { Button } from "@/components/ui/button";
import { useThreads } from "@/providers/Thread";
import { Thread } from "@langchain/langgraph-sdk";
import { useEffect, useState } from "react";
import type { MouseEvent } from "react";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { faTrashCan } from "@fortawesome/free-solid-svg-icons";

import { getContentString } from "../utils";
import { TooltipIconButton } from "../tooltip-icon-button";
import { useQueryState, parseAsBoolean } from "nuqs";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import { Skeleton } from "@/components/ui/skeleton";
import { PanelRightOpen, PanelRightClose } from "lucide-react";
import { useMediaQuery } from "@/hooks/useMediaQuery";
import { toast } from "sonner";

function ThreadList({
  threads,
  onThreadClick,
}: {
  threads: Thread[];
  onThreadClick?: (threadId: string) => void;
}) {
  const [threadId, setThreadId] = useQueryState("threadId");
  const { deleteThread, setThreads } = useThreads();
  const [deletingThreadId, setDeletingThreadId] = useState<string | null>(null);

  const handleDeleteThread = async (
    e: MouseEvent<HTMLButtonElement>,
    deletedThreadId: string,
  ) => {
    e.preventDefault();
    e.stopPropagation();

    if (!window.confirm("Delete this thread? This cannot be undone.")) return;

    setDeletingThreadId(deletedThreadId);

    try {
      await deleteThread(deletedThreadId);
      setThreads((prev) =>
        prev.filter((thread) => thread.thread_id !== deletedThreadId),
      );
      if (threadId === deletedThreadId) {
        setThreadId(null);
      }
      toast.success("Thread deleted");
    } catch (error) {
      console.error(error);
      toast.error("Failed to delete thread. Please try again.");
    } finally {
      setDeletingThreadId(null);
    }
  };

  return (
    <div className="app-scrollbar flex h-full w-full flex-col items-start justify-start gap-2 overflow-y-scroll">
      {threads.map((t) => {
        let itemText = t.thread_id;
        if (
          typeof t.values === "object" &&
          t.values &&
          "messages" in t.values &&
          Array.isArray(t.values.messages) &&
          t.values.messages?.length > 0
        ) {
          const firstMessage = t.values.messages[0];
          itemText = getContentString(firstMessage.content);
        }
        return (
          <div
            key={t.thread_id}
            className="group flex w-full items-center gap-1 px-1"
          >
            <Button
              variant="ghost"
              className="text-foreground hover:border-border hover:bg-accent/70 min-w-0 flex-1 items-start justify-start rounded-xl border border-transparent px-3 py-2 text-left font-normal"
              onClick={(e) => {
                e.preventDefault();
                onThreadClick?.(t.thread_id);
                if (t.thread_id === threadId) return;
                setThreadId(t.thread_id);
              }}
            >
              <p className="truncate text-ellipsis">{itemText}</p>
            </Button>
            <TooltipIconButton
              aria-label="Delete thread"
              tooltip="Delete thread"
              side="right"
              size="icon"
              className="text-muted-foreground hover:text-destructive size-8 p-2 opacity-60 transition-opacity group-hover:opacity-100 hover:opacity-100 focus-visible:opacity-100"
              disabled={deletingThreadId === t.thread_id}
              onClick={(e) => handleDeleteThread(e, t.thread_id)}
            >
              <FontAwesomeIcon
                icon={faTrashCan}
                className="size-3.5"
              />
            </TooltipIconButton>
          </div>
        );
      })}
    </div>
  );
}

function ThreadHistoryLoading() {
  return (
    <div className="app-scrollbar flex h-full w-full flex-col items-start justify-start gap-2 overflow-y-scroll">
      {Array.from({ length: 30 }).map((_, i) => (
        <Skeleton
          key={`skeleton-${i}`}
          className="h-10 w-[280px]"
        />
      ))}
    </div>
  );
}

export default function ThreadHistory() {
  const isLargeScreen = useMediaQuery("(min-width: 1024px)");
  const [chatHistoryOpen, setChatHistoryOpen] = useQueryState(
    "chatHistoryOpen",
    parseAsBoolean.withDefault(false),
  );

  const { getThreads, threads, setThreads, threadsLoading, setThreadsLoading } =
    useThreads();

  useEffect(() => {
    if (typeof window === "undefined") return;
    setThreadsLoading(true);
    getThreads()
      .then(setThreads)
      .catch(console.error)
      .finally(() => setThreadsLoading(false));
  }, []);

  return (
    <>
      <div className="app-panel shadow-inner-right hidden h-screen w-[300px] shrink-0 flex-col items-start justify-start gap-6 border-r lg:flex">
        <div className="flex w-full items-center justify-between px-4 pt-1.5">
          <Button
            className="hover:bg-accent/70"
            variant="ghost"
            onClick={() => setChatHistoryOpen((p) => !p)}
          >
            {chatHistoryOpen ? (
              <PanelRightOpen className="size-5" />
            ) : (
              <PanelRightClose className="size-5" />
            )}
          </Button>
          <h1 className="text-xl font-semibold tracking-tight">
            Thread History
          </h1>
        </div>
        {threadsLoading ? (
          <ThreadHistoryLoading />
        ) : (
          <ThreadList threads={threads} />
        )}
      </div>
      <div className="lg:hidden">
        <Sheet
          open={!!chatHistoryOpen && !isLargeScreen}
          onOpenChange={(open) => {
            if (isLargeScreen) return;
            setChatHistoryOpen(open);
          }}
        >
          <SheetContent
            side="left"
            className="flex lg:hidden"
          >
            <SheetHeader>
              <SheetTitle>Thread History</SheetTitle>
            </SheetHeader>
            <ThreadList
              threads={threads}
              onThreadClick={() => setChatHistoryOpen((o) => !o)}
            />
          </SheetContent>
        </Sheet>
      </div>
    </>
  );
}
