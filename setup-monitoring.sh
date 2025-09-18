#!/bin/bash

# GenSpark AI - Monitoring and Logging Setup Script
# Phase 8: Monitoring, Logging, and Alerting Configuration

# Load environment variables
source .env

echo "========================================="
echo "GenSpark AI - Monitoring & Logging Setup"
echo "Project ID: $PROJECT_ID"
echo "Region: $REGION"
echo "========================================="

# Step 1: Create BigQuery dataset for log analysis
echo "Step 1: Creating BigQuery dataset for logs..."
bq mk --dataset \
  --description="GenSpark AI application logs dataset" \
  --location=US \
  $PROJECT_ID:app_logs

echo "BigQuery dataset 'app_logs' created"

# Step 2: Create Cloud Logging sinks
echo ""
echo "Step 2: Creating Cloud Logging sinks..."

# Create log sink for application logs
gcloud logging sinks create genspark-app-logs \
  bigquery.googleapis.com/projects/$PROJECT_ID/datasets/app_logs \
  --log-filter='resource.type="cloud_run_revision" AND resource.labels.service_name=("genspark-frontend" OR "genspark-api")' \
  --description="GenSpark AI application logs sink"

echo "Application logs sink created"

# Create log sink for audit logs (already created in Phase 7, but ensure it exists)
gcloud logging sinks create genspark-security-logs \
  storage.googleapis.com/$PROJECT_ID-backups/security-logs \
  --log-filter='protoPayload.serviceName=("iam.googleapis.com" OR "cloudresourcemanager.googleapis.com")' \
  --description="GenSpark AI security audit logs" 2>/dev/null || echo "Security logs sink already exists"

# Create log sink for error logs
gcloud logging sinks create genspark-error-logs \
  bigquery.googleapis.com/projects/$PROJECT_ID/datasets/app_logs \
  --log-filter='severity>=ERROR' \
  --description="GenSpark AI error logs sink"

echo "Error logs sink created"

# Step 3: Create notification channels
echo ""
echo "Step 3: Creating notification channels..."

# Create email notification channel
NOTIFICATION_CHANNEL=$(gcloud alpha monitoring channels create \
  --display-name="GenSpark Admin Email" \
  --type=email \
  --channel-labels=email_address=admin@yourdomain.com \
  --description="Primary admin email notifications" \
  --format="value(name)")

echo "Email notification channel created: $NOTIFICATION_CHANNEL"

# Create Slack notification channel (if webhook URL provided)
# gcloud alpha monitoring channels create \
#   --display-name="GenSpark Slack Alerts" \
#   --type=slack \
#   --channel-labels=url=https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK \
#   --description="Slack channel notifications"

# Step 4: Create alerting policies
echo ""
echo "Step 4: Creating alerting policies..."

# CPU usage alert policy
cat > cpu-alert-policy.yaml << EOF
displayName: "High CPU Usage Alert"
documentation:
  content: "This alert fires when CPU usage is above 80% for 5 minutes"
  mimeType: "text/markdown"
conditions:
  - displayName: "CPU usage condition"
    conditionThreshold:
      filter: 'resource.type="cloud_run_revision" AND resource.labels.service_name=("genspark-frontend" OR "genspark-api")'
      comparison: "COMPARISON_GREATER_THAN"
      thresholdValue: 0.8
      duration: "300s"
      aggregations:
        - alignmentPeriod: "60s"
          perSeriesAligner: "ALIGN_MEAN"
          crossSeriesReducer: "REDUCE_MEAN"
          groupByFields:
            - "resource.labels.service_name"
combiner: "OR"
enabled: true
notificationChannels:
  - "$NOTIFICATION_CHANNEL"
EOF

gcloud alpha monitoring policies create --policy-from-file=cpu-alert-policy.yaml
echo "CPU usage alert policy created"

# Error rate alert policy
cat > error-rate-policy.yaml << EOF
displayName: "High Error Rate Alert"
documentation:
  content: "This alert fires when error rate is above 5% for 2 minutes"
  mimeType: "text/markdown"
conditions:
  - displayName: "Error rate condition"
    conditionThreshold:
      filter: 'resource.type="cloud_run_revision" AND resource.labels.service_name=("genspark-frontend" OR "genspark-api")'
      comparison: "COMPARISON_GREATER_THAN"
      thresholdValue: 0.05
      duration: "120s"
      aggregations:
        - alignmentPeriod: "60s"
          perSeriesAligner: "ALIGN_RATE"
          crossSeriesReducer: "REDUCE_MEAN"
          groupByFields:
            - "resource.labels.service_name"
