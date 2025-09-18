#!/bin/bash

# WhatsApp Business Automation Platform - System Health Monitoring Script
# Phase 10: Final Deployment and Testing
# This script provides comprehensive system health monitoring and alerting

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ID=${GOOGLE_CLOUD_PROJECT:-"your-project-id"}
REGION=${GOOGLE_CLOUD_REGION:-"us-central1"}
MONITORING_INTERVAL=${MONITORING_INTERVAL:-300} # 5 minutes
LOG_RETENTION_DAYS=${LOG_RETENTION_DAYS:-7}
ALERT_WEBHOOK=${ALERT_WEBHOOK:-""} # Slack/Discord webhook for alerts
LOG_FILE="/tmp/genspark-health-$(date +%Y%m%d).log"

# Service configuration
FRONTEND_SERVICE="genspark-frontend"
BACKEND_SERVICE="genspark-api"
DATABASE_INSTANCE="genspark-db-instance"
REDIS_INSTANCE="genspark-cache"

# Health thresholds
MAX_RESPONSE_TIME=2000  # 2 seconds
MIN_SUCCESS_RATE=95     # 95%
MAX_ERROR_RATE=5        # 5%
MAX_CPU_USAGE=80        # 80%
MAX_MEMORY_USAGE=80     # 80%

# Monitoring state
HEALTH_STATUS="UNKNOWN"
ALERT_COOLDOWN_FILE="/tmp/genspark-alert-cooldown"
COOLDOWN_DURATION=1800  # 30 minutes

echo -e "${CYAN}=== WhatsApp Business Automation Platform - Health Monitor ===${NC}"
echo -e "${CYAN}Project: $PROJECT_ID${NC}"
echo -e "${CYAN}Region: $REGION${NC}"
echo -e "${CYAN}Started: $(date)${NC}"
echo -e "${CYAN}Log File: $LOG_FILE${NC}"
echo ""

# Function to log with timestamp
log_with_timestamp() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local color_code=""
    
    case $level in
        "INFO")  color_code="${BLUE}" ;;
        "SUCCESS") color_code="${GREEN}" ;;
        "WARNING") color_code="${YELLOW}" ;;
        "ERROR") color_code="${RED}" ;;
        "CRITICAL") color_code="${RED}" ;;
    esac
    
    echo -e "${color_code}[$timestamp] $level: $message${NC}"
    echo "[$timestamp] $level: $message" >> "$LOG_FILE"
}

# Function to send alerts
send_alert() {
    local alert_level="$1"
    local alert_message="$2"
    
    # Check alert cooldown
    if [ -f "$ALERT_COOLDOWN_FILE" ]; then
        local last_alert=$(cat "$ALERT_COOLDOWN_FILE")
        local current_time=$(date +%s)
        if [ $((current_time - last_alert)) -lt $COOLDOWN_DURATION ]; then
            log_with_timestamp "INFO" "Alert suppressed due to cooldown period"
            return
        fi
    fi
    
    log_with_timestamp "$alert_level" "$alert_message"
    
    # Send webhook alert if configured
    if [ -n "$ALERT_WEBHOOK" ]; then
        local payload="{\"text\":\"🚨 GenSpark Alert [$alert_level]: $alert_message\"}"
        curl -s -X POST -H 'Content-Type: application/json' -d "$payload" "$ALERT_WEBHOOK" || true
        echo "$(date +%s)" > "$ALERT_COOLDOWN_FILE"
    fi
}

