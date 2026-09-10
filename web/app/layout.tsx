import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Hinge · A little bend for your Mac",
  description: "Your desktop follows your lid. A tiny Mac app that softly bends and blurs your screen as you close your MacBook.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