combiner: "OR"
enabled: true
notificationChannels:
  - "$NOTIFICATION_CHANNEL"
EOF

gcloud alpha monitoring policies create --policy-from-file=error-rate-policy.yaml
echo "Error rate alert policy created"

# Memory usage alert policy
cat > memory-alert-policy.yaml << EOF
displayName: "High Memory Usage Alert"
documentation:
  content: "This alert fires when memory usage is above 85% for 5 minutes"
  mimeType: "text/markdown"
conditions:
  - displayName: "Memory usage condition"
    conditionThreshold:
      filter: 'resource.type="cloud_run_revision" AND resource.labels.service_name=("genspark-frontend" OR "genspark-api")'
      comparison: "COMPARISON_GREATER_THAN"
      thresholdValue: 0.85
      duration: "300s"
      aggregations:
        - alignmentPeriod: "60s"
          perSeriesAligner: "ALIGN_MEAN"
          crossSeriesReducer: "REDUCE_MEAN"
          groupByFields:
            - "resource.labels.service_name"
combiner: "OR"
enabled: true
notificationChannels:
  - "$NOTIFICATION_CHANNEL"
EOF

gcloud alpha monitoring policies create --policy-from-file=memory-alert-policy.yaml
echo "Memory usage alert policy created"

# Database connection alert policy
cat > database-alert-policy.yaml << EOF
displayName: "Database Connection Issues"
documentation:
  content: "This alert fires when database connection errors occur"
  mimeType: "text/markdown"
conditions:
  - displayName: "Database connection condition"
    conditionThreshold:
      filter: 'resource.type="cloudsql_database" AND resource.labels.database_id="genspark-db"'
      comparison: "COMPARISON_GREATER_THAN"
      thresholdValue: 0
      duration: "60s"
      aggregations:
        - alignmentPeriod: "60s"
          perSeriesAligner: "ALIGN_RATE"
          crossSeriesReducer: "REDUCE_SUM"
combiner: "OR"
enabled: true
notificationChannels:
  - "$NOTIFICATION_CHANNEL"
EOF

gcloud alpha monitoring policies create --policy-from-file=database-alert-policy.yaml
echo "Database connection alert policy created"

# Step 5: Set up budget alerts
echo ""
echo "Step 5: Setting up cost monitoring and budgets..."

# Create budget alert
gcloud billing budgets create \
  --billing-account=$BILLING_ACCOUNT \
  --display-name="GenSpark Monthly Budget" \
  --budget-amount=100USD \
  --threshold-rules-percent=50,90 \
  --notification-channels=$NOTIFICATION_CHANNEL \
  --filter-projects=$PROJECT_ID \
  --description="GenSpark AI monthly spending budget with alerts at 50% and 90%"

echo "Monthly budget created with $100 limit and alerts at 50% and 90%"

# Step 6: Create custom dashboard
echo ""
echo "Step 6: Creating custom monitoring dashboard..."

cat > dashboard-config.json << EOF
{
  "displayName": "GenSpark AI Operations Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Cloud Run CPU Utilization",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=(\"genspark-frontend\" OR \"genspark-api\")",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_MEAN",
                      "crossSeriesReducer": "REDUCE_MEAN",
                      "groupByFields": ["resource.labels.service_name"]
                    }
                  }
                },
                "plotType": "LINE"
              }
            ],
            "timeshiftDuration": "0s",
            "yAxis": {
              "label": "CPU Utilization",
              "scale": "LINEAR"
            }
          }
        }
      },
      {
        "xPos": 6,
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Cloud Run Memory Utilization",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=(\"genspark-frontend\" OR \"genspark-api\")",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_MEAN",
                      "crossSeriesReducer": "REDUCE_MEAN",
                      "groupByFields": ["resource.labels.service_name"]
                    }
                  }
                },
                "plotType": "LINE"
              }
            ],
            "timeshiftDuration": "0s",
            "yAxis": {
              "label": "Memory Utilization",
              "scale": "LINEAR"
            }
          }
        }
      },
      {
        "yPos": 4,
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Request Count and Error Rate",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=(\"genspark-frontend\" OR \"genspark-api\")",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_RATE",
                      "crossSeriesReducer": "REDUCE_SUM",
                      "groupByFields": ["resource.labels.service_name"]
                    }
                  }
                },
                "plotType": "LINE"
              }
            ],
            "timeshiftDuration": "0s",
            "yAxis": {
              "label": "Requests/sec",
              "scale": "LINEAR"
            }
          }
        }
      },
      {
        "xPos": 6,
        "yPos": 4,
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Database Connections",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloudsql_database\" AND resource.labels.database_id=\"genspark-db\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_MEAN",
                      "crossSeriesReducer": "REDUCE_MEAN"
                    }
                  }
                },
                "plotType": "LINE"
              }
            ],
            "timeshiftDuration": "0s",
            "yAxis": {
              "label": "Active Connections",
              "scale": "LINEAR"
            }
          }
        }
      }
    ]
  }
}
EOF

