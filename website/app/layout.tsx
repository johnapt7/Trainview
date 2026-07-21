import type { Metadata } from "next";
import Script from "next/script";

export const metadata: Metadata = {
  title: "Trainview — Live trains, clearly",
  description: "A clear, live view of departures and arrivals across the British rail network.",
  openGraph: {
    title: "Trainview — Live trains, clearly",
    description: "Platforms, delays and every stop along the way—presented clearly, updated live.",
    images: ["/og.jpg"],
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "Trainview — Live trains, clearly",
    description: "Platforms, delays and every stop along the way—presented clearly, updated live.",
    images: ["/og.jpg"],
  },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en-GB">
      <head>
        <meta name="theme-color" content="#f0ead8" />
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
        <link
          href="https://fonts.googleapis.com/css2?family=DM+Mono:wght@400;500&amp;family=DM+Sans:opsz,wght@9..40,400;9..40,500;9..40,600&amp;display=swap"
          rel="stylesheet"
        />
        <link rel="stylesheet" href="/styles.css?v=ios-redesign" />
      </head>
      <body>
        {children}
        <Script src="/config.js" strategy="beforeInteractive" />
        <Script src="/app.js" strategy="afterInteractive" />
      </body>
    </html>
  );
}
