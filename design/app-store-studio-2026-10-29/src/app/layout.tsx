import type { Metadata } from "next";

import "./globals.css";



export const metadata: Metadata = {
  title: "Masso · App Store Studio",
  description: "Design and export App Store + Google Play screenshots.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="masso-font">{children}</body>
    </html>
  );
}
