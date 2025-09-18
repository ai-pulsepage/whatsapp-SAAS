#!/bin/bash

# GenSpark AI - CI/CD Pipeline Setup Script
# Phase 9: Cloud Build and GitHub Integration

# Load environment variables
source .env

echo "========================================="
echo "GenSpark AI - CI/CD Pipeline Setup"
echo "Project ID: $PROJECT_ID"
echo "Region: $REGION"
echo "========================================="

# Step 1: Enable Container Registry API
echo "Step 1: Enabling Container Registry API..."
gcloud services enable containerregistry.googleapis.com
echo "Container Registry API enabled"

# Step 2: Configure Docker authentication
echo ""
echo "Step 2: Configuring Docker authentication..."
gcloud auth configure-docker --quiet
echo "Docker authentication configured"

# Step 3: Create VPC connector for Cloud Run
echo ""
echo "Step 3: Creating VPC connector for Cloud Run..."
gcloud compute networks vpc-access connectors create genspark-connector \
  --region=$REGION \
  --subnet=genspark-subnet \
  --subnet-project=$PROJECT_ID \
  --min-instances=2 \
  --max-instances=10 \
  --machine-type=e2-micro

echo "VPC connector 'genspark-connector' created"

# Step 4: Grant Cloud Build service account permissions
echo ""
echo "Step 4: Configuring Cloud Build permissions..."

# Get Cloud Build service account email
CLOUD_BUILD_SA=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")@cloudbuild.gserviceaccount.com

# Grant necessary roles to Cloud Build service account
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$CLOUD_BUILD_SA" \
  --role="roles/run.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$CLOUD_BUILD_SA" \
  --role="roles/iam.serviceAccountUser"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$CLOUD_BUILD_SA" \
  --role="roles/storage.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$CLOUD_BUILD_SA" \
  --role="roles/secretmanager.secretAccessor"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$CLOUD_BUILD_SA" \
  --role="roles/vpcaccess.user"

echo "Cloud Build service account permissions configured"

# Step 5: Create GitHub build trigger (requires manual GitHub connection)
echo ""
echo "Step 5: Setting up GitHub integration..."

echo "To complete GitHub integration, follow these steps:"
echo ""
echo "1. Go to Cloud Build > Triggers in Google Cloud Console"
echo "2. Click 'Connect Repository'"
echo "3. Select GitHub and authenticate"
echo "4. Choose your GenSpark AI repository"
echo "5. Create a trigger with these settings:"
echo "   - Name: genspark-production-deploy"
echo "   - Event: Push to branch"
echo "   - Branch: ^main$"
echo "   - Configuration: Cloud Build configuration file"
echo "   - Location: cloudbuild.yaml"
echo ""

# Step 6: Create Cloud Build configuration for manual trigger setup
cat > build-trigger-config.yaml << EOF
name: genspark-production-deploy
description: "GenSpark AI production deployment trigger"
github:
  owner: your-github-username
  name: genspark-ai
  push:
    branch: ^main$
filename: cloudbuild.yaml
substitutions:
  _SERVICE_SUFFIX: ""
  _ENVIRONMENT: "production"
  _REGION: "us-central1"
includeBuildLogs: INCLUDE_BUILD_LOGS_WITH_STATUS
EOF

echo "Build trigger configuration created: build-trigger-config.yaml"

# Step 7: Set up build notifications
echo ""
echo "Step 7: Setting up build notifications..."

# Create Pub/Sub topic for build notifications
gcloud pubsub topics create cloud-builds

# Create notification configuration
cat > build-notification-config.yaml << EOF
name: projects/$PROJECT_ID/notificationConfigs/genspark-build-notifications
pubsubConfig:
  topic: projects/$PROJECT_ID/topics/cloud-builds
slackConfig:
  webhook:
    url: your-slack-webhook-url
filter: build.status in [BUILD_FAILURE, BUILD_SUCCESS]
EOF

echo "Build notification configuration created"

# Step 8: Create deployment environments
echo ""
echo "Step 8: Creating deployment environments..."

# Create staging environment configuration
cat > staging-deployment.yaml << EOF
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: genspark-frontend-staging
  namespace: default
  annotations:
    run.googleapis.com/ingress: all
    run.googleapis.com/execution-environment: gen2
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/minScale: "0"
        autoscaling.knative.dev/maxScale: "5"
        run.googleapis.com/vpc-access-connector: genspark-connector
        run.googleapis.com/vpc-access-egress: private-ranges-only
        run.googleapis.com/service-account: genspark-app-sa@$PROJECT_ID.iam.gserviceaccount.com
    spec:
      containerConcurrency: 80
      timeoutSeconds: 300
      containers:
      - image: gcr.io/$PROJECT_ID/genspark-frontend:latest
        ports:
        - name: http1
          containerPort: 3000
        env:
        - name: NODE_ENV
          value: staging
        - name: NEXT_PUBLIC_API_URL
          value: https://genspark-api-staging-uc.a.run.app
        resources:
          limits:
            cpu: 1000m
            memory: 1Gi
EOF

echo "Staging deployment configuration created"

# Step 9: Create rollback script
echo ""
echo "Step 9: Creating rollback capabilities..."

cat > rollback-deployment.sh << 'EOF'
#!/bin/bash

# GenSpark AI - Deployment Rollback Script

if [ -z "$1" ]; then
    echo "Usage: $0 <revision-number>"
    echo "Example: $0 genspark-frontend-00005"
    exit 1
