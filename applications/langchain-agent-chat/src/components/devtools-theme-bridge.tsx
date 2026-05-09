"use client";

import { useTheme } from "next-themes";
import { useCallback, useEffect, useRef } from "react";

const NEXT_DEVTOOLS_THEME_SELECT = 'select[name="theme"]';
const SUPPORTED_THEMES = new Set(["system", "light", "dark"]);
type QueryRoot = Document | ShadowRoot;

function getSupportedTheme(value: string | undefined) {
  const normalized = value?.toLowerCase();
  return normalized && SUPPORTED_THEMES.has(normalized) ? normalized : null;
}

function getDevToolsThemeSelects() {
  const selects: HTMLSelectElement[] = [];

  const walk = (root: QueryRoot) => {
    root
      .querySelectorAll<HTMLSelectElement>(NEXT_DEVTOOLS_THEME_SELECT)
      .forEach((select) => selects.push(select));

    root.querySelectorAll("*").forEach((element) => {
      if (element.shadowRoot) {
        walk(element.shadowRoot);
      }
    });
  };

  walk(document);
  return selects;
}

export function DevToolsThemeBridge() {
  const { theme, setTheme } = useTheme();
  const themeRef = useRef(theme);
  const syncingRef = useRef(false);

  const syncSelectToTheme = useCallback(
    (select: HTMLSelectElement, nextTheme: string) => {
      if (select.value === nextTheme) return;

      syncingRef.current = true;
      select.value = nextTheme;
      select.dispatchEvent(new Event("input", { bubbles: true }));
      select.dispatchEvent(new Event("change", { bubbles: true }));
      window.setTimeout(() => {
        syncingRef.current = false;
      }, 0);
    },
    [],
  );

  useEffect(() => {
    themeRef.current = theme;
  }, [theme]);

  useEffect(() => {
    if (process.env.NODE_ENV !== "development") return;
    const wiredSelects = new WeakSet<HTMLSelectElement>();
    const cleanupSelectListeners: Array<() => void> = [];

    const syncSelect = (select: HTMLSelectElement) => {
      const currentTheme = getSupportedTheme(themeRef.current);
      if (!currentTheme) return;

      syncSelectToTheme(select, currentTheme);
    };

    const handleDevToolsThemeChange = (event: Event) => {
      if (syncingRef.current) return;
      if (!(event.target instanceof HTMLSelectElement)) return;
      if (!event.target.matches(NEXT_DEVTOOLS_THEME_SELECT)) return;

      const nextTheme = getSupportedTheme(event.target.value);
      if (nextTheme && nextTheme !== themeRef.current) {
        setTheme(nextTheme);
      }
    };

    const wireSelect = (select: HTMLSelectElement) => {
      if (wiredSelects.has(select)) return;
      wiredSelects.add(select);
      select.addEventListener("input", handleDevToolsThemeChange);
      select.addEventListener("change", handleDevToolsThemeChange);
      cleanupSelectListeners.push(() => {
        select.removeEventListener("input", handleDevToolsThemeChange);
        select.removeEventListener("change", handleDevToolsThemeChange);
      });
    };

    const syncDevToolsThemeSelects = () => {
      getDevToolsThemeSelects().forEach((select) => {
        wireSelect(select);
        syncSelect(select);
      });
    };

    const observer = new MutationObserver(syncDevToolsThemeSelects);
    observer.observe(document.body, { childList: true, subtree: true });
    const interval = window.setInterval(syncDevToolsThemeSelects, 500);
    syncDevToolsThemeSelects();

    return () => {
      observer.disconnect();
      window.clearInterval(interval);
      cleanupSelectListeners.forEach((cleanup) => cleanup());
    };
  }, [setTheme, syncSelectToTheme]);

  useEffect(() => {
    if (process.env.NODE_ENV !== "development") return;
    const currentTheme = getSupportedTheme(theme);
    if (!currentTheme) return;

    getDevToolsThemeSelects().forEach((select) => {
      syncSelectToTheme(select, currentTheme);
    });
  }, [theme, syncSelectToTheme]);

  return null;
}