gcloud monitoring dashboards create --config-from-file=dashboard-config.json
echo "Custom operations dashboard created"

# Step 7: Configure log-based metrics
echo ""
echo "Step 7: Creating log-based metrics..."

# Create metric for application errors
gcloud logging metrics create genspark_application_errors \
  --description="Count of application errors" \
  --log-filter='resource.type="cloud_run_revision" AND severity>=ERROR AND resource.labels.service_name=("genspark-frontend" OR "genspark-api")'

# Create metric for WhatsApp API calls
gcloud logging metrics create genspark_whatsapp_api_calls \
  --description="Count of WhatsApp API calls" \
  --log-filter='resource.type="cloud_run_revision" AND jsonPayload.message:"WhatsApp API"'

# Create metric for user logins
gcloud logging metrics create genspark_user_logins \
  --description="Count of user authentication events" \
  --log-filter='resource.type="cloud_run_revision" AND jsonPayload.event:"user_login"'

echo "Log-based metrics created"

# Step 8: Configure uptime checks
echo ""
echo "Step 8: Setting up uptime monitoring..."

# Create uptime check for API health endpoint
gcloud monitoring uptime create \
  --display-name="GenSpark API Health Check" \
  --http-check-path="/health" \
  --hostname="api.yourdomain.com" \
  --port=443 \
  --use-ssl \
  --timeout=10s \
  --period=60s

# Create uptime check for frontend
gcloud monitoring uptime create \
  --display-name="GenSpark Frontend Health Check" \
  --http-check-path="/" \
  --hostname="app.yourdomain.com" \
  --port=443 \
  --use-ssl \
  --timeout=10s \
  --period=60s

echo "Uptime monitoring configured"

# Step 9: Clean up temporary files
echo ""
echo "Step 9: Cleaning up temporary files..."
rm -f cpu-alert-policy.yaml error-rate-policy.yaml memory-alert-policy.yaml database-alert-policy.yaml dashboard-config.json

# Step 10: Save monitoring configuration
echo ""
echo "Step 10: Saving monitoring configuration..."

echo "" >> ~/genspark-credentials.txt
echo "Monitoring and Logging Configuration:" >> ~/genspark-credentials.txt
echo "BigQuery Dataset: app_logs" >> ~/genspark-credentials.txt
echo "Log Sinks: genspark-app-logs, genspark-security-logs, genspark-error-logs" >> ~/genspark-credentials.txt
echo "Notification Channel: $NOTIFICATION_CHANNEL" >> ~/genspark-credentials.txt
echo "Budget Alert: $100 USD with 50% and 90% thresholds" >> ~/genspark-credentials.txt
echo "Dashboard: GenSpark AI Operations Dashboard" >> ~/genspark-credentials.txt
echo "Uptime Checks: API and Frontend health monitoring" >> ~/genspark-credentials.txt

echo ""
echo "========================================="
echo "Monitoring and Logging Setup Complete!"
echo "========================================="
echo ""
echo "Logging Infrastructure:"
echo "  📊 BigQuery dataset: app_logs"
echo "  📝 Application logs sink: genspark-app-logs"
echo "  🔒 Security logs sink: genspark-security-logs"
echo "  ❌ Error logs sink: genspark-error-logs"
echo ""
echo "Monitoring and Alerting:"
echo "  📧 Email notifications: admin@yourdomain.com"
echo "  🚨 CPU usage alerts: >80% for 5 minutes"
echo "  ❌ Error rate alerts: >5% for 2 minutes"
echo "  💾 Memory alerts: >85% for 5 minutes"
echo "  🗄️  Database connection alerts: Any failures"
echo ""
echo "Cost Management:"
echo "  💰 Monthly budget: $100 USD"
echo "  ⚠️  Alerts at 50% and 90% spending"
echo ""
echo "Performance Monitoring:"
echo "  📈 Custom operations dashboard created"
echo "  📊 Log-based metrics for key events"
echo "  🏃 Uptime checks for API and frontend"
echo ""
echo "Next steps:"
echo "1. Update notification email addresses"
echo "2. Update uptime check domains"
echo "3. Proceed to Phase 9 - CI/CD Pipeline"
echo "========================================="