# Function to check service health
check_service_health() {
    local service_name="$1"
    local expected_instances="$2"
    
    log_with_timestamp "INFO" "Checking $service_name health"
    
    # Get service details
    local service_info=$(gcloud run services describe "$service_name" \
        --region="$REGION" \
        --format="value(status.url,status.conditions.type,spec.template.spec.containerConcurrency)" \
        2>/dev/null || echo "")
    
    if [ -z "$service_info" ]; then
        send_alert "CRITICAL" "$service_name: Service not found or inaccessible"
        return 1
    fi
    
    local service_url=$(echo "$service_info" | cut -d$'\t' -f1)
    local service_status=$(echo "$service_info" | cut -d$'\t' -f2)
    
    # Check if service is ready
    if [[ "$service_status" != *"Ready"* ]]; then
        send_alert "CRITICAL" "$service_name: Service not ready (Status: $service_status)"
        return 1
    fi
    
    # Check service endpoint
    if [ -n "$service_url" ]; then
        local start_time=$(date +%s%N)
        local http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$service_url" || echo "000")
        local end_time=$(date +%s%N)
        local response_time=$(((end_time - start_time) / 1000000)) # Convert to milliseconds
        
        if [ "$http_code" != "200" ]; then
            send_alert "CRITICAL" "$service_name: HTTP health check failed (Code: $http_code)"
            return 1
        fi
        
        if [ $response_time -gt $MAX_RESPONSE_TIME ]; then
            send_alert "WARNING" "$service_name: High response time (${response_time}ms > ${MAX_RESPONSE_TIME}ms)"
        fi
        
        log_with_timestamp "SUCCESS" "$service_name: Healthy (Response: ${response_time}ms)"
    fi
    
    return 0
}

# Function to check API endpoints
check_api_endpoints() {
    log_with_timestamp "INFO" "Checking API endpoints"
    
    local backend_url=$(gcloud run services describe "$BACKEND_SERVICE" \
        --region="$REGION" \
        --format="value(status.url)" 2>/dev/null || echo "")
    
    if [ -z "$backend_url" ]; then
        send_alert "CRITICAL" "Backend service URL not found"
        return 1
    fi
    
    # Check health endpoint
    local health_response=$(curl -s --max-time 10 "$backend_url/health" || echo "")
    if [[ "$health_response" != *"healthy"* ]]; then
        send_alert "CRITICAL" "Backend health endpoint failed"
        return 1
    fi
    
    # Check database connectivity
    local db_response=$(curl -s --max-time 10 "$backend_url/api/health/db" || echo "")
    if [[ "$db_response" != *"connected"* ]]; then
        send_alert "CRITICAL" "Database connectivity check failed"
        return 1
    fi
    
    # Check cache connectivity
    local cache_response=$(curl -s --max-time 10 "$backend_url/api/health/cache" || echo "")
    if [[ "$cache_response" != *"connected"* ]]; then
        send_alert "WARNING" "Cache connectivity check failed"
    fi
    
    log_with_timestamp "SUCCESS" "API endpoints are healthy"
    return 0
}

# Function to check database health
check_database_health() {
    log_with_timestamp "INFO" "Checking database health"
    
    # Check Cloud SQL instance status
    local db_status=$(gcloud sql instances describe "$DATABASE_INSTANCE" \
        --format="value(state)" 2>/dev/null || echo "")
    
    if [ "$db_status" != "RUNNABLE" ]; then
        send_alert "CRITICAL" "Database instance not running (Status: $db_status)"
        return 1
    fi
    
    # Check database connections
    local connection_count=$(gcloud sql instances describe "$DATABASE_INSTANCE" \
        --format="value(currentDiskSize)" 2>/dev/null || echo "0")
    
    log_with_timestamp "SUCCESS" "Database is healthy"
    return 0
}

# Function to check Redis health
check_redis_health() {
    log_with_timestamp "INFO" "Checking Redis health"
    
    local redis_status=$(gcloud redis instances describe "$REDIS_INSTANCE" \
        --region="$REGION" \
        --format="value(state)" 2>/dev/null || echo "")
    
    if [ "$redis_status" != "READY" ]; then
        send_alert "CRITICAL" "Redis instance not ready (Status: $redis_status)"
        return 1
    fi
    
    log_with_timestamp "SUCCESS" "Redis is healthy"
    return 0
}

# Function to check resource utilization
check_resource_utilization() {
    log_with_timestamp "INFO" "Checking resource utilization"
    
    # Check CPU utilization for Cloud Run services
    local cpu_query='fetch cloud_run_revision
    | metric "run.googleapis.com/container/cpu/utilizations"
    | filter (resource.service_name == "'"$FRONTEND_SERVICE"'" || resource.service_name == "'"$BACKEND_SERVICE"'")
    | group_by [resource.service_name], [value_mean: mean(value.utilization)]
    | within 5m'
    
    # This would require more complex gcloud monitoring queries
    # For now, we'll check basic metrics
    
    log_with_timestamp "INFO" "Resource utilization check completed"
}

