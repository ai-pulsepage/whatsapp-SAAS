/**
 * WhatsApp Business Automation Platform - Load Testing Script
 * Phase 10: Final Deployment and Testing
 * 
 * This script performs comprehensive load testing to validate system performance
 * and scalability under various traffic conditions.
 */

const axios = require('axios');
const fs = require('fs').promises;
const path = require('path');

// Load testing configuration
const config = {
    frontendUrl: process.env.FRONTEND_URL || 'http://localhost:3000',
    backendUrl: process.env.BACKEND_URL || 'http://localhost:8080',
    
    // Test parameters
    warmupDuration: 30000,      // 30 seconds warmup
    testDuration: 300000,       // 5 minutes test duration
    rampUpDuration: 60000,      // 1 minute ramp up
    rampDownDuration: 60000,    // 1 minute ramp down
    
    // Load levels
    initialUsers: 1,
    maxConcurrentUsers: 100,
    requestsPerSecond: 50,
    
    // Performance thresholds
    maxResponseTime: 2000,      // 2 seconds
    maxErrorRate: 0.05,         // 5%
    minThroughput: 10,          // 10 requests/second
    
    // Test scenarios
    scenarios: {
        light: { users: 10, rps: 5, duration: 60000 },
        normal: { users: 50, rps: 25, duration: 180000 },
        heavy: { users: 100, rps: 50, duration: 300000 },
        stress: { users: 200, rps: 100, duration: 120000 }
    },
    
    // Authentication
    testUser: {
        email: 'loadtest@genspark.ai',
        password: 'LoadTest123!@#',
        company: 'Load Test Company'
    }
};

// Test results tracking
let testResults = {
    scenarios: {},
    summary: {
        totalRequests: 0,
        successfulRequests: 0,
        failedRequests: 0,
        averageResponseTime: 0,
        minResponseTime: Infinity,
        maxResponseTime: 0,
        throughput: 0,
        errorRate: 0,
        startTime: null,
        endTime: null,
        duration: 0
    },
    errors: [],
    responseTimes: [],
    timestamps: []
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
        'LOAD': colors.magenta,
        'PERF': colors.cyan
    }[level] || colors.reset;
    
    console.log(`${colorCode}[${timestamp}] ${level}: ${message}${colors.reset}`);
}

// Statistics calculation
class PerformanceStats {
    constructor() {
        this.responseTimes = [];
        this.requests = 0;
        this.errors = 0;
        this.startTime = null;
        this.endTime = null;
    }
    
    addRequest(responseTime, isError = false) {
        this.requests++;
        if (isError) {
            this.errors++;
        } else {
            this.responseTimes.push(responseTime);
        }
        
        if (!this.startTime) {
            this.startTime = Date.now();
        }
        this.endTime = Date.now();
    }
    
    getStats() {
        const duration = (this.endTime - this.startTime) / 1000; // seconds
        const sortedTimes = this.responseTimes.sort((a, b) => a - b);
        
        return {
            totalRequests: this.requests,
            successfulRequests: this.requests - this.errors,
            failedRequests: this.errors,
            errorRate: this.errors / this.requests,
            throughput: this.requests / duration,
            duration: duration,
            responseTime: {
                min: Math.min(...this.responseTimes) || 0,
                max: Math.max(...this.responseTimes) || 0,
                average: this.responseTimes.reduce((a, b) => a + b, 0) / this.responseTimes.length || 0,
                p50: this.percentile(sortedTimes, 0.5),
                p95: this.percentile(sortedTimes, 0.95),
                p99: this.percentile(sortedTimes, 0.99)
            }
        };
    }
    
    percentile(sortedArray, percentile) {
        if (sortedArray.length === 0) return 0;
        const index = Math.ceil(sortedArray.length * percentile) - 1;
        return sortedArray[Math.max(0, Math.min(index, sortedArray.length - 1))];
    }
}