fi

REVISION=$1
SERVICE_NAME=$(echo $REVISION | cut -d'-' -f1-2)
REGION="us-central1"

echo "Rolling back $SERVICE_NAME to revision $REVISION..."

# Rollback the service
gcloud run services update-traffic $SERVICE_NAME \
    --to-revisions=$REVISION=100 \
    --region=$REGION

echo "Rollback completed. Checking service health..."

# Health check
sleep 30
if [ "$SERVICE_NAME" == "genspark-frontend" ]; then
    curl -f "https://$SERVICE_NAME-uc.a.run.app/" || echo "Health check failed"
else
    curl -f "https://$SERVICE_NAME-uc.a.run.app/health" || echo "Health check failed"
fi

echo "Rollback verification completed"
EOF

chmod +x rollback-deployment.sh
echo "Rollback script created: rollback-deployment.sh"

# Step 10: Create deployment validation script
echo ""
echo "Step 10: Creating deployment validation..."

cat > validate-deployment.sh << 'EOF'
#!/bin/bash

# GenSpark AI - Deployment Validation Script

FRONTEND_URL="https://genspark-frontend-uc.a.run.app"
BACKEND_URL="https://genspark-api-uc.a.run.app"

echo "Validating GenSpark AI deployment..."

# Test frontend
echo "Testing frontend..."
if curl -f -s "$FRONTEND_URL/" > /dev/null; then
    echo "✓ Frontend is accessible"
else
    echo "✗ Frontend is not accessible"
    exit 1
fi

# Test backend health endpoint
echo "Testing backend health..."
if curl -f -s "$BACKEND_URL/health" > /dev/null; then
    echo "✓ Backend health check passed"
else
    echo "✗ Backend health check failed"
    exit 1
fi

# Test backend API
echo "Testing backend API..."
API_RESPONSE=$(curl -s "$BACKEND_URL/api/health" | jq -r '.status' 2>/dev/null)
if [ "$API_RESPONSE" == "healthy" ]; then
    echo "✓ Backend API is healthy"
else
    echo "✗ Backend API is not responding correctly"
    exit 1
fi

# Test database connectivity
echo "Testing database connectivity..."
DB_RESPONSE=$(curl -s "$BACKEND_URL/api/health/database" | jq -r '.database' 2>/dev/null)
if [ "$DB_RESPONSE" == "connected" ]; then
    echo "✓ Database connectivity verified"
else
    echo "✗ Database connectivity issues"
    exit 1
fi

# Test Redis connectivity
echo "Testing Redis connectivity..."
REDIS_RESPONSE=$(curl -s "$BACKEND_URL/api/health/redis" | jq -r '.redis' 2>/dev/null)
if [ "$REDIS_RESPONSE" == "connected" ]; then
    echo "✓ Redis connectivity verified"
else
    echo "✗ Redis connectivity issues"
    exit 1
fi

echo "All deployment validation tests passed!"
EOF

chmod +x validate-deployment.sh
echo "Deployment validation script created: validate-deployment.sh"

# Step 11: Save CI/CD configuration
echo ""
echo "Step 11: Saving CI/CD configuration..."

echo "" >> ~/genspark-credentials.txt
echo "CI/CD Pipeline Configuration:" >> ~/genspark-credentials.txt
echo "Cloud Build Service Account: $CLOUD_BUILD_SA" >> ~/genspark-credentials.txt
echo "VPC Connector: genspark-connector" >> ~/genspark-credentials.txt
echo "Container Registry: gcr.io/$PROJECT_ID" >> ~/genspark-credentials.txt
echo "Build Configuration: cloudbuild.yaml" >> ~/genspark-credentials.txt
echo "GitHub Integration: Manual setup required" >> ~/genspark-credentials.txt
echo "Notification Topic: cloud-builds" >> ~/genspark-credentials.txt

echo ""
echo "========================================="
echo "CI/CD Pipeline Setup Complete!"
echo "========================================="
echo ""
echo "Infrastructure Created:"
echo "  🔧 VPC Connector: genspark-connector"
echo "  🐳 Container Registry: gcr.io/$PROJECT_ID"
echo "  📦 Build configurations and scripts"
echo "  🔄 Rollback and validation scripts"
echo ""
echo "Cloud Build Permissions:"
echo "  ✓ Cloud Run admin access"
echo "  ✓ Service account user access"
echo "  ✓ Storage admin access"
echo "  ✓ Secret Manager access"
echo "  ✓ VPC connector access"
echo ""
echo "Manual Steps Required:"
echo "1. Connect GitHub repository in Cloud Console"
echo "2. Create build trigger using build-trigger-config.yaml"
echo "3. Configure Slack webhook in build-notification-config.yaml"
echo "4. Update GitHub repository settings in build-trigger-config.yaml"
echo ""
echo "Files Created:"
echo "  📋 cloudbuild.yaml - Main CI/CD pipeline"
echo "  ⚙️  build-trigger-config.yaml - GitHub trigger config"
echo "  📢 build-notification-config.yaml - Build notifications"
echo "  🎯 staging-deployment.yaml - Staging environment"
echo "  ↩️  rollback-deployment.sh - Emergency rollback script"
echo "  ✅ validate-deployment.sh - Deployment verification"
echo ""
echo "Next: Proceed to Phase 10 - Final Deployment and Testing"
echo "========================================="