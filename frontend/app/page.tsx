/*
 * GenSpark AI - Home Page
 * Main landing/dashboard page for authenticated users
 */

'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/hooks/useAuth';
import { useOrganization } from '@/hooks/useOrganization';
import LoadingSpinner from '@/components/ui/LoadingSpinner';
import DashboardLayout from '@/components/layout/DashboardLayout';
import StatsGrid from '@/components/dashboard/StatsGrid';
import RecentMessages from '@/components/dashboard/RecentMessages';
import AutomationOverview from '@/components/dashboard/AutomationOverview';
import QuickActions from '@/components/dashboard/QuickActions';
import WelcomeCard from '@/components/dashboard/WelcomeCard';

export default function HomePage() {
  const router = useRouter();
  const { user, isLoading: authLoading, isAuthenticated } = useAuth();
  const { organization, isLoading: orgLoading } = useOrganization();
  const [isInitialized, setIsInitialized] = useState(false);

  useEffect(() => {
    // Redirect to login if not authenticated
    if (!authLoading && !isAuthenticated) {
      router.push('/auth/login');
      return;
    }

    // Redirect to onboarding if no organization
    if (!orgLoading && isAuthenticated && !organization) {
      router.push('/onboarding');
      return;
    }

    if (!authLoading && !orgLoading && isAuthenticated && organization) {
      setIsInitialized(true);
    }
  }, [authLoading, orgLoading, isAuthenticated, organization, router]);

  // Show loading spinner while initializing
  if (authLoading || orgLoading || !isInitialized) {
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center">
        <LoadingSpinner size="large" />
      </div>
    );
  }

  return (
    <DashboardLayout>
      <div className="space-y-6">
        {/* Welcome Section */}
        <div className="bg-white shadow rounded-lg">
          <WelcomeCard user={user} organization={organization} />
        </div>

        {/* Stats Grid */}
        <StatsGrid organizationId={organization.id} />

        {/* Main Content Grid */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Left Column - Recent Messages & Automation */}
          <div className="lg:col-span-2 space-y-6">
            <RecentMessages organizationId={organization.id} />
            <AutomationOverview organizationId={organization.id} />
          </div>

          {/* Right Column - Quick Actions */}
          <div className="space-y-6">
            <QuickActions organizationId={organization.id} />
            
            {/* Getting Started Card (for new organizations) */}
            {organization.createdAt && 
             new Date() - new Date(organization.createdAt) < 7 * 24 * 60 * 60 * 1000 && (
              <div className="bg-blue-50 border border-blue-200 rounded-lg p-6">
                <h3 className="text-lg font-medium text-blue-900 mb-3">
                  Getting Started
                </h3>
                <div className="space-y-3">
                  <div className="flex items-center text-sm text-blue-800">
                    <div className="w-2 h-2 bg-blue-500 rounded-full mr-3" />
                    Connect your WhatsApp Business account
                  </div>
                  <div className="flex items-center text-sm text-blue-800">
                    <div className="w-2 h-2 bg-blue-500 rounded-full mr-3" />
                    Import your contacts
                  </div>
                  <div className="flex items-center text-sm text-blue-800">
                    <div className="w-2 h-2 bg-blue-500 rounded-full mr-3" />
                    Set up your first automation rule
                  </div>
                </div>
                <button
                  onClick={() => router.push('/setup')}
                  className="mt-4 bg-blue-600 text-white px-4 py-2 rounded-md text-sm font-medium hover:bg-blue-700 transition-colors"
                >
                  Continue Setup
                </button>
              </div>
            )}

            {/* Support Card */}
            <div className="bg-white border border-gray-200 rounded-lg p-6">
              <h3 className="text-lg font-medium text-gray-900 mb-3">
                Need Help?
              </h3>
              <p className="text-sm text-gray-600 mb-4">
                Our support team is here to help you get the most out of GenSpark AI.
              </p>
              <div className="space-y-2">
                <a
                  href="/docs"
                  className="block text-sm text-blue-600 hover:text-blue-800 transition-colors"
                >
                  📚 Documentation
                </a>
                <a
                  href="/support"
                  className="block text-sm text-blue-600 hover:text-blue-800 transition-colors"
                >
                  💬 Contact Support
                </a>
                <a
                  href="/community"
                  className="block text-sm text-blue-600 hover:text-blue-800 transition-colors"
                >
                  👥 Community Forum
                </a>
              </div>
            </div>
          </div>
        </div>

        {/* Performance Insights */}
        <div className="bg-white shadow rounded-lg p-6">
          <h2 className="text-xl font-semibold text-gray-900 mb-4">
            Performance Insights
          </h2>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div className="text-center">
              <div className="text-3xl font-bold text-green-600">↗️ 24%</div>
              <div className="text-sm text-gray-600">Response Rate Improvement</div>
            </div>
            <div className="text-center">
              <div className="text-3xl font-bold text-blue-600">⚡ 12s</div>
              <div className="text-sm text-gray-600">Average Response Time</div>
            </div>
            <div className="text-center">
              <div className="text-3xl font-bold text-purple-600">🤖 89%</div>
              <div className="text-sm text-gray-600">Automation Success Rate</div>
            </div>
          </div>
        </div>
      </div>
    </DashboardLayout>
  );
}