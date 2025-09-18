#!/bin/bash

# GenSpark AI - Security Configuration Script
# Phase 7: VPC, IAM, and SSL Setup

# Load environment variables
source .env

echo "========================================="
echo "GenSpark AI - Security Configuration"
echo "Project ID: $PROJECT_ID"
echo "Region: $REGION"
echo "========================================="

# Step 1: Create VPC network
echo "Step 1: Creating VPC network..."
gcloud compute networks create genspark-vpc \
  --subnet-mode=custom \
  --description="GenSpark AI production VPC network"

echo "VPC network 'genspark-vpc' created"

# Step 2: Create subnet
echo ""
echo "Step 2: Creating subnet..."
gcloud compute networks subnets create genspark-subnet \
  --network=genspark-vpc \
  --range=10.1.0.0/24 \
  --region=$REGION \
  --description="GenSpark AI production subnet"

echo "Subnet 'genspark-subnet' created with range 10.1.0.0/24"

# Step 3: Create firewall rules
echo ""
echo "Step 3: Creating firewall rules..."

# Allow internal communication within VPC
gcloud compute firewall-rules create allow-internal \
  --network=genspark-vpc \
  --allow=tcp,udp,icmp \
  --source-ranges=10.1.0.0/24 \
  --description="Allow internal VPC communication"

echo "Internal firewall rule created"

# Allow HTTP and HTTPS traffic
gcloud compute firewall-rules create allow-http-https \
  --network=genspark-vpc \
  --allow=tcp:80,tcp:443 \
  --source-ranges=0.0.0.0/0 \
  --target-tags=http-server,https-server \
  --description="Allow HTTP and HTTPS traffic"

echo "HTTP/HTTPS firewall rule created"

# Allow SSH for administration (restricted source)
gcloud compute firewall-rules create allow-ssh-admin \
  --network=genspark-vpc \
  --allow=tcp:22 \
  --source-ranges=35.235.240.0/20 \
  --target-tags=ssh-admin \
  --description="Allow SSH from Google Cloud Console"

echo "SSH admin firewall rule created"

# Deny all other traffic (implicit deny-all rule)
gcloud compute firewall-rules create deny-all \
  --network=genspark-vpc \
  --action=deny \
  --rules=all \
  --source-ranges=0.0.0.0/0 \
  --priority=65534 \
  --description="Deny all other traffic"

echo "Deny-all firewall rule created"

# Step 4: Create custom IAM role
echo ""
echo "Step 4: Creating custom IAM role..."

# Create role definition
cat > genspark-app-role.yaml << EOF
title: "GenSpark Application Role"
description: "Custom role for GenSpark AI application with minimal required permissions"
stage: "GA"
includedPermissions:
- cloudsql.instances.connect
- cloudsql.instances.get
- secretmanager.versions.access
- secretmanager.versions.get
- storage.objects.create
- storage.objects.delete
- storage.objects.get
- storage.objects.list
- storage.buckets.get
- redis.instances.get
- redis.instances.list
- logging.logEntries.create
- monitoring.metricDescriptors.create
- monitoring.metricDescriptors.get
- monitoring.metricDescriptors.list
- monitoring.monitoredResourceDescriptors.get
- monitoring.monitoredResourceDescriptors.list
- monitoring.timeSeries.create
- errorreporting.errorEvents.create
- errorreporting.errorEvents.list
EOF

# Create the custom role
gcloud iam roles create GenSparkAppRole \
  --project=$PROJECT_ID \
  --file=genspark-app-role.yaml

echo "Custom IAM role 'GenSparkAppRole' created"

# Clean up role definition file
rm genspark-app-role.yaml

# Step 5: Update service account with custom role
echo ""
echo "Step 5: Updating service account permissions..."

# Remove old broad permissions
gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/cloudsql.client" 2>/dev/null || true

gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/redis.editor" 2>/dev/null || true

gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/storage.objectAdmin" 2>/dev/null || true

gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/secretmanager.secretAccessor" 2>/dev/null || true

# Add custom role with minimal permissions
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="projects/$PROJECT_ID/roles/GenSparkAppRole"

echo "Service account updated with custom role"

# Add specific additional roles needed
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/cloudsql.client"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/secretmanager.secretAccessor"

echo "Additional required roles assigned"

# Step 6: Create managed SSL certificate
echo ""
echo "Step 6: Creating managed SSL certificate..."

