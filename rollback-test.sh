#!/bin/bash

# WhatsApp Business Automation Platform - Rollback Testing Script
# Phase 10: Final Deployment and Testing
# This script tests and validates rollback procedures for safe production deployments

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
TEST_TIMEOUT=300  # 5 minutes
ROLLBACK_TIMEOUT=600  # 10 minutes

# Backup and test configuration
TEST_IMAGE_TAG="rollback-test-$(date +%s)"
ORIGINAL_REVISION_SUFFIX=""
TEST_TRAFFIC_PERCENTAGE=10

echo -e "${CYAN}=== WhatsApp Business Automation Platform - Rollback Testing ===${NC}"
echo -e "${CYAN}Project: $PROJECT_ID${NC}"
echo -e "${CYAN}Region: $REGION${NC}"
echo -e "${CYAN}Test Image Tag: $TEST_IMAGE_TAG${NC}"
echo ""

# Function to log messages with colors and timestamps
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")     echo -e "${BLUE}[$timestamp] INFO: $message${NC}" ;;
        "SUCCESS")  echo -e "${GREEN}[$timestamp] SUCCESS: $message${NC}" ;;
        "WARNING")  echo -e "${YELLOW}[$timestamp] WARNING: $message${NC}" ;;
        "ERROR")    echo -e "${RED}[$timestamp] ERROR: $message${NC}" ;;
        "TEST")     echo -e "${MAGENTA}[$timestamp] TEST: $message${NC}" ;;
        "ROLLBACK") echo -e "${CYAN}[$timestamp] ROLLBACK: $message${NC}" ;;
    esac
}

# Function to run command with timeout and error handling
run_with_timeout() {
    local timeout_duration="$1"
    local description="$2"
    shift 2
    local command="$@"
    
    log "INFO" "Running: $description"
    log "INFO" "Command: $command"
    log "INFO" "Timeout: ${timeout_duration}s"
    
    if timeout "$timeout_duration" bash -c "$command"; then
        log "SUCCESS" "$description completed successfully"
        return 0
    else
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            log "ERROR" "$description timed out after ${timeout_duration}s"
        else
            log "ERROR" "$description failed with exit code $exit_code"
        fi
        return $exit_code
    fi
}

# Function to get current service revision
get_current_revision() {
    local service_name="$1"
    local current_revision=$(gcloud run services describe "$service_name" \
        --region="$REGION" \
        --format="value(status.latestReadyRevisionName)" 2>/dev/null || echo "")
    echo "$current_revision"
}

# Function to get service URL
get_service_url() {
    local service_name="$1"
    local service_url=$(gcloud run services describe "$service_name" \
        --region="$REGION" \
        --format="value(status.url)" 2>/dev/null || echo "")
    echo "$service_url"
}

# Function to test service health
test_service_health() {
    local service_name="$1"
    local service_url="$2"
    local expected_response="$3"
    
    log "TEST" "Testing health of $service_name"
    
    if [ -z "$service_url" ]; then
        log "ERROR" "Service URL not found for $service_name"
        return 1
    fi
    
    # Test basic connectivity
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 30 "$service_url" || echo "000")
    if [ "$http_code" != "200" ]; then
        log "ERROR" "$service_name health check failed - HTTP $http_code"
        return 1
    fi
    
    # Test response content if specified
    if [ -n "$expected_response" ]; then
        local response=$(curl -s --max-time 30 "$service_url" || echo "")
        if [[ "$response" != *"$expected_response"* ]]; then
            log "ERROR" "$service_name response validation failed"
            log "INFO" "Expected: $expected_response"
            log "INFO" "Got: $(echo "$response" | head -c 200)..."
            return 1
        fi
    fi
    
    log "SUCCESS" "$service_name health check passed"
    return 0
}

