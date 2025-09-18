#!/bin/bash

# WhatsApp Business Automation Platform - Deployment Validation Script
# Phase 10: Final Deployment and Testing
# This script validates all infrastructure components and services

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ID=${GOOGLE_CLOUD_PROJECT:-"your-project-id"}
REGION=${GOOGLE_CLOUD_REGION:-"us-central1"}
FRONTEND_SERVICE="genspark-frontend"
BACKEND_SERVICE="genspark-api"
DATABASE_INSTANCE="genspark-db-instance"
REDIS_INSTANCE="genspark-cache"
VPC_CONNECTOR="genspark-vpc-connector"

echo -e "${BLUE}=== WhatsApp Business Automation Platform - Deployment Validation ===${NC}"
echo -e "${BLUE}Project: $PROJECT_ID${NC}"
echo -e "${BLUE}Region: $REGION${NC}"
echo -e "${BLUE}Timestamp: $(date)${NC}"
echo ""

# Function to log success
log_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Function to log warning
log_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Function to log error
log_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Function to log info
log_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Validation counter
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# Function to run validation check
run_check() {
    local check_name="$1"
    local check_command="$2"
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    log_info "Checking: $check_name"
    
    if eval "$check_command" > /dev/null 2>&1; then
        log_success "$check_name"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        log_error "$check_name"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

echo -e "${YELLOW}1. GOOGLE CLOUD PROJECT VALIDATION${NC}"
echo "=================================================="

# Validate Google Cloud authentication
run_check "Google Cloud authentication" "gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -n1"

# Validate project access
run_check "Project access verification" "gcloud projects describe $PROJECT_ID"

# Validate required APIs
REQUIRED_APIS=(
    "run.googleapis.com"
    "sql.googleapis.com"
    "redis.googleapis.com"
    "storage.googleapis.com"
    "secretmanager.googleapis.com"
    "cloudbuild.googleapis.com"
    "vpcaccess.googleapis.com"
    "compute.googleapis.com"
    "monitoring.googleapis.com"
    "logging.googleapis.com"
)

for api in "${REQUIRED_APIS[@]}"; do
    run_check "API enabled: $api" "gcloud services list --enabled --filter='name:$api' --format='value(name)' | grep -q $api"
done

echo ""
echo -e "${YELLOW}2. INFRASTRUCTURE COMPONENTS VALIDATION${NC}"
echo "=================================================="

# Validate Cloud Run services
run_check "Cloud Run frontend service" "gcloud run services describe $FRONTEND_SERVICE --region=$REGION --format='value(status.url)'"
run_check "Cloud Run backend service" "gcloud run services describe $BACKEND_SERVICE --region=$REGION --format='value(status.url)'"

# Validate Cloud SQL instance
run_check "Cloud SQL instance" "gcloud sql instances describe $DATABASE_INSTANCE --format='value(state)' | grep -q RUNNABLE"

# Validate Redis instance
run_check "Redis Memorystore instance" "gcloud redis instances describe $REDIS_INSTANCE --region=$REGION --format='value(state)' | grep -q READY"

# Validate VPC connector
run_check "VPC connector" "gcloud compute networks vpc-access connectors describe $VPC_CONNECTOR --region=$REGION --format='value(state)' | grep -q READY"

# Validate Cloud Storage buckets
run_check "Cloud Storage static bucket" "gsutil ls gs://${PROJECT_ID}-static"
run_check "Cloud Storage uploads bucket" "gsutil ls gs://${PROJECT_ID}-uploads"

echo ""
echo -e "${YELLOW}3. SERVICE HEALTH VALIDATION${NC}"
echo "=================================================="

# Get service URLs
FRONTEND_URL=$(gcloud run services describe $FRONTEND_SERVICE --region=$REGION --format='value(status.url)' 2>/dev/null || echo "")
BACKEND_URL=$(gcloud run services describe $BACKEND_SERVICE --region=$REGION --format='value(status.url)' 2>/dev/null || echo "")

if [ -n "$FRONTEND_URL" ]; then
    run_check "Frontend service health" "curl -s -o /dev/null -w '%{http_code}' $FRONTEND_URL | grep -q '200'"
    run_check "Frontend service response time" "curl -s -o /dev/null -w '%{time_total}' $FRONTEND_URL | awk '{print ($1 < 5)}' | grep -q 1"
else
    log_error "Frontend service URL not found"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

if [ -n "$BACKEND_URL" ]; then
    run_check "Backend service health" "curl -s -o /dev/null -w '%{http_code}' $BACKEND_URL/health | grep -q '200'"
    run_check "Backend API health endpoint" "curl -s $BACKEND_URL/api/health | jq -r '.status' | grep -q 'healthy'"
    run_check "Backend service response time" "curl -s -o /dev/null -w '%{time_total}' $BACKEND_URL/health | awk '{print ($1 < 3)}' | grep -q 1"
else
    log_error "Backend service URL not found"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

echo ""
echo -e "${YELLOW}4. DATABASE CONNECTIVITY VALIDATION${NC}"
echo "=================================================="

# Test database connectivity through backend API
if [ -n "$BACKEND_URL" ]; then
    run_check "Database connectivity" "curl -s $BACKEND_URL/api/health/db | jq -r '.database' | grep -q 'connected'"
    run_check "Database schema validation" "curl -s $BACKEND_URL/api/health/db | jq -r '.tables' | grep -q 'users'"
else
    log_warning "Cannot test database connectivity - Backend URL not available"
fi

echo ""
echo -e "${YELLOW}5. CACHE AND SESSION VALIDATION${NC}"
echo "=================================================="

# Test Redis connectivity through backend API
if [ -n "$BACKEND_URL" ]; then
    run_check "Redis cache connectivity" "curl -s $BACKEND_URL/api/health/cache | jq -r '.cache' | grep -q 'connected'"
    run_check "Session storage validation" "curl -s $BACKEND_URL/api/health/cache | jq -r '.session' | grep -q 'active'"
else
    log_warning "Cannot test cache connectivity - Backend URL not available"
fi

echo ""
echo -e "${YELLOW}6. SECRET MANAGEMENT VALIDATION${NC}"
echo "=================================================="

# Validate Secret Manager secrets exist
REQUIRED_SECRETS=(
    "whatsapp-business-api-token"
    "database-password"
    "jwt-secret"
    "firebase-admin-sdk"
    "encryption-key"
)

for secret in "${REQUIRED_SECRETS[@]}"; do
    run_check "Secret exists: $secret" "gcloud secrets describe $secret"
done

echo ""
echo -e "${YELLOW}7. MONITORING AND LOGGING VALIDATION${NC}"
echo "=================================================="

# Validate monitoring resources
run_check "Cloud Monitoring workspace" "gcloud alpha monitoring dashboards list --format='value(name)' | head -n1"
run_check "Log-based metrics" "gcloud logging metrics list --format='value(name)' | head -n1"

# Validate alerting policies
run_check "Alerting policies configured" "gcloud alpha monitoring policies list --format='value(name)' | head -n1"

echo ""
echo -e "${YELLOW}8. SECURITY CONFIGURATION VALIDATION${NC}"
echo "=================================================="

# Validate IAM configurations
run_check "Cloud Run service accounts" "gcloud iam service-accounts list --format='value(email)' | grep -q 'genspark'"
run_check "Secret Manager permissions" "gcloud projects get-iam-policy $PROJECT_ID --flatten='bindings[].members' --filter='bindings.role:roles/secretmanager.secretAccessor'"

# Validate VPC security
run_check "VPC firewall rules" "gcloud compute firewall-rules list --filter='name:allow-genspark' --format='value(name)'"

echo ""
echo -e "${YELLOW}9. CI/CD PIPELINE VALIDATION${NC}"
echo "=================================================="

# Validate Cloud Build triggers
run_check "Cloud Build triggers configured" "gcloud builds triggers list --format='value(name)' | grep -q 'genspark'"

# Validate build history
run_check "Recent build success" "gcloud builds list --limit=1 --format='value(status)' | grep -q 'SUCCESS'"

echo ""
echo -e "${YELLOW}10. PERFORMANCE AND SCALING VALIDATION${NC}"
echo "=================================================="

# Validate autoscaling configuration
if [ -n "$FRONTEND_URL" ] && [ -n "$BACKEND_URL" ]; then
    run_check "Frontend autoscaling config" "gcloud run services describe $FRONTEND_SERVICE --region=$REGION --format='value(spec.template.metadata.annotations.\"run.googleapis.com/cpu-throttling\")'"
    run_check "Backend autoscaling config" "gcloud run services describe $BACKEND_SERVICE --region=$REGION --format='value(spec.template.metadata.annotations.\"autoscaling.knative.dev/maxScale\")'"
fi

echo ""
echo -e "${BLUE}=== VALIDATION SUMMARY ===${NC}"
echo "=================================================="
echo -e "Total Checks: ${BLUE}$TOTAL_CHECKS${NC}"
echo -e "Passed: ${GREEN}$PASSED_CHECKS${NC}"
echo -e "Failed: ${RED}$FAILED_CHECKS${NC}"

# Calculate success rate
SUCCESS_RATE=$(( PASSED_CHECKS * 100 / TOTAL_CHECKS ))
echo -e "Success Rate: ${BLUE}$SUCCESS_RATE%${NC}"

if [ $FAILED_CHECKS -eq 0 ]; then
    echo ""
    log_success "All validation checks passed! System is ready for production deployment."
    exit 0
elif [ $SUCCESS_RATE -ge 80 ]; then
    echo ""
    log_warning "Most validation checks passed ($SUCCESS_RATE%). Review failed checks before production deployment."
    exit 1
else
    echo ""
    log_error "Multiple validation checks failed ($SUCCESS_RATE% success rate). System requires attention before deployment."
    exit 2
fi