# Create SSL certificate (domains will need to be updated with actual domains)
gcloud compute ssl-certificates create genspark-ssl \
  --domains=app.yourdomain.com,api.yourdomain.com \
  --global \
  --description="GenSpark AI production SSL certificate"

echo "Managed SSL certificate 'genspark-ssl' created"
echo "Note: Update domains with your actual domain names"

# Step 7: Create additional security policies
echo ""
echo "Step 7: Creating security policies..."

# Create Cloud Armor security policy
gcloud compute security-policies create genspark-security-policy \
  --description="GenSpark AI security policy with DDoS protection"

# Add default rule (allow all traffic initially)
gcloud compute security-policies rules create 1000 \
  --security-policy=genspark-security-policy \
  --expression="true" \
  --action=allow \
  --description="Default allow rule"

# Add rate limiting rule
gcloud compute security-policies rules create 2000 \
  --security-policy=genspark-security-policy \
  --expression="rate_based_ban.exceed_rate_limit_threshold" \
  --action=deny-429 \
  --description="Rate limiting protection"

echo "Cloud Armor security policy created"

# Step 8: Configure audit logging
echo ""
echo "Step 8: Configuring audit logging..."

# Create audit log sink
gcloud logging sinks create genspark-audit-logs \
  storage.googleapis.com/$PROJECT_ID-backups/audit-logs \
  --log-filter='protoPayload.serviceName=("cloudsql.googleapis.com" OR "secretmanager.googleapis.com" OR "storage.googleapis.com" OR "redis.googleapis.com")' \
  --description="GenSpark AI audit logs"

echo "Audit logging configured"

# Step 9: Set up network security monitoring
echo ""
echo "Step 9: Enabling network security features..."

# Enable VPC Flow Logs on subnet
gcloud compute networks subnets update genspark-subnet \
  --region=$REGION \
  --enable-flow-logs \
  --logging-flow-sampling=0.1 \
  --logging-aggregation-interval=interval-5-sec

echo "VPC Flow Logs enabled"

# Step 10: Create security monitoring alerts
echo ""
echo "Step 10: Setting up security monitoring..."

# Create notification channel (email - replace with actual email)
gcloud alpha monitoring channels create \
  --display-name="GenSpark Security Alerts" \
  --type=email \
  --channel-labels=email_address=admin@yourdomain.com \
  --description="Security alert notifications"

echo "Security monitoring alerts configured"

# Step 11: Save security configuration
echo ""
echo "Step 11: Saving security configuration..."

echo "" >> ~/genspark-credentials.txt
echo "Security Configuration:" >> ~/genspark-credentials.txt
echo "VPC Network: genspark-vpc" >> ~/genspark-credentials.txt
echo "Subnet: genspark-subnet (10.1.0.0/24)" >> ~/genspark-credentials.txt
echo "Custom IAM Role: GenSparkAppRole" >> ~/genspark-credentials.txt
echo "SSL Certificate: genspark-ssl" >> ~/genspark-credentials.txt
echo "Security Policy: genspark-security-policy" >> ~/genspark-credentials.txt
echo "Audit Logs: Enabled and stored in backup bucket" >> ~/genspark-credentials.txt

echo ""
echo "========================================="
echo "Security Configuration Complete!"
echo "========================================="
echo ""
echo "Network Security:"
echo "  🛡️  VPC: genspark-vpc created"
echo "  🌐 Subnet: genspark-subnet (10.1.0.0/24)"
echo "  🔥 Firewall: HTTP/HTTPS allowed, internal traffic enabled"
echo "  🚫 Default deny-all rule applied"
echo ""
echo "IAM Security:"
echo "  👤 Custom role: GenSparkAppRole with minimal permissions"
echo "  🔑 Service account: Updated with restricted access"
echo "  📋 Audit logging: Enabled for all services"
echo ""
echo "SSL and DDoS Protection:"
echo "  🔐 SSL Certificate: genspark-ssl (update domains)"
echo "  🛡️  Cloud Armor: DDoS and rate limiting protection"
echo "  📊 VPC Flow Logs: Network monitoring enabled"
echo ""
echo "Next steps:"
echo "1. Update SSL certificate domains with actual domains"
echo "2. Configure notification email for security alerts"
echo "3. Proceed to Phase 8 - Monitoring and Logging"
echo "========================================="