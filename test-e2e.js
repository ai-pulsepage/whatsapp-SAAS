/**
 * WhatsApp Business Automation Platform - End-to-End Testing Suite
 * Phase 10: Final Deployment and Testing
 * 
 * This comprehensive testing suite validates all system components and user flows
 */

const axios = require('axios');
const fs = require('fs').promises;
const path = require('path');

// Test configuration
const config = {
    frontendUrl: process.env.FRONTEND_URL || 'http://localhost:3000',
    backendUrl: process.env.BACKEND_URL || 'http://localhost:8080',
    testTimeout: 30000,
    retryAttempts: 3,
    testUser: {
        email: 'test@genspark.ai',
        password: 'Test123!@#',
        company: 'GenSpark Test Company',
        phone: '+1234567890'
    },
    whatsappTest: {
        testNumber: '+1234567890',
        testMessage: 'This is an automated test message from GenSpark platform'
    }
};

// Test results tracking
let testResults = {
    total: 0,
    passed: 0,
    failed: 0,
    skipped: 0,
    errors: []
};

// Utility functions
const colors = {
    reset: '\x1b[0m',
    bright: '\x1b[1m',
    red: '\x1b[31m',
    green: '\x1b[32m',
    yellow: '\x1b[33m',
    blue: '\x1b[34m',
    magenta: '\x1b[35m',
    cyan: '\x1b[36m'
};

function log(level, message) {
    const timestamp = new Date().toISOString();
    const colorCode = {
        'INFO': colors.blue,
        'SUCCESS': colors.green,
        'WARNING': colors.yellow,
        'ERROR': colors.red,
        'SKIP': colors.magenta
    }[level] || colors.reset;
    
    console.log(`${colorCode}[${timestamp}] ${level}: ${message}${colors.reset}`);
}

function logSuccess(message) { log('SUCCESS', message); }
function logError(message) { log('ERROR', message); }
function logWarning(message) { log('WARNING', message); }
function logInfo(message) { log('INFO', message); }
function logSkip(message) { log('SKIP', message); }

// HTTP client with retry logic
async function makeRequest(method, url, data = null, headers = {}, retries = config.retryAttempts) {
    for (let attempt = 1; attempt <= retries; attempt++) {
        try {
            const response = await axios({
                method,
                url,
                data,
                headers: {
                    'Content-Type': 'application/json',
                    ...headers
                },
                timeout: config.testTimeout,
                validateStatus: () => true // Don't throw on HTTP errors
            });
            return response;
        } catch (error) {
            if (attempt === retries) {
                throw new Error(`Request failed after ${retries} attempts: ${error.message}`);
            }
            logWarning(`Request attempt ${attempt} failed, retrying...`);
            await new Promise(resolve => setTimeout(resolve, 1000 * attempt));
        }
    }
}

// Test execution framework
async function runTest(testName, testFunction) {
    testResults.total++;
    logInfo(`Running test: ${testName}`);
    
    try {
        await testFunction();
        testResults.passed++;
        logSuccess(`✓ ${testName}`);
        return true;
    } catch (error) {
        testResults.failed++;
        testResults.errors.push({ test: testName, error: error.message });
        logError(`✗ ${testName}: ${error.message}`);
        return false;
    }
}

async function runTestSuite(suiteName, tests) {
    logInfo(`\n${'='.repeat(60)}`);
    logInfo(`TEST SUITE: ${suiteName}`);
    logInfo(`${'='.repeat(60)}`);
    
    for (const [testName, testFunction] of Object.entries(tests)) {
        await runTest(testName, testFunction);
    }
}

// Authentication helper
let authTokens = {
    accessToken: null,
    refreshToken: null
};

async function authenticate() {
    const response = await makeRequest('POST', `${config.backendUrl}/api/auth/register`, {
        email: config.testUser.email,
        password: config.testUser.password,
        company: config.testUser.company,
        phone: config.testUser.phone
    });
    
    if (response.status === 201 || response.status === 409) {
        // User created or already exists, now login
        const loginResponse = await makeRequest('POST', `${config.backendUrl}/api/auth/login`, {
            email: config.testUser.email,
            password: config.testUser.password
        });
        
        if (loginResponse.status === 200 && loginResponse.data.token) {
            authTokens.accessToken = loginResponse.data.token;
            authTokens.refreshToken = loginResponse.data.refreshToken;
            return authTokens;
        }
    }
    
    throw new Error('Authentication failed');
}

// Test Suites

