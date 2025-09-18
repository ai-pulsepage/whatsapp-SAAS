#!/bin/bash

# GenSpark AI - Database Setup Script
# Phase 2: Cloud SQL PostgreSQL Setup

# Load environment variables
source .env

echo "========================================="
echo "GenSpark AI - Database Setup"
echo "Project ID: $PROJECT_ID"
echo "Region: $REGION"
echo "========================================="

# Step 1: Create PostgreSQL instance
echo "Step 1: Creating Cloud SQL PostgreSQL instance..."
gcloud sql instances create genspark-db \
  --database-version=POSTGRES_15 \
  --tier=db-f1-micro \
  --region=$REGION \
  --backup-start-time=02:00 \
  --enable-bin-log \
  --storage-type=SSD \
  --storage-size=20GB \
  --storage-auto-increase

echo "PostgreSQL instance created successfully!"

# Step 2: Set root password
echo "Step 2: Setting root password..."
export DB_ROOT_PASSWORD="$(openssl rand -base64 32)"
gcloud sql users set-password postgres \
  --instance=genspark-db \
  --password=$DB_ROOT_PASSWORD

echo "Database root password: $DB_ROOT_PASSWORD" >> ~/genspark-credentials.txt
echo "Root password set and saved to ~/genspark-credentials.txt"

# Step 3: Create application database
echo "Step 3: Creating application database..."
gcloud sql databases create genspark_production --instance=genspark-db
echo "Application database 'genspark_production' created!"

# Step 4: Create application user
echo "Step 4: Creating application user..."
export DB_APP_PASSWORD="$(openssl rand -base64 32)"
gcloud sql users create genspark_app \
  --instance=genspark-db \
  --password=$DB_APP_PASSWORD

echo "Application database password: $DB_APP_PASSWORD" >> ~/genspark-credentials.txt
echo "Application user 'genspark_app' created and password saved!"

# Step 5: Get connection details
echo "Step 5: Getting database connection details..."
echo "Connection Name:"
gcloud sql instances describe genspark-db --format="value(connectionName)"
echo "IP Address:"
gcloud sql instances describe genspark-db --format="value(ipAddresses[0].ipAddress)"

# Save connection details to credentials file
echo "" >> ~/genspark-credentials.txt
echo "Database Connection Details:" >> ~/genspark-credentials.txt
echo "Connection Name: $(gcloud sql instances describe genspark-db --format='value(connectionName)')" >> ~/genspark-credentials.txt
echo "IP Address: $(gcloud sql instances describe genspark-db --format='value(ipAddresses[0].ipAddress)')" >> ~/genspark-credentials.txt
echo "Database URL: postgresql://genspark_app:$DB_APP_PASSWORD@/genspark_production?host=/cloudsql/$PROJECT_ID:$REGION:genspark-db" >> ~/genspark-credentials.txt

echo ""
echo "========================================="
echo "Database Setup Complete!"
echo ""
echo "Next steps:"
echo "1. Connect to database and run schema setup"
echo "2. Enable required PostgreSQL extensions"
echo "3. Run initial migrations"
echo ""
echo "Connection command:"
echo "gcloud sql connect genspark-db --user=postgres"
echo ""
echo "All credentials saved to ~/genspark-credentials.txt"
echo "========================================="