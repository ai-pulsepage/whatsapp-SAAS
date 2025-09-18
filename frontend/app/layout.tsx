/*
 * GenSpark AI - Root Layout Component
 * Main layout wrapper for the Next.js application
 */

import type { Metadata } from 'next';
import { Inter } from 'next/font/google';
import './globals.css';
import { AuthProvider } from '@/providers/AuthProvider';
import { QueryProvider } from '@/providers/QueryProvider';
import { ToastProvider } from '@/providers/ToastProvider';
import { SocketProvider } from '@/providers/SocketProvider';

const inter = Inter({ subsets: ['latin'] });

export const metadata: Metadata = {
  title: 'GenSpark AI - WhatsApp Business Automation',
  description: 'AI-powered WhatsApp Business automation platform for enhanced customer engagement',
  keywords: 'WhatsApp, Business, Automation, AI, Customer Service, Chat Bot',
  authors: [{ name: 'GenSpark AI Team' }],
  creator: 'GenSpark AI',
  publisher: 'GenSpark AI',
  robots: 'index, follow',
  viewport: 'width=device-width, initial-scale=1',
  themeColor: '#0070f3',
  manifest: '/manifest.json',
  icons: {
    icon: '/favicon.ico',
    shortcut: '/favicon-16x16.png',
    apple: '/apple-touch-icon.png',
  },
  openGraph: {
    type: 'website',
    locale: 'en_US',
    url: 'https://app.genspark.ai',
    title: 'GenSpark AI - WhatsApp Business Automation',
    description: 'AI-powered WhatsApp Business automation platform for enhanced customer engagement',
    siteName: 'GenSpark AI',
    images: [
      {
        url: '/og-image.png',
        width: 1200,
        height: 630,
        alt: 'GenSpark AI Platform',
      },
    ],
  },
  twitter: {
    card: 'summary_large_image',
    site: '@GenSparkAI',
    creator: '@GenSparkAI',
    title: 'GenSpark AI - WhatsApp Business Automation',
    description: 'AI-powered WhatsApp Business automation platform for enhanced customer engagement',
    images: ['/twitter-image.png'],
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        {/* Preconnect to external domains */}
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
        <link rel="preconnect" href="https://api.genspark.ai" />
        
        {/* Analytics and monitoring scripts */}
        {process.env.NEXT_PUBLIC_GA_MEASUREMENT_ID && (
          <>
            <script
              async
              src={`https://www.googletagmanager.com/gtag/js?id=${process.env.NEXT_PUBLIC_GA_MEASUREMENT_ID}`}
            />
            <script
              dangerouslySetInnerHTML={{
                __html: `
                  window.dataLayer = window.dataLayer || [];
                  function gtag(){dataLayer.push(arguments);}
                  gtag('js', new Date());
                  gtag('config', '${process.env.NEXT_PUBLIC_GA_MEASUREMENT_ID}', {
                    page_title: document.title,
                    page_location: window.location.href,
                  });
                `,
              }}
            />
          </>
        )}
        
        {/* Sentry error tracking */}
        {process.env.NEXT_PUBLIC_SENTRY_DSN && (
          <script
            dangerouslySetInnerHTML={{
              __html: `
                (function() {
                  // Sentry initialization will be handled by the Sentry SDK
                  console.log('Sentry DSN configured');
                })();
              `,
            }}
          />
        )}
      </head>
      <body className={inter.className} suppressHydrationWarning>
        <QueryProvider>
          <AuthProvider>
            <SocketProvider>
              <ToastProvider>
                <div id="root">
                  {children}
                </div>
                
                {/* Modals and overlays */}
                <div id="modal-root" />
                <div id="tooltip-root" />
                <div id="dropdown-root" />
              </ToastProvider>
            </SocketProvider>
          </AuthProvider>
        </QueryProvider>

        {/* Service Worker Registration */}
        <script
          dangerouslySetInnerHTML={{
            __html: `
              if ('serviceWorker' in navigator) {
                window.addEventListener('load', function() {
                  navigator.serviceWorker.register('/sw.js')
                    .then(function(registration) {
                      console.log('SW registered: ', registration);
                    })
                    .catch(function(registrationError) {
                      console.log('SW registration failed: ', registrationError);
                    });
                });
              }
            `,
          }}
        />
      </body>
    </html>
  );
}