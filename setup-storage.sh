#!/bin/bash

# GenSpark AI - Cloud Storage Setup Script
# Phase 6: Cloud Storage and Secret Manager Setup

# Load environment variables
source .env

echo "========================================="
echo "GenSpark AI - Cloud Storage Setup"
echo "Project ID: $PROJECT_ID"
echo "Region: $REGION"
echo "========================================="

# Step 1: Create Cloud Storage buckets
echo "Step 1: Creating Cloud Storage buckets..."

# Create media files bucket (public read)
gsutil mb -l $REGION gs://$PROJECT_ID-media
echo "Created media bucket: gs://$PROJECT_ID-media"

# Create private files bucket (authenticated access)
gsutil mb -l $REGION gs://$PROJECT_ID-private
echo "Created private bucket: gs://$PROJECT_ID-private"

# Create backup bucket
gsutil mb -l $REGION gs://$PROJECT_ID-backups
echo "Created backup bucket: gs://$PROJECT_ID-backups"

# Step 2: Set bucket permissions
echo ""
echo "Step 2: Setting bucket permissions..."

# Set public read access for media bucket
gsutil iam ch allUsers:objectViewer gs://$PROJECT_ID-media
echo "Set public read access for media bucket"

# Keep private bucket restricted (no public access)
echo "Private bucket access restricted to service accounts"

# Set backup bucket permissions (restricted)
echo "Backup bucket access restricted to service accounts"

# Step 3: Create and apply CORS configuration
echo ""
echo "Step 3: Configuring CORS for web access..."

cat > cors-config.json << EOF
[
  {
    "origin": [
      "https://genspark.ai",
      "https://app.genspark.ai",
      "https://admin.genspark.ai",
      "https://*.pages.dev",
      "http://localhost:3000",
      "http://localhost:3001"
    ],
    "method": ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    "responseHeader": [
      "Content-Type",
      "Access-Control-Allow-Origin",
      "Access-Control-Allow-Methods",
      "Access-Control-Allow-Headers"
    ],
    "maxAgeSeconds": 3600
  }
]
EOF

# Apply CORS to media bucket
gsutil cors set cors-config.json gs://$PROJECT_ID-media
echo "CORS configuration applied to media bucket"

# Clean up CORS file
rm cors-config.json

# Step 4: Create lifecycle configuration for backups
echo ""
echo "Step 4: Setting up lifecycle management..."

cat > lifecycle-config.json << EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {
          "type": "SetStorageClass",
          "storageClass": "COLDLINE"
        },
        "condition": {
          "age": 30
        }
      },
      {
        "action": {
          "type": "Delete"
        },
        "condition": {
          "age": 365
        }
      }
    ]
  }
}
EOF

# Apply lifecycle configuration to backup bucket
gsutil lifecycle set lifecycle-config.json gs://$PROJECT_ID-backups
echo "Lifecycle configuration applied to backup bucket"

# Clean up lifecycle file
rm lifecycle-config.json

# Step 5: Create storage access keys and permissions
echo ""
echo "Step 5: Configuring storage access permissions..."

# Grant storage access to service account
gsutil iam ch serviceAccount:$SERVICE_ACCOUNT:objectAdmin gs://$PROJECT_ID-media
gsutil iam ch serviceAccount:$SERVICE_ACCOUNT:objectAdmin gs://$PROJECT_ID-private
gsutil iam ch serviceAccount:$SERVICE_ACCOUNT:objectAdmin gs://$PROJECT_ID-backups

echo "Storage permissions granted to service account"

# Step 6: Test bucket access
echo ""
echo "Step 6: Testing bucket access..."

# Create a test file
echo "GenSpark AI Storage Test - $(date)" > test-file.txt

# Upload test file to media bucket
gsutil cp test-file.txt gs://$PROJECT_ID-media/test/
echo "Test file uploaded to media bucket"

# Upload test file to private bucket
gsutil cp test-file.txt gs://$PROJECT_ID-private/test/
echo "Test file uploaded to private bucket"

# List bucket contents
echo "Media bucket contents:"
gsutil ls gs://$PROJECT_ID-media/test/

echo "Private bucket contents:"
gsutil ls gs://$PROJECT_ID-private/test/

# Clean up test file
rm test-file.txt
gsutil rm gs://$PROJECT_ID-media/test/test-file.txt
gsutil rm gs://$PROJECT_ID-private/test/test-file.txt

echo "Test files cleaned up"

# Step 7: Save bucket information
echo ""
echo "Step 7: Saving storage configuration..."

echo "" >> ~/genspark-credentials.txt
echo "Cloud Storage Configuration:" >> ~/genspark-credentials.txt
echo "Media Bucket: gs://$PROJECT_ID-media" >> ~/genspark-credentials.txt
echo "Private Bucket: gs://$PROJECT_ID-private" >> ~/genspark-credentials.txt
echo "Backup Bucket: gs://$PROJECT_ID-backups" >> ~/genspark-credentials.txt
echo "Media URL: https://storage.googleapis.com/$PROJECT_ID-media" >> ~/genspark-credentials.txt

echo ""
echo "========================================="
echo "Cloud Storage Setup Complete!"
echo "========================================="
echo ""
echo "Buckets created:"
echo "  📁 Media (public): gs://$PROJECT_ID-media"
echo "  🔒 Private: gs://$PROJECT_ID-private" 
echo "  💾 Backups: gs://$PROJECT_ID-backups"
echo ""
echo "Configuration:"
echo "  ✓ CORS enabled for web access"
echo "  ✓ Lifecycle management for backups"
echo "  ✓ Service account permissions granted"
echo "  ✓ Public read access for media bucket"
echo ""
echo "Next: Run setup-secrets.sh for Secret Manager"
echo "========================================="