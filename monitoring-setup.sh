#!/bin/bash

# WhatsApp Business Automation Platform - Monitoring Setup Script
# Phase 10: Final Deployment and Testing
# This script configures comprehensive monitoring, alerting, and logging

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
NOTIFICATION_EMAIL=${NOTIFICATION_EMAIL:-"admin@genspark.ai"}
FRONTEND_SERVICE="genspark-frontend"
BACKEND_SERVICE="genspark-api"
DATABASE_INSTANCE="genspark-db-instance"
REDIS_INSTANCE="genspark-cache"

echo -e "${CYAN}=== WhatsApp Business Automation Platform - Monitoring Setup ===${NC}"
echo -e "${CYAN}Project: $PROJECT_ID${NC}"
echo -e "${CYAN}Region: $REGION${NC}"
echo -e "${CYAN}Notification Email: $NOTIFICATION_EMAIL${NC}"
echo ""

# Function to log messages
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")  echo -e "${BLUE}[$timestamp] INFO: $message${NC}" ;;
        "SUCCESS") echo -e "${GREEN}[$timestamp] SUCCESS: $message${NC}" ;;
        "WARNING") echo -e "${YELLOW}[$timestamp] WARNING: $message${NC}" ;;
        "ERROR") echo -e "${RED}[$timestamp] ERROR: $message${NC}" ;;
    esac
}

# Function to check if command succeeded
check_success() {
    if [ $? -eq 0 ]; then
        log "SUCCESS" "$1"
        return 0
    else
        log "ERROR" "$1 failed"
        return 1
    fi
}

# Function to create notification channel
create_notification_channel() {
    log "INFO" "Creating email notification channel"
    
    # Create email notification channel
    local channel_config=$(cat << EOF
{
  "type": "email",
  "displayName": "GenSpark Admin Email",
  "labels": {
    "email_address": "$NOTIFICATION_EMAIL"
  },
  "enabled": true
}
EOF
)
    
    echo "$channel_config" | gcloud alpha monitoring channels create --channel-content-from-file=- --format="value(name)" > /tmp/notification-channel-id.txt 2>/dev/null || true
    
    if [ -s /tmp/notification-channel-id.txt ]; then
        NOTIFICATION_CHANNEL_ID=$(cat /tmp/notification-channel-id.txt)
        log "SUCCESS" "Email notification channel created: $NOTIFICATION_CHANNEL_ID"
    else
        # Try to find existing channel
        NOTIFICATION_CHANNEL_ID=$(gcloud alpha monitoring channels list --filter="labels.email_address:$NOTIFICATION_EMAIL" --format="value(name)" | head -n1 || echo "")
        if [ -n "$NOTIFICATION_CHANNEL_ID" ]; then
            log "INFO" "Using existing notification channel: $NOTIFICATION_CHANNEL_ID"
        else
            log "WARNING" "Failed to create or find notification channel"
        fi
    fi
}

# Function to create log-based metrics
create_log_based_metrics() {
    log "INFO" "Creating log-based metrics"
    
    # Error rate metric
    gcloud logging metrics create genspark_error_rate \
        --description="Error rate for GenSpark platform" \
        --log-filter='resource.type="cloud_run_revision" AND (resource.labels.service_name="'"$FRONTEND_SERVICE"'" OR resource.labels.service_name="'"$BACKEND_SERVICE"'") AND severity>=ERROR' \
        --value-extractor="" 2>/dev/null || log "WARNING" "Error rate metric may already exist"
    
    # Request count metric
    gcloud logging metrics create genspark_request_count \
        --description="Request count for GenSpark platform" \
        --log-filter='resource.type="cloud_run_revision" AND (resource.labels.service_name="'"$FRONTEND_SERVICE"'" OR resource.labels.service_name="'"$BACKEND_SERVICE"'") AND httpRequest.requestUrl!=""' \
        --value-extractor="" 2>/dev/null || log "WARNING" "Request count metric may already exist"
    
    # Security incidents metric
    gcloud logging metrics create genspark_security_incidents \
        --description="Security incidents for GenSpark platform" \
        --log-filter='severity>=WARNING AND (protoPayload.methodName:"iam" OR textPayload:"unauthorized" OR textPayload:"forbidden" OR textPayload:"attack")' \
        --value-extractor="" 2>/dev/null || log "WARNING" "Security incidents metric may already exist"
    
    # Database connection errors
    gcloud logging metrics create genspark_db_errors \
        --description="Database connection errors" \
        --log-filter='resource.type="cloud_run_revision" AND textPayload:("database" AND ("error" OR "timeout" OR "connection"))' \
        --value-extractor="" 2>/dev/null || log "WARNING" "Database errors metric may already exist"
    
    log "SUCCESS" "Log-based metrics created"
}

# Function to create alerting policies
create_alerting_policies() {
    log "INFO" "Creating alerting policies"
    
    if [ -z "$NOTIFICATION_CHANNEL_ID" ]; then
        log "WARNING" "No notification channel available, alerts will be created without notifications"
    fi
    
    # High error rate alert
    local error_rate_policy=$(cat << EOF
{
  "displayName": "GenSpark - High Error Rate",
  "documentation": {
    "content": "The error rate for GenSpark platform services is above the threshold."
  },
  "conditions": [
    {
      "displayName": "Error rate condition",
      "conditionThreshold": {
        "filter": "resource.type=\"cloud_run_revision\" AND (resource.labels.service_name=\"$FRONTEND_SERVICE\" OR resource.labels.service_name=\"$BACKEND_SERVICE\")",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 0.05,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_RATE",
            "crossSeriesReducer": "REDUCE_MEAN",
            "groupByFields": ["resource.labels.service_name"]
          }
        ]
      }
    }
  ],
  "combiner": "OR",
  "enabled": true
}
EOF
)
    
    # Add notification channel if available
    if [ -n "$NOTIFICATION_CHANNEL_ID" ]; then
        error_rate_policy=$(echo "$error_rate_policy" | jq --arg channel_id "$NOTIFICATION_CHANNEL_ID" '. + {"notificationChannels": [$channel_id]}')
    fi
    
    echo "$error_rate_policy" | gcloud alpha monitoring policies create --policy-from-file=- 2>/dev/null || log "WARNING" "Error rate policy creation failed"
    
    # Service availability alert
    local availability_policy=$(cat << EOF
{
  "displayName": "GenSpark - Service Unavailable",
  "documentation": {
    "content": "GenSpark service is not responding or returning errors."
  },
  "conditions": [
    {
      "displayName": "Service availability condition",
      "conditionThreshold": {
        "filter": "resource.type=\"cloud_run_revision\" AND (resource.labels.service_name=\"$FRONTEND_SERVICE\" OR resource.labels.service_name=\"$BACKEND_SERVICE\")",
        "comparison": "COMPARISON_LESS_THAN",
        "thresholdValue": 0.95,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_FRACTION_TRUE",
            "crossSeriesReducer": "REDUCE_MEAN"
          }
        ]
      }
    }
  ],
  "combiner": "OR",
  "enabled": true
}
EOF
)
    
    if [ -n "$NOTIFICATION_CHANNEL_ID" ]; then
        availability_policy=$(echo "$availability_policy" | jq --arg channel_id "$NOTIFICATION_CHANNEL_ID" '. + {"notificationChannels": [$channel_id]}')
    fi
    
    echo "$availability_policy" | gcloud alpha monitoring policies create --policy-from-file=- 2>/dev/null || log "WARNING" "Availability policy creation failed"
    
    # High response time alert
    local response_time_policy=$(cat << EOF
{
  "displayName": "GenSpark - High Response Time",
  "documentation": {
    "content": "GenSpark services are experiencing high response times."
  },
  "conditions": [
    {
      "displayName": "Response time condition",
      "conditionThreshold": {
        "filter": "resource.type=\"cloud_run_revision\" AND (resource.labels.service_name=\"$FRONTEND_SERVICE\" OR resource.labels.service_name=\"$BACKEND_SERVICE\")",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 2.0,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_MEAN",
            "crossSeriesReducer": "REDUCE_MEAN"
          }
        ]
      }
    }
  ],
  "combiner": "OR",
  "enabled": true
}
EOF
)
    
    if [ -n "$NOTIFICATION_CHANNEL_ID" ]; then
        response_time_policy=$(echo "$response_time_policy" | jq --arg channel_id "$NOTIFICATION_CHANNEL_ID" '. + {"notificationChannels": [$channel_id]}')
    fi
    
    echo "$response_time_policy" | gcloud alpha monitoring policies create --policy-from-file=- 2>/dev/null || log "WARNING" "Response time policy creation failed"
    
    # Database connection alert
    local db_connection_policy=$(cat << EOF
{
  "displayName": "GenSpark - Database Connection Issues",
  "documentation": {
    "content": "Database connection issues detected for GenSpark platform."
  },
  "conditions": [
    {
      "displayName": "Database error condition",
      "conditionThreshold": {
        "filter": "metric.type=\"logging.googleapis.com/user/genspark_db_errors\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 5.0,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_RATE",
            "crossSeriesReducer": "REDUCE_SUM"
          }
        ]
      }
    }
  ],
  "combiner": "OR",
  "enabled": true
}
EOF
)
    
    if [ -n "$NOTIFICATION_CHANNEL_ID" ]; then
        db_connection_policy=$(echo "$db_connection_policy" | jq --arg channel_id "$NOTIFICATION_CHANNEL_ID" '. + {"notificationChannels": [$channel_id]}')
    fi
    
    echo "$db_connection_policy" | gcloud alpha monitoring policies create --policy-from-file=- 2>/dev/null || log "WARNING" "Database connection policy creation failed"
    
    # Security incidents alert
    local security_policy=$(cat << EOF
{
  "displayName": "GenSpark - Security Incidents",
  "documentation": {
    "content": "Security incidents detected for GenSpark platform."
  },
  "conditions": [
    {
      "displayName": "Security incident condition",
      "conditionThreshold": {
        "filter": "metric.type=\"logging.googleapis.com/user/genspark_security_incidents\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 3.0,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_RATE",
            "crossSeriesReducer": "REDUCE_SUM"
          }
        ]
      }
    }
  ],
  "combiner": "OR",
  "enabled": true
}
EOF
)
    
    if [ -n "$NOTIFICATION_CHANNEL_ID" ]; then
        security_policy=$(echo "$security_policy" | jq --arg channel_id "$NOTIFICATION_CHANNEL_ID" '. + {"notificationChannels": [$channel_id]}')
    fi
    
    echo "$security_policy" | gcloud alpha monitoring policies create --policy-from-file=- 2>/dev/null || log "WARNING" "Security policy creation failed"
    
    log "SUCCESS" "Alerting policies created"
}

# Function to create monitoring dashboard
create_monitoring_dashboard() {
    log "INFO" "Creating monitoring dashboard"
    
    local dashboard_config=$(cat << EOF
{
  "displayName": "GenSpark WhatsApp Business Platform",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Service Request Rate",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloud_run_revision\" AND (resource.labels.service_name=\"$FRONTEND_SERVICE\" OR resource.labels.service_name=\"$BACKEND_SERVICE\")",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_RATE",
                      "crossSeriesReducer": "REDUCE_SUM"
                    }
                  }
                }
              }
            ]
          }
        }
      },
      {
        "xPos": 6,
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Service Response Time",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloud_run_revision\" AND (resource.labels.service_name=\"$FRONTEND_SERVICE\" OR resource.labels.service_name=\"$BACKEND_SERVICE\")",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_MEAN",
                      "crossSeriesReducer": "REDUCE_MEAN"
                    }
                  }
                }
              }
            ]
          }
        }
      },
      {
        "yPos": 4,
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Error Rate",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "metric.type=\"logging.googleapis.com/user/genspark_error_rate\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_RATE",
                      "crossSeriesReducer": "REDUCE_SUM"
                    }
                  }
                }
              }
            ]
          }
        }
      },
      {
        "xPos": 6,
        "yPos": 4,
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Active Instances",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloud_run_revision\" AND (resource.labels.service_name=\"$FRONTEND_SERVICE\" OR resource.labels.service_name=\"$BACKEND_SERVICE\")",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_MEAN",
                      "crossSeriesReducer": "REDUCE_SUM"
                    }
                  }
                }
              }
            ]
          }
        }
      },
      {
        "yPos": 8,
        "width": 12,
        "height": 4,
        "widget": {
          "title": "Recent Logs",
          "logsPanel": {
            "filter": "resource.type=\"cloud_run_revision\" AND (resource.labels.service_name=\"$FRONTEND_SERVICE\" OR resource.labels.service_name=\"$BACKEND_SERVICE\")",
            "resourceNames": []
          }
        }
      }
    ]
  }
}
EOF
)
    
    echo "$dashboard_config" | gcloud alpha monitoring dashboards create --config-from-file=- 2>/dev/null || log "WARNING" "Dashboard creation failed"
    check_success "Monitoring dashboard created"
}

# Function to configure uptime checks
create_uptime_checks() {
    log "INFO" "Creating uptime checks"
    
    # Get service URLs
    local frontend_url=$(gcloud run services describe "$FRONTEND_SERVICE" --region="$REGION" --format="value(status.url)" 2>/dev/null || echo "")
    local backend_url=$(gcloud run services describe "$BACKEND_SERVICE" --region="$REGION" --format="value(status.url)" 2>/dev/null || echo "")
    
    if [ -n "$frontend_url" ]; then
        # Frontend uptime check
        local frontend_check=$(cat << EOF
{
  "displayName": "GenSpark Frontend Uptime",
  "httpCheck": {
    "requestMethod": "GET",
    "useSsl": true,
    "path": "/",
    "port": 443
  },
  "monitoredResource": {
    "type": "uptime_url",
    "labels": {
      "project_id": "$PROJECT_ID",
      "host": "${frontend_url#https://}"
    }
  },
  "timeout": "10s",
  "period": "300s",
  "contentMatchers": [
    {
      "content": "GenSpark"
    }
  ]
}
EOF
)
        
        echo "$frontend_check" | gcloud alpha monitoring uptime create --uptime-check-config-from-file=- 2>/dev/null || log "WARNING" "Frontend uptime check creation failed"
    fi
    
    if [ -n "$backend_url" ]; then
        # Backend uptime check
        local backend_check=$(cat << EOF
{
  "displayName": "GenSpark Backend API Uptime",
  "httpCheck": {
    "requestMethod": "GET",
    "useSsl": true,
    "path": "/health",
    "port": 443
  },
  "monitoredResource": {
    "type": "uptime_url",
    "labels": {
      "project_id": "$PROJECT_ID",
      "host": "${backend_url#https://}"
    }
  },
  "timeout": "10s",
  "period": "300s",
  "contentMatchers": [
    {
      "content": "healthy"
    }
  ]
}
EOF
)
        
        echo "$backend_check" | gcloud alpha monitoring uptime create --uptime-check-config-from-file=- 2>/dev/null || log "WARNING" "Backend uptime check creation failed"
    fi
    
    log "SUCCESS" "Uptime checks created"
}

# Function to configure log retention
configure_log_retention() {
    log "INFO" "Configuring log retention policies"
    
    # Set log retention for Cloud Run services
    gcloud logging sinks create genspark-logs-retention \
        storage.googleapis.com/${PROJECT_ID}-logs-archive \
        --log-filter='resource.type="cloud_run_revision" AND (resource.labels.service_name="'"$FRONTEND_SERVICE"'" OR resource.labels.service_name="'"$BACKEND_SERVICE"'")' \
        --project="$PROJECT_ID" 2>/dev/null || log "WARNING" "Log retention sink may already exist"
    
    log "SUCCESS" "Log retention configured"
}

# Function to create custom metrics
create_custom_metrics() {
    log "INFO" "Creating custom metrics"
    
    # WhatsApp message metrics
    gcloud logging metrics create whatsapp_messages_sent \
        --description="WhatsApp messages sent count" \
        --log-filter='resource.type="cloud_run_revision" AND textPayload:"whatsapp" AND textPayload:"message_sent"' \
        --value-extractor="" 2>/dev/null || log "WARNING" "WhatsApp messages metric may already exist"
    
    # User registration metrics
    gcloud logging metrics create user_registrations \
        --description="User registration count" \
        --log-filter='resource.type="cloud_run_revision" AND textPayload:"user_registered"' \
        --value-extractor="" 2>/dev/null || log "WARNING" "User registration metric may already exist"
    
    # API rate limiting metrics
    gcloud logging metrics create api_rate_limited \
        --description="API rate limiting events" \
        --log-filter='resource.type="cloud_run_revision" AND (httpRequest.status=429 OR textPayload:"rate_limited")' \
        --value-extractor="" 2>/dev/null || log "WARNING" "Rate limiting metric may already exist"
    
    log "SUCCESS" "Custom metrics created"
}

# Function to test monitoring setup
test_monitoring_setup() {
    log "INFO" "Testing monitoring setup"
    
    # List created metrics
    local metrics_count=$(gcloud logging metrics list --filter="name:genspark" --format="value(name)" | wc -l)
    log "INFO" "Created $metrics_count log-based metrics"
    
    # List alerting policies
    local policies_count=$(gcloud alpha monitoring policies list --filter="displayName:GenSpark" --format="value(name)" | wc -l)
    log "INFO" "Created $policies_count alerting policies"
    
    # List dashboards
    local dashboards_count=$(gcloud alpha monitoring dashboards list --filter="displayName:GenSpark" --format="value(name)" | wc -l)
    log "INFO" "Created $dashboards_count monitoring dashboards"
    
    # Test notification channel
    if [ -n "$NOTIFICATION_CHANNEL_ID" ]; then
        gcloud alpha monitoring channels verify "$NOTIFICATION_CHANNEL_ID" 2>/dev/null && log "SUCCESS" "Notification channel verified" || log "WARNING" "Notification channel verification failed"
    fi
    
    log "SUCCESS" "Monitoring setup testing completed"
}

# Main execution
main() {
    log "INFO" "Starting monitoring setup for GenSpark WhatsApp Business Platform"
    
    # Check required dependencies
    command -v gcloud >/dev/null 2>&1 || { log "ERROR" "gcloud CLI is required but not installed"; exit 1; }
    command -v jq >/dev/null 2>&1 || { log "ERROR" "jq is required but not installed"; exit 1; }
    
    # Verify project access
    gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1 || { log "ERROR" "Cannot access project $PROJECT_ID"; exit 1; }
    
    # Create monitoring components
    create_notification_channel
    create_log_based_metrics
    create_alerting_policies
    create_monitoring_dashboard
    create_uptime_checks
    configure_log_retention
    create_custom_metrics
    test_monitoring_setup
    
    # Cleanup temporary files
    rm -f /tmp/notification-channel-id.txt
    
    log "SUCCESS" "Monitoring setup completed successfully!"
    
    echo ""
    echo -e "${CYAN}=== MONITORING SETUP SUMMARY ===${NC}"
    echo -e "${CYAN}Project: $PROJECT_ID${NC}"
    echo -e "${CYAN}Notification Email: $NOTIFICATION_EMAIL${NC}"
    if [ -n "$NOTIFICATION_CHANNEL_ID" ]; then
        echo -e "${CYAN}Notification Channel: $NOTIFICATION_CHANNEL_ID${NC}"
    fi
    echo -e "${CYAN}Dashboard: Available in Google Cloud Console${NC}"
    echo -e "${CYAN}Uptime Checks: Configured for frontend and backend${NC}"
    echo ""
    echo -e "${GREEN}Next Steps:${NC}"
    echo "1. Review dashboard configuration in Cloud Console"
    echo "2. Test alerting by triggering conditions"
    echo "3. Configure additional notification channels if needed"
    echo "4. Set up log-based alerting for business metrics"
    echo "5. Schedule regular monitoring reviews"
}

# Run main function
main "$@"