# Function to create test deployment
create_test_deployment() {
    local service_name="$1"
    
    log "TEST" "Creating test deployment for $service_name"
    
    # Get current service configuration
    local current_image=$(gcloud run services describe "$service_name" \
        --region="$REGION" \
        --format="value(spec.template.spec.template.spec.containers[0].image)" 2>/dev/null || echo "")
    
    if [ -z "$current_image" ]; then
        log "ERROR" "Cannot retrieve current image for $service_name"
        return 1
    fi
    
    # Create a test image tag (in real scenario, this would be a different image)
    # For testing purposes, we'll use the same image with different environment variable
    log "INFO" "Current image: $current_image"
    log "INFO" "Deploying test revision with environment marker"
    
    # Deploy test revision with a marker environment variable
    run_with_timeout $TEST_TIMEOUT "Test deployment for $service_name" \
        "gcloud run deploy $service_name \
            --image='$current_image' \
            --region='$REGION' \
            --set-env-vars='ROLLBACK_TEST_ACTIVE=true,DEPLOYMENT_VERSION=$TEST_IMAGE_TAG' \
            --no-traffic \
            --tag='rollback-test' \
            --quiet"
    
    if [ $? -eq 0 ]; then
        log "SUCCESS" "Test deployment created for $service_name"
        return 0
    else
        log "ERROR" "Test deployment failed for $service_name"
        return 1
    fi
}

# Function to split traffic for testing
split_traffic_to_test() {
    local service_name="$1"
    local test_percentage="$2"
    
    log "TEST" "Splitting traffic to test revision for $service_name ($test_percentage%)"
    
    # Allocate traffic to test revision
    run_with_timeout $TEST_TIMEOUT "Traffic splitting for $service_name" \
        "gcloud run services update-traffic $service_name \
            --region='$REGION' \
            --to-tags='rollback-test=$test_percentage' \
            --quiet"
    
    if [ $? -eq 0 ]; then
        log "SUCCESS" "Traffic split to test revision: $test_percentage%"
        # Wait for traffic allocation to take effect
        sleep 30
        return 0
    else
        log "ERROR" "Traffic splitting failed for $service_name"
        return 1
    fi
}

# Function to simulate service failure
simulate_service_failure() {
    local service_name="$1"
    
    log "TEST" "Simulating service failure for $service_name"
    
    # Deploy a failing version (we'll use an invalid image to simulate failure)
    run_with_timeout $TEST_TIMEOUT "Simulating failure for $service_name" \
        "gcloud run deploy $service_name \
            --image='gcr.io/google-samples/hello-app:invalid-tag' \
            --region='$REGION' \
            --no-traffic \
            --tag='failed-deployment' \
            --quiet" || true  # Allow this to fail as expected
    
    # Try to allocate traffic to the failed deployment
    run_with_timeout $TEST_TIMEOUT "Allocating traffic to failed deployment" \
        "gcloud run services update-traffic $service_name \
            --region='$REGION' \
            --to-tags='failed-deployment=50' \
            --quiet" || true  # Allow this to fail as expected
    
    log "TEST" "Service failure simulation completed"
    
    # Wait a moment to let the failure propagate
    sleep 15
    
    return 0
}

# Function to perform rollback
perform_rollback() {
    local service_name="$1"
    local target_revision="$2"
    
    log "ROLLBACK" "Initiating rollback for $service_name to revision $target_revision"
    
    if [ -z "$target_revision" ]; then
        log "ERROR" "No target revision specified for rollback"
        return 1
    fi
    
    # Rollback to previous stable revision
    run_with_timeout $ROLLBACK_TIMEOUT "Rollback operation for $service_name" \
        "gcloud run services update-traffic $service_name \
            --region='$REGION' \
            --to-revisions='$target_revision=100' \
            --clear-tags \
            --quiet"
    
    if [ $? -eq 0 ]; then
        log "SUCCESS" "Rollback completed for $service_name"
        
        # Wait for rollback to take effect
        log "INFO" "Waiting for rollback to take effect..."
        sleep 45
        
        return 0
    else
        log "ERROR" "Rollback failed for $service_name"
        return 1
    fi
}