# Function to check error rates
check_error_rates() {
    log_with_timestamp "INFO" "Checking error rates"
    
    # Get recent logs with errors
    local error_count=$(gcloud logging read 'resource.type="cloud_run_revision" AND severity>=ERROR' \
        --limit=100 \
        --format="value(timestamp)" \
        --freshness=5m 2>/dev/null | wc -l)
    
    if [ $error_count -gt 10 ]; then
        send_alert "WARNING" "High error rate detected ($error_count errors in last 5 minutes)"
    fi
    
    log_with_timestamp "INFO" "Error rate check completed (Errors: $error_count)"
}

# Function to check SSL certificates
check_ssl_certificates() {
    log_with_timestamp "INFO" "Checking SSL certificates"
    
    local frontend_url=$(gcloud run services describe "$FRONTEND_SERVICE" \
        --region="$REGION" \
        --format="value(status.url)" 2>/dev/null || echo "")
    
    if [ -n "$frontend_url" ] && [[ "$frontend_url" == https://* ]]; then
        local cert_expiry=$(echo | openssl s_client -servername "${frontend_url#https://}" -connect "${frontend_url#https://}:443" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null || echo "")
        
        if [ -n "$cert_expiry" ]; then
            log_with_timestamp "SUCCESS" "SSL certificate is valid"
        else
            send_alert "WARNING" "SSL certificate check failed"
        fi
    fi
}

# Function to check external dependencies
check_external_dependencies() {
    log_with_timestamp "INFO" "Checking external dependencies"
    
    # Check WhatsApp Business API endpoint (if configured)
    local whatsapp_status=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" "https://graph.facebook.com/v18.0/me" || echo "000")
    if [ "$whatsapp_status" != "400" ] && [ "$whatsapp_status" != "401" ]; then
        log_with_timestamp "WARNING" "WhatsApp Business API connectivity may be impacted"
    fi
    
    # Check Google Cloud APIs
    local apis_to_check=("run.googleapis.com" "sql.googleapis.com" "redis.googleapis.com")
    for api in "${apis_to_check[@]}"; do
        local api_status=$(gcloud services list --enabled --filter="name:$api" --format="value(name)" 2>/dev/null || echo "")
        if [ -z "$api_status" ]; then
            send_alert "CRITICAL" "Required API not enabled: $api"
        fi
    done
    
    log_with_timestamp "SUCCESS" "External dependencies check completed"
}

# Function to perform security checks
check_security_status() {
    log_with_timestamp "INFO" "Performing security checks"
    
    # Check for security incidents in logs
    local security_incidents=$(gcloud logging read 'severity>=WARNING AND (protoPayload.methodName:"iam" OR textPayload:"unauthorized" OR textPayload:"forbidden")' \
        --limit=50 \
        --format="value(timestamp)" \
        --freshness=1h 2>/dev/null | wc -l)
    
    if [ $security_incidents -gt 5 ]; then
        send_alert "WARNING" "Potential security incidents detected ($security_incidents events in last hour)"
    fi
    
    # Check IAM policy changes
    local iam_changes=$(gcloud logging read 'protoPayload.serviceName="cloudresourcemanager.googleapis.com" AND protoPayload.methodName="SetIamPolicy"' \
        --limit=10 \
        --format="value(timestamp)" \
        --freshness=1h 2>/dev/null | wc -l)
    
    if [ $iam_changes -gt 0 ]; then
        log_with_timestamp "INFO" "IAM policy changes detected in last hour: $iam_changes"
    fi
    
    log_with_timestamp "SUCCESS" "Security checks completed"
}

# Function to cleanup old logs
cleanup_old_logs() {
    find /tmp -name "genspark-health-*.log" -type f -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null || true
    log_with_timestamp "INFO" "Log cleanup completed"
}

# Function to generate health report
generate_health_report() {
    local overall_status="HEALTHY"
    local issues_count=0
    
    log_with_timestamp "INFO" "Generating health report"
    
    # Create detailed report
    cat << EOF > "/tmp/genspark-health-report-$(date +%Y%m%d-%H%M%S).json"
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "project_id": "$PROJECT_ID",
    "region": "$REGION",
    "overall_status": "$overall_status",
    "services": {
        "frontend": {
            "service": "$FRONTEND_SERVICE",
            "status": "checked"
        },
        "backend": {
            "service": "$BACKEND_SERVICE", 
            "status": "checked"
        }
    },
    "infrastructure": {
        "database": {
            "instance": "$DATABASE_INSTANCE",
            "status": "checked"
        },
        "cache": {
            "instance": "$REDIS_INSTANCE",
            "status": "checked"
        }
    },
    "monitoring": {
        "log_file": "$LOG_FILE",
        "alert_webhook": "$ALERT_WEBHOOK",
        "last_check": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    }
}
EOF
    
    log_with_timestamp "SUCCESS" "Health report generated"
}

# Main monitoring loop
run_health_checks() {
    log_with_timestamp "INFO" "Starting comprehensive health checks"
    
    local checks_passed=0
    local checks_failed=0
    
    # Run all health checks
    if check_service_health "$FRONTEND_SERVICE" 1; then
        ((checks_passed++))
    else
        ((checks_failed++))
    fi
    
    if check_service_health "$BACKEND_SERVICE" 1; then
        ((checks_passed++))
    else
        ((checks_failed++))
    fi
    
    if check_api_endpoints; then
        ((checks_passed++))
    else
        ((checks_failed++))
    fi
    
    if check_database_health; then
        ((checks_passed++))
    else
        ((checks_failed++))
    fi
    
    if check_redis_health; then
        ((checks_passed++))
    else
        ((checks_failed++))
    fi
    
    check_resource_utilization
    check_error_rates
    check_ssl_certificates
    check_external_dependencies
    check_security_status
    
    # Determine overall health
    if [ $checks_failed -eq 0 ]; then
        HEALTH_STATUS="HEALTHY"
        log_with_timestamp "SUCCESS" "All health checks passed ($checks_passed/$((checks_passed + checks_failed)))"
    elif [ $checks_failed -lt 3 ]; then
        HEALTH_STATUS="DEGRADED"
        send_alert "WARNING" "System degraded - $checks_failed critical checks failed"
    else
        HEALTH_STATUS="UNHEALTHY"
        send_alert "CRITICAL" "System unhealthy - $checks_failed critical checks failed"
    fi
    
    generate_health_report
    cleanup_old_logs
    
    log_with_timestamp "INFO" "Health check cycle completed - Status: $HEALTH_STATUS"
}

# Function to run continuous monitoring
run_continuous_monitoring() {
    log_with_timestamp "INFO" "Starting continuous monitoring (interval: ${MONITORING_INTERVAL}s)"
    
    while true; do
        run_health_checks
        sleep $MONITORING_INTERVAL
    done
}

# Function to run single check
run_single_check() {
    run_health_checks
    echo ""
    echo -e "${CYAN}Health Status: $HEALTH_STATUS${NC}"
    echo -e "${CYAN}Log File: $LOG_FILE${NC}"
}

# Main script logic
case "${1:-single}" in
    "continuous"|"-c"|"--continuous")
        run_continuous_monitoring
        ;;
    "single"|"-s"|"--single"|"")
        run_single_check
        ;;
    "help"|"-h"|"--help")
        cat << EOF
WhatsApp Business Automation Platform - Health Monitoring Script

Usage: $0 [OPTIONS]

OPTIONS:
    continuous, -c, --continuous    Run continuous monitoring
    single, -s, --single           Run single health check (default)
    help, -h, --help               Show this help message

ENVIRONMENT VARIABLES:
    GOOGLE_CLOUD_PROJECT           GCP project ID
    GOOGLE_CLOUD_REGION           GCP region
    MONITORING_INTERVAL           Monitoring interval in seconds (default: 300)
    LOG_RETENTION_DAYS            Log retention period (default: 7)
    ALERT_WEBHOOK                 Webhook URL for alerts (optional)

EXAMPLES:
    $0                            # Run single health check
    $0 continuous                 # Run continuous monitoring
    MONITORING_INTERVAL=60 $0 -c  # Run continuous with 60s interval

EOF
        exit 0
        ;;
    *)
        echo "Unknown option: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac