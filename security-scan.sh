#!/bin/bash

# WhatsApp Business Automation Platform - Security Scanning Script
# Phase 10: Final Deployment and Testing
# This script performs comprehensive security validation and vulnerability scanning

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ID=${GOOGLE_CLOUD_PROJECT:-"your-project-id"}
REGION=${GOOGLE_CLOUD_REGION:-"us-central1"}
FRONTEND_SERVICE="genspark-frontend"
BACKEND_SERVICE="genspark-api"
DATABASE_INSTANCE="genspark-db-instance"
SCAN_TIMEOUT=600  # 10 minutes
REPORT_FILE="/tmp/genspark-security-report-$(date +%Y%m%d-%H%M%S).json"

echo -e "${CYAN}=== WhatsApp Business Automation Platform - Security Scanning ===${NC}"
echo -e "${CYAN}Project: $PROJECT_ID${NC}"
echo -e "${CYAN}Region: $REGION${NC}"
echo -e "${CYAN}Report File: $REPORT_FILE${NC}"
echo ""

# Security findings tracking
declare -A security_findings
security_findings[critical]=0
security_findings[high]=0
security_findings[medium]=0
security_findings[low]=0
security_findings[info]=0

# Function to log with severity levels
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")     echo -e "${BLUE}[$timestamp] INFO: $message${NC}" ;;
        "SUCCESS")  echo -e "${GREEN}[$timestamp] SUCCESS: $message${NC}" ;;
        "WARNING")  echo -e "${YELLOW}[$timestamp] WARNING: $message${NC}" ;;
        "ERROR")    echo -e "${RED}[$timestamp] ERROR: $message${NC}" ;;
        "CRITICAL") echo -e "${RED}[$timestamp] CRITICAL: $message${NC}" ;;
        "SECURITY") echo -e "${MAGENTA}[$timestamp] SECURITY: $message${NC}" ;;
    esac
}

# Function to record security finding
record_finding() {
    local severity="$1"
    local category="$2"
    local description="$3"
    local recommendation="$4"
    
    security_findings[$severity]=$((${security_findings[$severity]} + 1))
    
    log "SECURITY" "[$severity] $category: $description"
    if [ -n "$recommendation" ]; then
        log "INFO" "Recommendation: $recommendation"
    fi
    
    # Store finding in report (simplified JSON append)
    echo "  {\"severity\": \"$severity\", \"category\": \"$category\", \"description\": \"$description\", \"recommendation\": \"$recommendation\"}," >> "${REPORT_FILE}.tmp"
}

# Function to test endpoint for common vulnerabilities
test_endpoint_security() {
    local endpoint_url="$1"
    local endpoint_name="$2"
    
    log "INFO" "Testing security for endpoint: $endpoint_name"
    
    # Test 1: Check for security headers
    log "INFO" "Checking security headers"
    local headers_response=$(curl -s -I --max-time 10 "$endpoint_url" 2>/dev/null || echo "")
    
    if [ -n "$headers_response" ]; then
        # Check for essential security headers
        if ! echo "$headers_response" | grep -qi "X-Content-Type-Options"; then
            record_finding "medium" "Security Headers" "Missing X-Content-Type-Options header" "Add 'X-Content-Type-Options: nosniff' header"
        fi
        
        if ! echo "$headers_response" | grep -qi "X-Frame-Options"; then
            record_finding "medium" "Security Headers" "Missing X-Frame-Options header" "Add 'X-Frame-Options: DENY' or 'SAMEORIGIN' header"
        fi
        
        if ! echo "$headers_response" | grep -qi "X-XSS-Protection"; then
            record_finding "low" "Security Headers" "Missing X-XSS-Protection header" "Add 'X-XSS-Protection: 1; mode=block' header"
        fi
        
        if ! echo "$headers_response" | grep -qi "Strict-Transport-Security"; then
            record_finding "medium" "Security Headers" "Missing HSTS header" "Add 'Strict-Transport-Security' header for HTTPS endpoints"
        fi
        
        if ! echo "$headers_response" | grep -qi "Content-Security-Policy"; then
            record_finding "medium" "Security Headers" "Missing Content Security Policy" "Implement CSP header to prevent XSS attacks"
        fi
        
        # Check for information disclosure in headers
        if echo "$headers_response" | grep -qi "Server:"; then
            local server_header=$(echo "$headers_response" | grep -i "Server:" | head -n1)
            record_finding "low" "Information Disclosure" "Server header reveals technology stack: $server_header" "Remove or minimize server information in headers"
        fi
    else
        record_finding "high" "Connectivity" "Cannot connect to endpoint for security testing" "Verify endpoint availability"
    fi
    
    # Test 2: Check for HTTPS enforcement
    if [[ "$endpoint_url" == https://* ]]; then
        local http_url="${endpoint_url/https:/http:}"
        local http_response=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$http_url" 2>/dev/null || echo "000")
        
        if [ "$http_response" = "200" ]; then
            record_finding "high" "Transport Security" "HTTP endpoint accessible without redirect to HTTPS" "Implement HTTP to HTTPS redirect"
        elif [ "$http_response" = "301" ] || [ "$http_response" = "302" ]; then
            log "SUCCESS" "HTTP properly redirects to HTTPS"
        fi
    fi
    
    # Test 3: Basic XSS testing
    log "INFO" "Testing for XSS vulnerabilities"
    local xss_payload="<script>alert('xss')</script>"
    local xss_response=$(curl -s --max-time 10 -G -d "test=$xss_payload" "$endpoint_url" 2>/dev/null || echo "")
    
    if [[ "$xss_response" == *"<script>alert"* ]]; then
        record_finding "high" "XSS Vulnerability" "Potential XSS vulnerability detected" "Implement proper input validation and output encoding"
    fi
    
    # Test 4: SQL injection testing (basic)
    log "INFO" "Testing for SQL injection vulnerabilities"
    local sql_payload="' OR '1'='1"
    local sql_response=$(curl -s --max-time 10 -G -d "test=$sql_payload" "$endpoint_url" 2>/dev/null || echo "")
    
    if [[ "$sql_response" == *"SQL"* ]] || [[ "$sql_response" == *"mysql"* ]] || [[ "$sql_response" == *"postgresql"* ]]; then
        record_finding "critical" "SQL Injection" "Potential SQL injection vulnerability detected" "Implement parameterized queries and input validation"
    fi
    
    # Test 5: Directory traversal
    log "INFO" "Testing for directory traversal"
    local traversal_payload="../../../etc/passwd"
    local traversal_response=$(curl -s --max-time 10 -G -d "file=$traversal_payload" "$endpoint_url" 2>/dev/null || echo "")
    
    if [[ "$traversal_response" == *"root:x:"* ]] || [[ "$traversal_response" == *"/bin/bash"* ]]; then
        record_finding "critical" "Directory Traversal" "Directory traversal vulnerability detected" "Implement proper path validation and access controls"
    fi
}

# Function to scan IAM configuration
scan_iam_configuration() {
    log "INFO" "Scanning IAM configuration"
    
    # Check for overly permissive service accounts
    local service_accounts=$(gcloud iam service-accounts list --format="value(email)" --filter="email:*genspark*" 2>/dev/null || echo "")
    
    if [ -n "$service_accounts" ]; then
        while IFS= read -r sa_email; do
            if [ -n "$sa_email" ]; then
                log "INFO" "Checking permissions for service account: $sa_email"
                
                # Get roles for service account
                local sa_roles=$(gcloud projects get-iam-policy "$PROJECT_ID" \
                    --flatten="bindings[].members" \
                    --format="table(bindings.role)" \
                    --filter="bindings.members:serviceAccount:$sa_email" 2>/dev/null || echo "")
                
                # Check for overly broad roles
                if echo "$sa_roles" | grep -q "roles/owner"; then
                    record_finding "critical" "IAM Permissions" "Service account has Owner role: $sa_email" "Use principle of least privilege - assign minimal required permissions"
                fi
                
                if echo "$sa_roles" | grep -q "roles/editor"; then
                    record_finding "high" "IAM Permissions" "Service account has Editor role: $sa_email" "Use specific roles instead of broad Editor permissions"
                fi
                
                if echo "$sa_roles" | grep -q "roles/iam.securityAdmin"; then
                    record_finding "high" "IAM Permissions" "Service account has Security Admin role: $sa_email" "Review if security admin permissions are necessary"
                fi
            fi
        done <<< "$service_accounts"
    fi
    
    # Check for users with overly broad permissions
    local broad_users=$(gcloud projects get-iam-policy "$PROJECT_ID" \
        --flatten="bindings[].members" \
        --format="table(bindings.members,bindings.role)" \
        --filter="bindings.role:(roles/owner OR roles/editor)" 2>/dev/null | grep -v "serviceAccount" || echo "")
    
    if [ -n "$broad_users" ]; then
        record_finding "medium" "IAM Permissions" "Users with broad permissions detected" "Review user permissions and apply least privilege principle"
    fi
}

# Function to scan network security
scan_network_security() {
    log "INFO" "Scanning network security configuration"
    
    # Check VPC firewall rules
    local firewall_rules=$(gcloud compute firewall-rules list --format="csv(name,direction,priority,sourceRanges.list():label=SRC_RANGES,allowed[].map().firewall_rule().list():label=ALLOW,targetTags.list():label=TARGET_TAGS)" --filter="name:*genspark*" 2>/dev/null || echo "")
    
    if [ -n "$firewall_rules" ]; then
        while IFS= read -r rule_line; do
            if [[ "$rule_line" == *"0.0.0.0/0"* ]]; then
                if [[ "$rule_line" == *"tcp:22"* ]] || [[ "$rule_line" == *"tcp:3389"* ]]; then
                    record_finding "high" "Network Security" "Firewall rule allows SSH/RDP from anywhere: $rule_line" "Restrict SSH/RDP access to specific IP ranges"
                elif [[ "$rule_line" == *"tcp"* ]]; then
                    record_finding "medium" "Network Security" "Firewall rule allows broad access: $rule_line" "Review and restrict source IP ranges"
                fi
            fi
        done <<< "$firewall_rules"
    fi
    
    # Check Cloud Run service security
    log "INFO" "Checking Cloud Run service security"
    
    # Check if services allow unauthenticated access
    for service in "$FRONTEND_SERVICE" "$BACKEND_SERVICE"; do
        local auth_policy=$(gcloud run services get-iam-policy "$service" --region="$REGION" --format="value(bindings.members)" --filter="bindings.role:roles/run.invoker" 2>/dev/null || echo "")
        
        if echo "$auth_policy" | grep -q "allUsers"; then
            if [ "$service" = "$FRONTEND_SERVICE" ]; then
                log "INFO" "Frontend service allows unauthenticated access (expected)"
            else
                record_finding "medium" "Access Control" "Backend service allows unauthenticated access: $service" "Consider implementing authentication for backend APIs"
            fi
        fi
    done
}

# Function to scan database security
scan_database_security() {
    log "INFO" "Scanning database security configuration"
    
    # Check Cloud SQL instance configuration
    local db_config=$(gcloud sql instances describe "$DATABASE_INSTANCE" --format="value(settings.ipConfiguration.requireSsl,settings.ipConfiguration.authorizedNetworks[].value)" 2>/dev/null || echo "")
    
    if [[ "$db_config" == *"False"* ]]; then
        record_finding "high" "Database Security" "SSL not required for database connections" "Enable SSL requirement for all database connections"
    fi
    
    # Check for public IP access
    if [[ "$db_config" == *"0.0.0.0/0"* ]]; then
        record_finding "critical" "Database Security" "Database allows connections from anywhere" "Restrict database access to specific networks only"
    fi
    
    # Check backup configuration
    local backup_config=$(gcloud sql instances describe "$DATABASE_INSTANCE" --format="value(settings.backupConfiguration.enabled,settings.backupConfiguration.pointInTimeRecoveryEnabled)" 2>/dev/null || echo "")
    
    if [[ "$backup_config" != *"True"* ]]; then
        record_finding "medium" "Data Protection" "Database backup not properly configured" "Enable automated backups and point-in-time recovery"
    fi
}

# Function to scan secret management
scan_secret_management() {
    log "INFO" "Scanning secret management configuration"
    
    # List secrets and check for proper naming/organization
    local secrets=$(gcloud secrets list --format="value(name)" --filter="name:*genspark*" 2>/dev/null || echo "")
    
    if [ -z "$secrets" ]; then
        record_finding "medium" "Secret Management" "No secrets found with expected naming pattern" "Ensure all application secrets are stored in Secret Manager"
    else
        while IFS= read -r secret_name; do
            if [ -n "$secret_name" ]; then
                # Check secret access permissions
                local secret_policy=$(gcloud secrets get-iam-policy "$secret_name" --format="value(bindings.members)" --filter="bindings.role:roles/secretmanager.secretAccessor" 2>/dev/null || echo "")
                
                if echo "$secret_policy" | grep -q "allUsers"; then
                    record_finding "critical" "Secret Management" "Secret accessible by all users: $secret_name" "Restrict secret access to specific service accounts only"
                fi
                
                # Check for overly broad access
                local member_count=$(echo "$secret_policy" | wc -w)
                if [ "$member_count" -gt 5 ]; then
                    record_finding "medium" "Secret Management" "Secret has many accessors: $secret_name" "Review and minimize secret access permissions"
                fi
            fi
        done <<< "$secrets"
    fi
    
    # Check for hardcoded secrets in environment variables (basic check)
    for service in "$FRONTEND_SERVICE" "$BACKEND_SERVICE"; do
        local env_vars=$(gcloud run services describe "$service" --region="$REGION" --format="value(spec.template.spec.template.spec.containers[].env[].name,spec.template.spec.template.spec.containers[].env[].value)" 2>/dev/null || echo "")
        
        if echo "$env_vars" | grep -iE "(password|secret|key|token)" | grep -v "SECRET_MANAGER"; then
            record_finding "high" "Secret Management" "Potential hardcoded secrets in environment variables: $service" "Move secrets to Secret Manager"
        fi
    done
}

# Function to scan container security
scan_container_security() {
    log "INFO" "Scanning container security configuration"
    
    # Check for container vulnerabilities using Cloud Security Command Center (if available)
    # Note: This would require additional setup and permissions
    
    # Check container configuration
    for service in "$FRONTEND_SERVICE" "$BACKEND_SERVICE"; do
        local container_config=$(gcloud run services describe "$service" --region="$REGION" --format="value(spec.template.spec.template.spec.containers[].securityContext,spec.template.spec.template.spec.containers[].image)" 2>/dev/null || echo "")
        
        # Check if running as root (not directly available in Cloud Run format)
        log "INFO" "Container security check for $service"
        
        # Check image source
        if echo "$container_config" | grep -q "gcr.io/$PROJECT_ID"; then
            log "SUCCESS" "Using private registry for $service"
        else
            record_finding "low" "Container Security" "Using external registry for $service" "Consider using private registry for better control"
        fi
    done
}

# Function to check compliance requirements
scan_compliance() {
    log "INFO" "Scanning compliance requirements"
    
    # Check for audit logging
    local audit_logs=$(gcloud logging sinks list --format="value(name)" --filter="name:*audit*" 2>/dev/null || echo "")
    
    if [ -z "$audit_logs" ]; then
        record_finding "medium" "Compliance" "No audit logging sinks configured" "Configure audit log exports for compliance"
    fi
    
    # Check for data retention policies
    local retention_policy=$(gcloud logging sinks list --format="value(name,filter)" 2>/dev/null | grep -i "retention" || echo "")
    
    if [ -z "$retention_policy" ]; then
        record_finding "low" "Compliance" "No explicit data retention policies found" "Configure log retention policies per compliance requirements"
    fi
    
    # Check for encryption at rest (Cloud SQL)
    local encryption_config=$(gcloud sql instances describe "$DATABASE_INSTANCE" --format="value(diskEncryptionConfiguration.kmsKeyName)" 2>/dev/null || echo "")
    
    if [ -z "$encryption_config" ]; then
        record_finding "medium" "Compliance" "Database not using customer-managed encryption keys" "Consider using CMEK for enhanced data protection"
    fi
}

# Function to perform vulnerability scanning
run_vulnerability_scan() {
    log "INFO" "Running vulnerability scanning"
    
    # Get service URLs
    local frontend_url=$(gcloud run services describe "$FRONTEND_SERVICE" --region="$REGION" --format="value(status.url)" 2>/dev/null || echo "")
    local backend_url=$(gcloud run services describe "$BACKEND_SERVICE" --region="$REGION" --format="value(status.url)" 2>/dev/null || echo "")
    
    # Test endpoints if available
    if [ -n "$frontend_url" ]; then
        test_endpoint_security "$frontend_url" "Frontend"
    else
        record_finding "high" "Availability" "Frontend service URL not accessible" "Verify frontend service deployment"
    fi
    
    if [ -n "$backend_url" ]; then
        test_endpoint_security "$backend_url/health" "Backend Health"
        test_endpoint_security "$backend_url/api" "Backend API"
    else
        record_finding "high" "Availability" "Backend service URL not accessible" "Verify backend service deployment"
    fi
}

# Function to generate security report
generate_security_report() {
    log "INFO" "Generating comprehensive security report"
    
    # Calculate security score
    local critical_weight=10
    local high_weight=5
    local medium_weight=2
    local low_weight=1
    
    local total_score=$(( ${security_findings[critical]} * critical_weight + ${security_findings[high]} * high_weight + ${security_findings[medium]} * medium_weight + ${security_findings[low]} * low_weight ))
    
    # Determine security posture
    local security_posture="EXCELLENT"
    if [ $total_score -gt 0 ]; then
        if [ ${security_findings[critical]} -gt 0 ]; then
            security_posture="CRITICAL"
        elif [ ${security_findings[high]} -gt 3 ]; then
            security_posture="POOR"
        elif [ ${security_findings[high]} -gt 0 ] || [ ${security_findings[medium]} -gt 5 ]; then
            security_posture="FAIR"
        else
            security_posture="GOOD"
        fi
    fi
    
    # Generate final report
    cat > "$REPORT_FILE" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "project_id": "$PROJECT_ID",
  "region": "$REGION",
  "security_posture": "$security_posture",
  "security_score": $total_score,
  "findings_summary": {
    "critical": ${security_findings[critical]},
    "high": ${security_findings[high]},
    "medium": ${security_findings[medium]},
    "low": ${security_findings[low]},
    "info": ${security_findings[info]}
  },
  "detailed_findings": [
$(cat "${REPORT_FILE}.tmp" 2>/dev/null | sed '$ s/,$//' || echo "")
  ],
  "recommendations": [
    "Regular security assessments and vulnerability scanning",
    "Implement automated security monitoring and alerting",
    "Regular access reviews and permission audits",
    "Keep all dependencies and base images updated",
    "Implement security training for development team"
  ]
}
EOF
    
    # Cleanup temporary file
    rm -f "${REPORT_FILE}.tmp"
    
    log "SUCCESS" "Security report generated: $REPORT_FILE"
}

# Function to display security summary
display_security_summary() {
    log "INFO" "=== SECURITY SCAN SUMMARY ==="
    
    echo -e "${CYAN}Findings Summary:${NC}"
    echo -e "  ${RED}Critical: ${security_findings[critical]}${NC}"
    echo -e "  ${YELLOW}High: ${security_findings[high]}${NC}"
    echo -e "  ${BLUE}Medium: ${security_findings[medium]}${NC}"
    echo -e "  ${GREEN}Low: ${security_findings[low]}${NC}"
    echo -e "  ${CYAN}Info: ${security_findings[info]}${NC}"
    
    # Security posture determination
    if [ ${security_findings[critical]} -gt 0 ]; then
        log "CRITICAL" "CRITICAL security issues found - immediate attention required"
        echo -e "${RED}Security Posture: CRITICAL${NC}"
    elif [ ${security_findings[high]} -gt 3 ]; then
        log "ERROR" "Multiple HIGH severity issues found"
        echo -e "${RED}Security Posture: POOR${NC}"
    elif [ ${security_findings[high]} -gt 0 ] || [ ${security_findings[medium]} -gt 5 ]; then
        log "WARNING" "Some security issues found - review recommended"
        echo -e "${YELLOW}Security Posture: FAIR${NC}"
    elif [ ${security_findings[medium]} -gt 0 ] || [ ${security_findings[low]} -gt 0 ]; then
        log "SUCCESS" "Minor security issues found - good overall security"
        echo -e "${GREEN}Security Posture: GOOD${NC}"
    else
        log "SUCCESS" "No security issues found - excellent security posture"
        echo -e "${GREEN}Security Posture: EXCELLENT${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}Report saved to: $REPORT_FILE${NC}"
    
    # Return appropriate exit code
    if [ ${security_findings[critical]} -gt 0 ]; then
        return 2  # Critical issues
    elif [ ${security_findings[high]} -gt 0 ]; then
        return 1  # High severity issues
    else
        return 0  # No critical or high issues
    fi
}

# Main security scan function
run_comprehensive_security_scan() {
    log "INFO" "Starting comprehensive security scanning"
    
    # Initialize report
    echo "" > "${REPORT_FILE}.tmp"
    
    # Run security scans
    scan_iam_configuration
    scan_network_security
    scan_database_security
    scan_secret_management
    scan_container_security
    scan_compliance
    run_vulnerability_scan
    
    # Generate and display results
    generate_security_report
    display_security_summary
}

# Main execution
main() {
    local command="${1:-full}"
    
    case "$command" in
        "full"|"-f"|"--full"|"")
            run_comprehensive_security_scan
            ;;
        "quick"|"-q"|"--quick")
            log "INFO" "Running quick security scan"
            scan_iam_configuration
            run_vulnerability_scan
            generate_security_report
            display_security_summary
            ;;
        "iam"|"--iam")
            log "INFO" "Running IAM security scan"
            scan_iam_configuration
            generate_security_report
            display_security_summary
            ;;
        "network"|"--network")
            log "INFO" "Running network security scan"
            scan_network_security
            generate_security_report
            display_security_summary
            ;;
        "help"|"-h"|"--help")
            cat << EOF