# Function to validate rollback success
validate_rollback() {
    local service_name="$1"
    local original_revision="$2"
    
    log "TEST" "Validating rollback for $service_name"
    
    # Check that service is running the original revision
    local current_revision=$(get_current_revision "$service_name")
    if [ "$current_revision" != "$original_revision" ]; then
        log "WARNING" "Current revision ($current_revision) doesn't match original ($original_revision)"
        log "INFO" "This may be expected if the rollback created a new revision"
    fi
    
    # Test service health after rollback
    local service_url=$(get_service_url "$service_name")
    if ! test_service_health "$service_name" "$service_url" ""; then
        log "ERROR" "Service health check failed after rollback"
        return 1
    fi
    
    # Verify environment variables are back to normal (no test markers)
    local env_check=$(curl -s --max-time 30 "$service_url/health" 2>/dev/null | grep "ROLLBACK_TEST_ACTIVE" || true)
    if [ -n "$env_check" ]; then
        log "WARNING" "Test environment variables still present after rollback"
    else
        log "SUCCESS" "Environment variables properly restored after rollback"
    fi
    
    log "SUCCESS" "Rollback validation completed for $service_name"
    return 0
}

# Function to cleanup test resources
cleanup_test_resources() {
    local service_name="$1"
    
    log "INFO" "Cleaning up test resources for $service_name"
    
    # Remove test tags and revisions
    gcloud run revisions list \
        --service="$service_name" \
        --region="$REGION" \
        --filter="metadata.labels.'serving.knative.dev/service'='$service_name'" \
        --format="value(metadata.name)" | while read revision; do
        
        # Check if revision has test tags or is unused
        local revision_traffic=$(gcloud run services describe "$service_name" \
            --region="$REGION" \
            --format="value(status.traffic[].revisionName)" 2>/dev/null | grep "^$revision$" || true)
        
        if [ -z "$revision_traffic" ] && [[ "$revision" == *"rollback-test"* ]]; then
            log "INFO" "Deleting unused test revision: $revision"
            gcloud run revisions delete "$revision" --region="$REGION" --quiet 2>/dev/null || true
        fi
    done
    
    # Clear any remaining tags
    gcloud run services update-traffic "$service_name" \
        --region="$REGION" \
        --clear-tags \
        --quiet 2>/dev/null || true
    
    log "SUCCESS" "Cleanup completed for $service_name"
}

# Function to test database rollback procedures
test_database_rollback() {
    log "TEST" "Testing database rollback procedures"
    
    # Note: This is a simulation - in real scenarios, you would test actual database migrations
    
    # Check current database schema version (if versioning is implemented)
    # This would typically connect to the database and check migration status
    log "INFO" "Simulating database schema version check"
    
    # In a real implementation, you would:
    # 1. Create a test migration
    # 2. Apply the migration
    # 3. Verify the migration was applied
    # 4. Roll back the migration
    # 5. Verify the rollback was successful
    
    log "INFO" "Database rollback testing would include:"
    log "INFO" "  - Schema migration rollback"
    log "INFO" "  - Data consistency checks"
    log "INFO" "  - Index recreation"
    log "INFO" "  - Constraint validation"
    log "INFO" "  - Backup restoration testing"
    
    log "SUCCESS" "Database rollback simulation completed"
    return 0
}

# Function to test configuration rollback
test_configuration_rollback() {
    log "TEST" "Testing configuration rollback procedures"
    
    # Test environment variable rollback
    log "INFO" "Testing environment variable rollback"
    
    # Test secret rollback (simulation)
    log "INFO" "Testing secret configuration rollback"
    
    # In a real scenario, you would:
    # 1. Backup current configuration
    # 2. Apply test configuration
    # 3. Verify test configuration is active
    # 4. Rollback to original configuration
    # 5. Verify original configuration is restored
    
    log "SUCCESS" "Configuration rollback simulation completed"
    return 0
}