// HTTP client with performance tracking
async function makeLoadTestRequest(method, url, data = null, headers = {}) {
    const startTime = Date.now();
    let isError = false;
    let response = null;
    
    try {
        response = await axios({
            method,
            url,
            data,
            headers: {
                'Content-Type': 'application/json',
                ...headers
            },
            timeout: config.maxResponseTime * 2,
            validateStatus: () => true // Don't throw on HTTP errors
        });
        
        isError = response.status >= 400;
        
    } catch (error) {
        isError = true;
        response = { status: 0, statusText: error.message };
    }
    
    const responseTime = Date.now() - startTime;
    
    return {
        response,
        responseTime,
        isError,
        timestamp: startTime
    };
}

// Authentication helper for load testing
let authToken = null;
async function authenticate() {
    if (authToken) return authToken;
    
    try {
        // Register test user
        await makeLoadTestRequest('POST', `${config.backendUrl}/api/auth/register`, {
            email: config.testUser.email,
            password: config.testUser.password,
            company: config.testUser.company
        });
        
        // Login
        const loginResult = await makeLoadTestRequest('POST', `${config.backendUrl}/api/auth/login`, {
            email: config.testUser.email,
            password: config.testUser.password
        });
        
        if (loginResult.response.status === 200 && loginResult.response.data.token) {
            authToken = loginResult.response.data.token;
            return authToken;
        }
        
    } catch (error) {
        log('ERROR', `Authentication failed: ${error.message}`);
    }
    
    return null;
}

// Test scenarios
const testScenarios = {
    // Basic health check scenario
    healthCheck: async () => {
        const result = await makeLoadTestRequest('GET', `${config.backendUrl}/health`);
        return result;
    },
    
    // Frontend page load scenario
    frontendLoad: async () => {
        const result = await makeLoadTestRequest('GET', config.frontendUrl);
        return result;
    },
    
    // API endpoint scenario
    apiCall: async () => {
        const token = await authenticate();
        const headers = token ? { 'Authorization': `Bearer ${token}` } : {};
        const result = await makeLoadTestRequest('GET', `${config.backendUrl}/api/dashboard`, null, headers);
        return result;
    },
    
    // Database query scenario
    databaseQuery: async () => {
        const token = await authenticate();
        const headers = token ? { 'Authorization': `Bearer ${token}` } : {};
        const result = await makeLoadTestRequest('GET', `${config.backendUrl}/api/contacts`, null, headers);
        return result;
    },
    
    // Create operation scenario
    createOperation: async () => {
        const token = await authenticate();
        const headers = token ? { 'Authorization': `Bearer ${token}` } : {};
        const contactData = {
            name: `Load Test Contact ${Date.now()}`,
            phone: `+1${Math.floor(Math.random() * 10000000000)}`
        };
        const result = await makeLoadTestRequest('POST', `${config.backendUrl}/api/contacts`, contactData, headers);
        return result;
    },
    
    // Mixed workload scenario
    mixedWorkload: async () => {
        const scenarios = [
            testScenarios.healthCheck,
            testScenarios.apiCall,
            testScenarios.databaseQuery
        ];
        
        const randomScenario = scenarios[Math.floor(Math.random() * scenarios.length)];
        return await randomScenario();
    }
};

// Load test execution engine
class LoadTestEngine {
    constructor(scenarioName, options) {
        this.scenarioName = scenarioName;
        this.options = { ...config.scenarios.normal, ...options };
        this.stats = new PerformanceStats();
        this.activeRequests = 0;
        this.isRunning = false;
        this.workers = [];
    }
    