WhatsApp Business Automation Platform - Security Scanning Script

Usage: $0 [OPTIONS]

OPTIONS:
    full, -f, --full               Run comprehensive security scan (default)
    quick, -q, --quick             Run quick security validation
    iam, --iam                     Run IAM configuration scan only
    network, --network             Run network security scan only
    help, -h, --help               Show this help message

ENVIRONMENT VARIABLES:
    GOOGLE_CLOUD_PROJECT           GCP project ID
    GOOGLE_CLOUD_REGION           GCP region (default: us-central1)
    SCAN_TIMEOUT                  Scan timeout in seconds (default: 600)

EXAMPLES:
    $0                            # Run comprehensive security scan
    $0 quick                      # Run quick security validation
    $0 iam                        # Scan IAM configuration only

OUTPUT:
    - Console output with findings
    - JSON report file with detailed results
    - Exit code: 0=clean, 1=warnings, 2=critical issues

EOF
            exit 0
            ;;
        *)
            log "ERROR" "Unknown command: $command"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Verify prerequisites
if ! command -v gcloud >/dev/null 2>&1; then
    log "ERROR" "gcloud CLI is required but not installed"
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    log "ERROR" "curl is required but not installed"
    exit 1
fi

# Verify project access
if ! gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
    log "ERROR" "Cannot access project $PROJECT_ID or project not set"
    exit 1
fi

# Run main function
main "$@"