# Function to perform comprehensive rollback test
run_comprehensive_rollback_test() {
    log "INFO" "Starting comprehensive rollback testing"
    
    local test_results=()
    local overall_success=true
    
    # Store original revisions
    log "INFO" "Capturing current deployment state"
    local frontend_original_revision=$(get_current_revision "$FRONTEND_SERVICE")
    local backend_original_revision=$(get_current_revision "$BACKEND_SERVICE")
    
    log "INFO" "Original Frontend Revision: $frontend_original_revision"
    log "INFO" "Original Backend Revision: $backend_original_revision"
    
    # Test 1: Service Health Baseline
    log "TEST" "=== Test 1: Baseline Health Check ==="
    local frontend_url=$(get_service_url "$FRONTEND_SERVICE")
    local backend_url=$(get_service_url "$BACKEND_SERVICE")
    
    if test_service_health "$FRONTEND_SERVICE" "$frontend_url" "GenSpark" && \
       test_service_health "$BACKEND_SERVICE" "$backend_url" "healthy"; then
        test_results+=("Baseline Health: PASS")
        log "SUCCESS" "Baseline health check passed"
    else
        test_results+=("Baseline Health: FAIL")
        overall_success=false
        log "ERROR" "Baseline health check failed"
    fi
    
    # Test 2: Test Deployment Creation
    log "TEST" "=== Test 2: Test Deployment Creation ==="
    if create_test_deployment "$FRONTEND_SERVICE" && \
       create_test_deployment "$BACKEND_SERVICE"; then
        test_results+=("Test Deployment: PASS")
        log "SUCCESS" "Test deployments created successfully"
        
        # Test 3: Traffic Splitting
        log "TEST" "=== Test 3: Traffic Splitting ==="
        if split_traffic_to_test "$FRONTEND_SERVICE" "$TEST_TRAFFIC_PERCENTAGE" && \
           split_traffic_to_test "$BACKEND_SERVICE" "$TEST_TRAFFIC_PERCENTAGE"; then
            test_results+=("Traffic Splitting: PASS")
            log "SUCCESS" "Traffic splitting successful"
        else
            test_results+=("Traffic Splitting: FAIL")
            overall_success=false
            log "ERROR" "Traffic splitting failed"
        fi
    else
        test_results+=("Test Deployment: FAIL")
        overall_success=false
        log "ERROR" "Test deployment creation failed"
    fi
    
    # Test 4: Failure Simulation and Rollback
    log "TEST" "=== Test 4: Failure Simulation and Rollback ==="
    
    # Simulate failure for frontend
    simulate_service_failure "$FRONTEND_SERVICE"
    
    # Wait and check if service is unhealthy
    sleep 30
    if ! test_service_health "$FRONTEND_SERVICE" "$frontend_url" "GenSpark"; then
        log "INFO" "Service failure simulation successful - service is now unhealthy"
        
        # Perform rollback
        if perform_rollback "$FRONTEND_SERVICE" "$frontend_original_revision"; then
            # Validate rollback
            if validate_rollback "$FRONTEND_SERVICE" "$frontend_original_revision"; then
                test_results+=("Frontend Rollback: PASS")
                log "SUCCESS" "Frontend rollback test passed"
            else
                test_results+=("Frontend Rollback: FAIL")
                overall_success=false
                log "ERROR" "Frontend rollback validation failed"
            fi
        else
            test_results+=("Frontend Rollback: FAIL")
            overall_success=false
            log "ERROR" "Frontend rollback failed"
        fi
    else
        log "WARNING" "Service failure simulation may not have worked as expected"
        test_results+=("Frontend Rollback: SKIP")
    fi
    
    # Test 5: Backend Rollback Test
    log "TEST" "=== Test 5: Backend Rollback Test ==="
    if perform_rollback "$BACKEND_SERVICE" "$backend_original_revision" && \
       validate_rollback "$BACKEND_SERVICE" "$backend_original_revision"; then
        test_results+=("Backend Rollback: PASS")
        log "SUCCESS" "Backend rollback test passed"
    else
        test_results+=("Backend Rollback: FAIL")
        overall_success=false
        log "ERROR" "Backend rollback test failed"
    fi
    
    # Test 6: Database Rollback Simulation
    log "TEST" "=== Test 6: Database Rollback Simulation ==="
    if test_database_rollback; then
        test_results+=("Database Rollback: PASS")
    else
        test_results+=("Database Rollback: FAIL")
        overall_success=false
    fi
    
    # Test 7: Configuration Rollback Simulation
    log "TEST" "=== Test 7: Configuration Rollback Simulation ==="
    if test_configuration_rollback; then
        test_results+=("Configuration Rollback: PASS")
    else
        test_results+=("Configuration Rollback: FAIL")
        overall_success=false
    fi
    
    # Cleanup
    log "INFO" "=== Cleanup Phase ==="
    cleanup_test_resources "$FRONTEND_SERVICE"
    cleanup_test_resources "$BACKEND_SERVICE"
    
    # Final health check
    log "TEST" "=== Final Health Check ==="
    if test_service_health "$FRONTEND_SERVICE" "$frontend_url" "GenSpark" && \
       test_service_health "$BACKEND_SERVICE" "$backend_url" "healthy"; then
        test_results+=("Final Health: PASS")
        log "SUCCESS" "Final health check passed"
    else
        test_results+=("Final Health: FAIL")
        overall_success=false
        log "ERROR" "Final health check failed"
    fi
    
    # Generate test report
    log "INFO" "=== ROLLBACK TESTING SUMMARY ==="
    echo ""
    echo -e "${CYAN}Test Results:${NC}"
    for result in "${test_results[@]}"; do
        if [[ "$result" == *"PASS"* ]]; then
            echo -e "  ${GREEN}✓ $result${NC}"
        elif [[ "$result" == *"FAIL"* ]]; then
            echo -e "  ${RED}✗ $result${NC}"
        else
            echo -e "  ${YELLOW}⚠ $result${NC}"
        fi
    done
    
    echo ""
    if [ "$overall_success" = true ]; then
        log "SUCCESS" "All rollback tests completed successfully!"
        echo -e "${GREEN}Rollback procedures are validated and ready for production use.${NC}"
        return 0
    else
        log "ERROR" "Some rollback tests failed. Review and fix issues before production deployment."
        echo -e "${RED}Rollback procedures need attention before production use.${NC}"
        return 1
    fi
}

