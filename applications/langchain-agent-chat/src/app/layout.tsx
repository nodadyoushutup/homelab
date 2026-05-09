import type { Metadata } from "next";
import "./globals.css";
import React from "react";
import { NuqsAdapter } from "nuqs/adapters/next/app";
import { ThemeProvider } from "@/providers/theme";
import { APP_DISPLAY_NAME } from "@/lib/branding";
import { DevToolsThemeBridge } from "@/components/devtools-theme-bridge";

export const metadata: Metadata = {
  title: APP_DISPLAY_NAME,
  description: `${APP_DISPLAY_NAME} for the homelab LangGraph deployment`,
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      suppressHydrationWarning
    >
      <body>
        <ThemeProvider
          attribute="class"
          defaultTheme="system"
          enableSystem
          storageKey="nodad-agent-chat-theme"
          disableTransitionOnChange
        >
          <DevToolsThemeBridge />
          <NuqsAdapter>{children}</NuqsAdapter>
        </ThemeProvider>
      </body>
    </html>
  );
}