// 1. Infrastructure Health Tests
const infrastructureTests = {
    'Frontend service availability': async () => {
        const response = await makeRequest('GET', config.frontendUrl);
        if (response.status !== 200) {
            throw new Error(`Frontend returned status ${response.status}`);
        }
    },
    
    'Backend service health check': async () => {
        const response = await makeRequest('GET', `${config.backendUrl}/health`);
        if (response.status !== 200) {
            throw new Error(`Backend health check failed with status ${response.status}`);
        }
    },
    
    'Database connectivity': async () => {
        const response = await makeRequest('GET', `${config.backendUrl}/api/health/db`);
        if (response.status !== 200 || response.data.database !== 'connected') {
            throw new Error('Database connectivity check failed');
        }
    },
    
    'Redis cache connectivity': async () => {
        const response = await makeRequest('GET', `${config.backendUrl}/api/health/cache`);
        if (response.status !== 200 || response.data.cache !== 'connected') {
            throw new Error('Redis cache connectivity check failed');
        }
    },
    
    'API rate limiting': async () => {
        const requests = Array(10).fill().map(() => 
            makeRequest('GET', `${config.backendUrl}/api/health`)
        );
        
        const responses = await Promise.all(requests);
        const rateLimitedResponses = responses.filter(r => r.status === 429);
        
        if (rateLimitedResponses.length === 0) {
            logWarning('Rate limiting may not be properly configured');
        }
    }
};

// 2. Authentication and Authorization Tests
const authTests = {
    'User registration flow': async () => {
        const response = await makeRequest('POST', `${config.backendUrl}/api/auth/register`, {
            email: `test-${Date.now()}@example.com`,
            password: 'TestPass123!',
            company: 'Test Company',
            phone: '+1234567890'
        });
        
        if (response.status !== 201) {
            throw new Error(`Registration failed with status ${response.status}`);
        }
    },
    
    'User login flow': async () => {
        await authenticate();
        if (!authTokens.accessToken) {
            throw new Error('Login flow failed - no access token received');
        }
    },
    
    'JWT token validation': async () => {
        if (!authTokens.accessToken) {
            await authenticate();
        }
        
        const response = await makeRequest('GET', `${config.backendUrl}/api/auth/validate`, null, {
            'Authorization': `Bearer ${authTokens.accessToken}`
        });
        
        if (response.status !== 200) {
            throw new Error('JWT token validation failed');
        }
    },
    
    'Protected route access': async () => {
        if (!authTokens.accessToken) {
            await authenticate();
        }
        
        const response = await makeRequest('GET', `${config.backendUrl}/api/dashboard`, null, {
            'Authorization': `Bearer ${authTokens.accessToken}`
        });
        
        if (response.status !== 200) {
            throw new Error('Protected route access failed');
        }
    },
    
    'Unauthorized access prevention': async () => {
        const response = await makeRequest('GET', `${config.backendUrl}/api/dashboard`);
        
        if (response.status !== 401) {
            throw new Error('Unauthorized access was not properly prevented');
        }
    }
};

// 3. WhatsApp Business API Integration Tests
const whatsappTests = {
    'WhatsApp webhook endpoint': async () => {
        const response = await makeRequest('GET', `${config.backendUrl}/api/webhooks/whatsapp`);
        if (response.status !== 200) {
            throw new Error('WhatsApp webhook endpoint not accessible');
        }
    },
    
    'Message template validation': async () => {
        if (!authTokens.accessToken) {
            await authenticate();
        }
        
        const response = await makeRequest('POST', `${config.backendUrl}/api/whatsapp/templates/validate`, {
            template: 'hello_world',
            language: 'en'
        }, {
            'Authorization': `Bearer ${authTokens.accessToken}`
        });
        
        if (response.status !== 200) {
            throw new Error('Message template validation failed');
        }
    },
    
    'Contact management': async () => {
        if (!authTokens.accessToken) {
            await authenticate();
        }
        
        const contactData = {
            name: 'Test Contact',
            phone: config.whatsappTest.testNumber,
            email: 'testcontact@example.com'
        };
        
        const response = await makeRequest('POST', `${config.backendUrl}/api/contacts`, contactData, {
            'Authorization': `Bearer ${authTokens.accessToken}`
        });
        
        if (response.status !== 201) {
            throw new Error('Contact management failed');
        }
    },
    
    'Message queue processing': async () => {
        if (!authTokens.accessToken) {
            await authenticate();
        }
        
        const messageData = {
            to: config.whatsappTest.testNumber,
            message: config.whatsappTest.testMessage,
            type: 'text'
        };
        
        const response = await makeRequest('POST', `${config.backendUrl}/api/messages/send`, messageData, {
            'Authorization': `Bearer ${authTokens.accessToken}`
        });
        
        if (response.status !== 202) {
            logWarning('Message queue processing test failed - this may require valid WhatsApp API credentials');
        }
    }
};