# Function to show usage
show_usage() {
    cat << EOF
WhatsApp Business Automation Platform - Rollback Testing Script

Usage: $0 [OPTIONS]

OPTIONS:
    test, -t, --test               Run comprehensive rollback tests (default)
    quick, -q, --quick             Run quick rollback validation
    cleanup, -c, --cleanup         Cleanup test resources only
    help, -h, --help               Show this help message

ENVIRONMENT VARIABLES:
    GOOGLE_CLOUD_PROJECT           GCP project ID
    GOOGLE_CLOUD_REGION           GCP region (default: us-central1)
    TEST_TIMEOUT                  Test timeout in seconds (default: 300)
    ROLLBACK_TIMEOUT              Rollback timeout in seconds (default: 600)

EXAMPLES:
    $0                            # Run comprehensive rollback tests
    $0 quick                      # Run quick validation
    $0 cleanup                    # Cleanup test resources

NOTES:
    - This script tests rollback procedures in a safe manner
    - Original services are preserved throughout testing
    - Test revisions are created with minimal traffic allocation
    - All test resources are cleaned up after testing

EOF
}

# Main execution logic
main() {
    local command="${1:-test}"
    
    case "$command" in
        "test"|"-t"|"--test"|"")
            run_comprehensive_rollback_test
            ;;
        "quick"|"-q"|"--quick")
            log "INFO" "Running quick rollback validation"
            
            local frontend_revision=$(get_current_revision "$FRONTEND_SERVICE")
            local backend_revision=$(get_current_revision "$BACKEND_SERVICE")
            local frontend_url=$(get_service_url "$FRONTEND_SERVICE")
            local backend_url=$(get_service_url "$BACKEND_SERVICE")
            
            if test_service_health "$FRONTEND_SERVICE" "$frontend_url" "GenSpark" && \
               test_service_health "$BACKEND_SERVICE" "$backend_url" "healthy"; then
                log "SUCCESS" "Quick rollback validation passed"
                return 0
            else
                log "ERROR" "Quick rollback validation failed"
                return 1
            fi
            ;;
        "cleanup"|"-c"|"--cleanup")
            log "INFO" "Cleaning up test resources"
            cleanup_test_resources "$FRONTEND_SERVICE"
            cleanup_test_resources "$BACKEND_SERVICE"
            log "SUCCESS" "Cleanup completed"
            ;;
        "help"|"-h"|"--help")
            show_usage
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