    async runScenario(scenarioFunction) {
        log('LOAD', `Starting load test scenario: ${this.scenarioName}`);
        log('INFO', `Configuration: ${this.options.users} users, ${this.options.rps} RPS, ${this.options.duration}ms duration`);
        
        this.isRunning = true;
        const startTime = Date.now();
        const endTime = startTime + this.options.duration;
        
        // Start worker threads
        for (let i = 0; i < this.options.users; i++) {
            this.workers.push(this.createWorker(i, scenarioFunction, endTime));
        }
        
        // Monitor progress
        const progressInterval = setInterval(() => {
            const elapsed = Date.now() - startTime;
            const progress = (elapsed / this.options.duration * 100).toFixed(1);
            const currentStats = this.stats.getStats();
            
            log('PERF', `Progress: ${progress}% | Requests: ${currentStats.totalRequests} | Errors: ${currentStats.failedRequests} | Avg RT: ${currentStats.responseTime.average.toFixed(0)}ms`);
        }, 10000); // Every 10 seconds
        
        // Wait for completion
        await Promise.all(this.workers);
        
        clearInterval(progressInterval);
        this.isRunning = false;
        
        const finalStats = this.stats.getStats();
        log('SUCCESS', `Load test completed: ${this.scenarioName}`);
        
        return finalStats;
    }
    
    async createWorker(workerId, scenarioFunction, endTime) {
        const requestInterval = 1000 / (this.options.rps / this.options.users); // ms between requests per user
        
        while (this.isRunning && Date.now() < endTime) {
            try {
                this.activeRequests++;
                const result = await scenarioFunction();
                
                this.stats.addRequest(result.responseTime, result.isError);
                
                if (result.isError) {
                    log('ERROR', `Request failed: ${result.response.status} ${result.response.statusText}`);
                }
                
            } catch (error) {
                this.stats.addRequest(0, true);
                log('ERROR', `Worker ${workerId} error: ${error.message}`);
            } finally {
                this.activeRequests--;
            }
            
            // Wait between requests
            await new Promise(resolve => setTimeout(resolve, requestInterval));
        }
    }
    
    async stop() {
        this.isRunning = false;
        
        // Wait for active requests to complete
        while (this.activeRequests > 0) {
            await new Promise(resolve => setTimeout(resolve, 100));
        }
    }
}

// Main load testing functions
async function runSingleScenario(scenarioName, scenarioOptions = {}) {
    const scenario = testScenarios[Object.keys(testScenarios)[0]]; // Default to first scenario
    const selectedScenario = testScenarios[scenarioName] || testScenarios.mixedWorkload;
    
    const engine = new LoadTestEngine(scenarioName, scenarioOptions);
    const stats = await engine.runScenario(selectedScenario);
    
    return stats;
}

async function runComprehensiveLoadTest() {
    log('LOAD', 'Starting comprehensive load testing suite');
    
    const scenarios = [
        { name: 'warmup', scenario: 'healthCheck', options: { users: 5, rps: 10, duration: 30000 } },
        { name: 'light_load', scenario: 'mixedWorkload', options: config.scenarios.light },
        { name: 'normal_load', scenario: 'mixedWorkload', options: config.scenarios.normal },
        { name: 'heavy_load', scenario: 'mixedWorkload', options: config.scenarios.heavy },
        { name: 'stress_test', scenario: 'mixedWorkload', options: config.scenarios.stress }
    ];
    
    const results = {};
    
    for (const { name, scenario, options } of scenarios) {
        log('LOAD', `\n${'='.repeat(60)}`);
        log('LOAD', `Running scenario: ${name.toUpperCase()}`);
        log('LOAD', `${'='.repeat(60)}`);
        
        try {
            results[name] = await runSingleScenario(scenario, options);
            
            // Display scenario results
            displayScenarioResults(name, results[name]);
            
            // Brief cooldown between scenarios
            if (name !== scenarios[scenarios.length - 1].name) {
                log('INFO', 'Cooldown period...');
                await new Promise(resolve => setTimeout(resolve, 10000)); // 10 seconds
            }
            
        } catch (error) {
            log('ERROR', `Scenario ${name} failed: ${error.message}`);
            results[name] = { error: error.message };
        }
    }
    
    // Generate comprehensive report
    generateLoadTestReport(results);
    
    return results;
}