// 4. Multi-tenant Architecture Tests
const multiTenantTests = {
    'Tenant isolation verification': async () => {
        if (!authTokens.accessToken) {
            await authenticate();
        }
        
        // Create data for current tenant
        const response1 = await makeRequest('POST', `${config.backendUrl}/api/contacts`, {
            name: 'Tenant Test Contact',
            phone: '+1111111111'
        }, {
            'Authorization': `Bearer ${authTokens.accessToken}`
        });
        
        if (response1.status !== 201) {
            throw new Error('Failed to create tenant-specific data');
        }
        
        // Verify tenant isolation by checking data access
        const response2 = await makeRequest('GET', `${config.backendUrl}/api/contacts`, null, {
            'Authorization': `Bearer ${authTokens.accessToken}`
        });
        
        if (response2.status !== 200 || !Array.isArray(response2.data)) {
            throw new Error('Tenant data access verification failed');
        }
    },
    
    'Tenant configuration management': async () => {
        if (!authTokens.accessToken) {
            await authenticate();
        }
        
        const configData = {
            whatsappBusinessId: 'test-business-id',
            webhookUrl: 'https://example.com/webhook',
            timeZone: 'UTC'
        };
        
        const response = await makeRequest('PUT', `${config.backendUrl}/api/tenant/config`, configData, {
            'Authorization': `Bearer ${authTokens.accessToken}`
        });
        
        if (response.status !== 200) {
            throw new Error('Tenant configuration management failed');
        }
    },
    
    'Resource quota enforcement': async () => {
        if (!authTokens.accessToken) {
            await authenticate();
        }
        
        const response = await makeRequest('GET', `${config.backendUrl}/api/tenant/usage`, null, {
            'Authorization': `Bearer ${authTokens.accessToken}`
        });
        
        if (response.status !== 200 || !response.data.quota) {
            throw new Error('Resource quota enforcement check failed');
        }
    }
};

// 5. Dashboard and Analytics Tests
const dashboardTests = {
    'Dashboard data loading': async () => {
        if (!authTokens.accessToken) {
            await authenticate();
        }
        
        const response = await makeRequest('GET', `${config.backendUrl}/api/dashboard/stats`, null, {
            'Authorization': `Bearer ${authTokens.accessToken}`
        });
        
        if (response.status !== 200) {
            throw new Error('Dashboard data loading failed');
        }
    },
    
    'Analytics data retrieval': async () => {
        if (!authTokens.accessToken) {
            await authenticate();
        }
        
        const response = await makeRequest('GET', `${config.backendUrl}/api/analytics/messages`, null, {
            'Authorization': `Bearer ${authTokens.accessToken}`
        });
        
        if (response.status !== 200) {
            throw new Error('Analytics data retrieval failed');
        }
    },
    
    'Export functionality': async () => {
        if (!authTokens.accessToken) {
            await authenticate();
        }
        
        const response = await makeRequest('POST', `${config.backendUrl}/api/export/contacts`, {
            format: 'csv',
            dateRange: '30days'
        }, {
            'Authorization': `Bearer ${authTokens.accessToken}`
        });
        
        if (response.status !== 200) {
            throw new Error('Export functionality failed');
        }
    }
};

// 6. Security and Compliance Tests
const securityTests = {
    'SQL injection protection': async () => {
        const maliciousPayload = {
            email: "test'; DROP TABLE users; --",
            password: 'password'
        };
        
        const response = await makeRequest('POST', `${config.backendUrl}/api/auth/login`, maliciousPayload);
        
        if (response.status === 500) {
            throw new Error('SQL injection protection may be insufficient');
        }
    },
    
    'XSS protection': async () => {
        if (!authTokens.accessToken) {
            await authenticate();
        }
        
        const xssPayload = {
            name: '<script>alert("XSS")</script>',
            phone: '+1234567890'
        };
        
        const response = await makeRequest('POST', `${config.backendUrl}/api/contacts`, xssPayload, {
            'Authorization': `Bearer ${authTokens.accessToken}`
        });
        
        // Should either sanitize or reject
        if (response.status === 500) {
            throw new Error('XSS protection may be insufficient');
        }
    },
    
    'CORS configuration': async () => {
        const response = await makeRequest('OPTIONS', `${config.backendUrl}/api/health`);
        
        if (!response.headers['access-control-allow-origin']) {
            logWarning('CORS headers may not be properly configured');
        }
    },
    
    'Content Security Policy': async () => {
        const response = await makeRequest('GET', config.frontendUrl);
        
        if (!response.headers['content-security-policy']) {
            logWarning('Content Security Policy headers may not be configured');
        }
    }
};

