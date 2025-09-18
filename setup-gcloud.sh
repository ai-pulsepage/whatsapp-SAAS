#!/bin/bash

# GenSpark AI - Google Cloud Setup Script
# Phase 1: Google Cloud Project Setup

# Load environment variables
source .env

echo "========================================="
echo "GenSpark AI - Google Cloud Setup"
echo "Project ID: $PROJECT_ID"
echo "Region: $REGION" 
echo "Zone: $ZONE"
echo "========================================="

# Step 1: Authenticate (requires user interaction)
echo "Step 1: Authenticate with Google Cloud..."
gcloud auth login
gcloud auth application-default login

# Step 2: Create project
echo "Step 2: Creating Google Cloud project..."
gcloud projects create $PROJECT_ID --name="GenSpark AI Production"
gcloud config set project $PROJECT_ID

# Step 3: Link billing account (user must provide billing account ID)
echo "Step 3: Link billing account..."
echo "Please run: gcloud billing accounts list"
echo "Then run: gcloud billing projects link $PROJECT_ID --billing-account=YOUR-BILLING-ACCOUNT-ID"

# Step 4: Enable required APIs
echo "Step 4: Enabling required APIs..."

# Core services
gcloud services enable cloudbuild.googleapis.com
gcloud services enable run.googleapis.com
gcloud services enable sql-component.googleapis.com
gcloud services enable sqladmin.googleapis.com
gcloud services enable redis.googleapis.com
gcloud services enable storage-component.googleapis.com
gcloud services enable secretmanager.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com

# Firebase services
gcloud services enable firebase.googleapis.com
gcloud services enable identitytoolkit.googleapis.com

# Monitoring and logging
gcloud services enable logging.googleapis.com
gcloud services enable monitoring.googleapis.com
gcloud services enable errorreporting.googleapis.com

# AI and ML services (for future features)
gcloud services enable aiplatform.googleapis.com
gcloud services enable translate.googleapis.com

echo "APIs enabled successfully!"

# Step 5: Create service account
echo "Step 5: Creating service account..."
gcloud iam service-accounts create genspark-app-sa \
  --display-name="GenSpark Application Service Account" \
  --description="Service account for GenSpark AI application"

export SERVICE_ACCOUNT="genspark-app-sa@${PROJECT_ID}.iam.gserviceaccount.com"

# Grant necessary roles
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/cloudsql.client"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/redis.editor"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/storage.objectAdmin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/secretmanager.secretAccessor"

# Create and download service account key
gcloud iam service-accounts keys create ~/genspark-service-account.json \
  --iam-account=$SERVICE_ACCOUNT

echo "Service account created and key saved to ~/genspark-service-account.json"

echo "========================================="
echo "Phase 1 Complete!"
echo "Next: Run Phase 2 - Database Setup"
echo "========================================="