function displayScenarioResults(scenarioName, stats) {
    log('PERF', `\n--- ${scenarioName.toUpperCase()} RESULTS ---`);
    log('PERF', `Total Requests: ${stats.totalRequests}`);
    log('PERF', `Successful Requests: ${stats.successfulRequests}`);
    log('PERF', `Failed Requests: ${stats.failedRequests}`);
    log('PERF', `Error Rate: ${(stats.errorRate * 100).toFixed(2)}%`);
    log('PERF', `Throughput: ${stats.throughput.toFixed(2)} req/sec`);
    log('PERF', `Response Time - Min: ${stats.responseTime.min}ms, Max: ${stats.responseTime.max}ms, Avg: ${stats.responseTime.average.toFixed(0)}ms`);
    log('PERF', `Response Time - P50: ${stats.responseTime.p50}ms, P95: ${stats.responseTime.p95}ms, P99: ${stats.responseTime.p99}ms`);
    
    // Performance validation
    const issues = [];
    
    if (stats.errorRate > config.maxErrorRate) {
        issues.push(`High error rate: ${(stats.errorRate * 100).toFixed(2)}% > ${(config.maxErrorRate * 100).toFixed(2)}%`);
    }
    
    if (stats.responseTime.average > config.maxResponseTime) {
        issues.push(`High average response time: ${stats.responseTime.average.toFixed(0)}ms > ${config.maxResponseTime}ms`);
    }
    
    if (stats.throughput < config.minThroughput) {
        issues.push(`Low throughput: ${stats.throughput.toFixed(2)} < ${config.minThroughput} req/sec`);
    }
    
    if (issues.length > 0) {
        log('WARNING', 'Performance issues detected:');
        issues.forEach(issue => log('WARNING', `  - ${issue}`));
    } else {
        log('SUCCESS', 'All performance thresholds met');
    }
}

function generateLoadTestReport(results) {
    log('LOAD', `\n${'='.repeat(80)}`);
    log('LOAD', 'COMPREHENSIVE LOAD TEST REPORT');
    log('LOAD', `${'='.repeat(80)}`);
    
    const overallStats = {
        totalRequests: 0,
        totalErrors: 0,
        averageResponseTime: 0,
        maxThroughput: 0,
        scenariosPassed: 0,
        scenariosFailed: 0
    };
    
    Object.entries(results).forEach(([name, stats]) => {
        if (stats.error) {
            overallStats.scenariosFailed++;
            return;
        }
        
        overallStats.scenariosPassed++;
        overallStats.totalRequests += stats.totalRequests;
        overallStats.totalErrors += stats.failedRequests;
        overallStats.averageResponseTime += stats.responseTime.average;
        overallStats.maxThroughput = Math.max(overallStats.maxThroughput, stats.throughput);
    });
    
    const validScenarios = overallStats.scenariosPassed;
    if (validScenarios > 0) {
        overallStats.averageResponseTime /= validScenarios;
    }
    
    log('PERF', `Scenarios Passed: ${overallStats.scenariosPassed}`);
    log('PERF', `Scenarios Failed: ${overallStats.scenariosFailed}`);
    log('PERF', `Total Requests Processed: ${overallStats.totalRequests}`);
    log('PERF', `Total Errors: ${overallStats.totalErrors}`);
    log('PERF', `Overall Error Rate: ${((overallStats.totalErrors / overallStats.totalRequests) * 100).toFixed(2)}%`);
    log('PERF', `Average Response Time: ${overallStats.averageResponseTime.toFixed(0)}ms`);
    log('PERF', `Peak Throughput: ${overallStats.maxThroughput.toFixed(2)} req/sec`);
    
    // Performance summary
    const isSystemHealthy = 
        overallStats.scenariosFailed === 0 &&
        (overallStats.totalErrors / overallStats.totalRequests) <= config.maxErrorRate &&
        overallStats.averageResponseTime <= config.maxResponseTime &&
        overallStats.maxThroughput >= config.minThroughput;
    
    if (isSystemHealthy) {
        log('SUCCESS', 'System performance is within acceptable limits');
        log('SUCCESS', 'Platform is ready for production load');
    } else {
        log('WARNING', 'System performance needs optimization');
        log('WARNING', 'Consider scaling resources or optimizing code before production');
    }
    
    // Save detailed report
    saveLoadTestReport(results, overallStats);
}