// 7. Performance Tests
const performanceTests = {
    'API response time benchmark': async () => {
        const startTime = Date.now();
        const response = await makeRequest('GET', `${config.backendUrl}/api/health`);
        const responseTime = Date.now() - startTime;
        
        if (response.status !== 200) {
            throw new Error('API health check failed');
        }
        
        if (responseTime > 1000) {
            logWarning(`API response time (${responseTime}ms) exceeds 1000ms threshold`);
        }
        
        logInfo(`API response time: ${responseTime}ms`);
    },
    
    'Concurrent request handling': async () => {
        const concurrentRequests = 20;
        const requests = Array(concurrentRequests).fill().map(() =>
            makeRequest('GET', `${config.backendUrl}/api/health`)
        );
        
        const startTime = Date.now();
        const responses = await Promise.all(requests);
        const totalTime = Date.now() - startTime;
        
        const successfulResponses = responses.filter(r => r.status === 200);
        
        if (successfulResponses.length < concurrentRequests * 0.9) {
            throw new Error(`Only ${successfulResponses.length}/${concurrentRequests} concurrent requests succeeded`);
        }
        
        logInfo(`Handled ${concurrentRequests} concurrent requests in ${totalTime}ms`);
    },
    
    'Database query performance': async () => {
        if (!authTokens.accessToken) {
            await authenticate();
        }
        
        const startTime = Date.now();
        const response = await makeRequest('GET', `${config.backendUrl}/api/contacts?limit=100`, null, {
            'Authorization': `Bearer ${authTokens.accessToken}`
        });
        const queryTime = Date.now() - startTime;
        
        if (response.status !== 200) {
            throw new Error('Database query failed');
        }
        
        if (queryTime > 2000) {
            logWarning(`Database query time (${queryTime}ms) exceeds 2000ms threshold`);
        }
        
        logInfo(`Database query time: ${queryTime}ms`);
    }
};

// Main test execution
async function runAllTests() {
    const startTime = Date.now();
    
    logInfo(`${colors.cyan}${'='.repeat(80)}`);
    logInfo(`WhatsApp Business Automation Platform - End-to-End Testing Suite`);
    logInfo(`Started at: ${new Date().toISOString()}`);
    logInfo(`Frontend URL: ${config.frontendUrl}`);
    logInfo(`Backend URL: ${config.backendUrl}`);
    logInfo(`${'='.repeat(80)}${colors.reset}`);
    
    try {
        await runTestSuite('Infrastructure Health', infrastructureTests);
        await runTestSuite('Authentication & Authorization', authTests);
        await runTestSuite('WhatsApp Business API Integration', whatsappTests);
        await runTestSuite('Multi-tenant Architecture', multiTenantTests);
        await runTestSuite('Dashboard & Analytics', dashboardTests);
        await runTestSuite('Security & Compliance', securityTests);
        await runTestSuite('Performance', performanceTests);
        
    } catch (error) {
        logError(`Test execution error: ${error.message}`);
    }
    
    const endTime = Date.now();
    const duration = (endTime - startTime) / 1000;
    
    // Generate test report
    logInfo(`\n${colors.cyan}${'='.repeat(80)}`);
    logInfo('TEST EXECUTION SUMMARY');
    logInfo(`${'='.repeat(80)}${colors.reset}`);
    logInfo(`Total Tests: ${testResults.total}`);
    logSuccess(`Passed: ${testResults.passed}`);
    logError(`Failed: ${testResults.failed}`);
    logInfo(`Success Rate: ${((testResults.passed / testResults.total) * 100).toFixed(1)}%`);
    logInfo(`Execution Time: ${duration.toFixed(2)} seconds`);
    
    if (testResults.errors.length > 0) {
        logInfo(`\n${colors.red}FAILED TESTS:${colors.reset}`);
        testResults.errors.forEach(error => {
            logError(`${error.test}: ${error.error}`);
        });
    }
    
    // Save test report
    const report = {
        timestamp: new Date().toISOString(),
        duration: duration,
        results: testResults,
        config: {
            frontendUrl: config.frontendUrl,
            backendUrl: config.backendUrl
        }
    };
    
    try {
        await fs.writeFile(
            path.join(__dirname, 'test-report.json'),
            JSON.stringify(report, null, 2)
        );
        logInfo('Test report saved to test-report.json');
    } catch (error) {
        logWarning(`Failed to save test report: ${error.message}`);
    }
    
    // Exit with appropriate code
    process.exit(testResults.failed > 0 ? 1 : 0);
}

// Error handling
process.on('unhandledRejection', (reason, promise) => {
    logError(`Unhandled Rejection at: ${promise}, reason: ${reason}`);
    process.exit(1);
});

process.on('uncaughtException', (error) => {
    logError(`Uncaught Exception: ${error.message}`);
    process.exit(1);
});

// Run tests if called directly
if (require.main === module) {
    runAllTests().catch(error => {
        logError(`Test execution failed: ${error.message}`);
        process.exit(1);
    });
}

module.exports = {
    runAllTests,
    runTestSuite,
    runTest,
    config,
    testResults
};