async function saveLoadTestReport(results, overallStats) {
    const report = {
        timestamp: new Date().toISOString(),
        configuration: config,
        overallStats,
        detailedResults: results,
        recommendations: generateRecommendations(results, overallStats)
    };
    
    try {
        await fs.writeFile(
            path.join(process.cwd(), 'load-test-report.json'),
            JSON.stringify(report, null, 2)
        );
        log('SUCCESS', 'Detailed load test report saved to load-test-report.json');
    } catch (error) {
        log('WARNING', `Failed to save detailed report: ${error.message}`);
    }
}

function generateRecommendations(results, overallStats) {
    const recommendations = [];
    
    if (overallStats.averageResponseTime > config.maxResponseTime) {
        recommendations.push('Consider implementing response caching');
        recommendations.push('Optimize database queries and add indexes');
        recommendations.push('Scale up Cloud Run instances');
    }
    
    if ((overallStats.totalErrors / overallStats.totalRequests) > config.maxErrorRate) {
        recommendations.push('Investigate error patterns and fix root causes');
        recommendations.push('Implement circuit breakers for external dependencies');
        recommendations.push('Add request queuing for traffic spikes');
    }
    
    if (overallStats.maxThroughput < config.minThroughput) {
        recommendations.push('Scale horizontally with more Cloud Run instances');
        recommendations.push('Optimize application code for better performance');
        recommendations.push('Consider using Cloud CDN for static assets');
    }
    
    return recommendations;
}

// Main execution
async function main() {
    const args = process.argv.slice(2);
    const command = args[0] || 'comprehensive';
    
    console.log(`${colors.cyan}=== WhatsApp Business Automation Platform - Load Testing ===${colors.reset}`);
    console.log(`${colors.cyan}Frontend URL: ${config.frontendUrl}${colors.reset}`);
    console.log(`${colors.cyan}Backend URL: ${config.backendUrl}${colors.reset}`);
    console.log(`${colors.cyan}Max Users: ${config.maxConcurrentUsers}${colors.reset}`);
    console.log('');
    
    try {
        switch (command) {
            case 'comprehensive':
                await runComprehensiveLoadTest();
                break;
                
            case 'quick':
                log('LOAD', 'Running quick load test');
                const quickStats = await runSingleScenario('mixedWorkload', config.scenarios.light);
                displayScenarioResults('quick', quickStats);
                break;
                
            case 'stress':
                log('LOAD', 'Running stress test');
                const stressStats = await runSingleScenario('mixedWorkload', config.scenarios.stress);
                displayScenarioResults('stress', stressStats);
                break;
                
            default:
                log('ERROR', `Unknown command: ${command}`);
                console.log('Usage: node load-test.js [comprehensive|quick|stress]');
                process.exit(1);
        }
        
        log('SUCCESS', 'Load testing completed successfully');
        process.exit(0);
        
    } catch (error) {
        log('ERROR', `Load testing failed: ${error.message}`);
        console.error(error);
        process.exit(1);
    }
}

// Error handling
process.on('unhandledRejection', (reason, promise) => {
    log('ERROR', `Unhandled Rejection: ${reason}`);
    process.exit(1);
});

process.on('SIGINT', () => {
    log('INFO', 'Load test interrupted by user');
    process.exit(0);
});

// Run if called directly
if (require.main === module) {
    main();
}

module.exports = {
    runSingleScenario,
    runComprehensiveLoadTest,
    LoadTestEngine,
    testScenarios,
    config
};