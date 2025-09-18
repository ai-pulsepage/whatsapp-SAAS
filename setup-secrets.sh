#!/bin/bash

# GenSpark AI - Secret Manager Setup Script
# Phase 6: Secret Manager Configuration

# Load environment variables
source .env

echo "========================================="
echo "GenSpark AI - Secret Manager Setup"
echo "Project ID: $PROJECT_ID"
echo "========================================="

# Step 1: Create database connection string secret
echo "Step 1: Creating database connection secret..."
if [ -f ~/genspark-credentials.txt ]; then
    DB_PASSWORD=$(grep "Application database password:" ~/genspark-credentials.txt | cut -d' ' -f4)
    if [ ! -z "$DB_PASSWORD" ]; then
        echo "postgresql://genspark_app:$DB_PASSWORD@/genspark_production?host=/cloudsql/$PROJECT_ID:$REGION:genspark-db" | gcloud secrets create database-url --data-file=-
        echo "Database URL secret created"
    else
        echo "Database password not found in credentials file"
        echo "Please run setup-database.sh first"
    fi
else
    echo "Credentials file not found. Creating placeholder..."
    echo "postgresql://genspark_app:PLACEHOLDER_PASSWORD@/genspark_production?host=/cloudsql/$PROJECT_ID:$REGION:genspark-db" | gcloud secrets create database-url --data-file=-
    echo "Database URL secret created with placeholder"
fi

# Step 2: Create WhatsApp credentials (user must provide)
echo ""
echo "Step 2: Creating WhatsApp API secrets..."
echo "PLACEHOLDER_WHATSAPP_ACCESS_TOKEN" | gcloud secrets create whatsapp-access-token --data-file=-
echo "WhatsApp access token secret created (placeholder)"

echo "PLACEHOLDER_WEBHOOK_VERIFY_TOKEN" | gcloud secrets create webhook-verify-token --data-file=-
echo "Webhook verify token secret created (placeholder)"

echo "PLACEHOLDER_WHATSAPP_APP_SECRET" | gcloud secrets create whatsapp-app-secret --data-file=-
echo "WhatsApp app secret created (placeholder)"

# Step 3: Create AI service API keys (user must provide)
echo ""
echo "Step 3: Creating AI service API secrets..."
echo "PLACEHOLDER_ANTHROPIC_API_KEY" | gcloud secrets create anthropic-api-key --data-file=-
echo "Anthropic API key secret created (placeholder)"

echo "PLACEHOLDER_OPENAI_API_KEY" | gcloud secrets create openai-api-key --data-file=-
echo "OpenAI API key secret created (placeholder)"

echo "PLACEHOLDER_GOOGLE_AI_API_KEY" | gcloud secrets create google-ai-api-key --data-file=-
echo "Google AI API key secret created (placeholder)"

# Step 4: Generate and create JWT secret
echo ""
echo "Step 4: Creating JWT secret..."
JWT_SECRET=$(openssl rand -base64 64 | tr -d '\n')
echo "$JWT_SECRET" | gcloud secrets create jwt-secret --data-file=-
echo "JWT secret created and saved"

# Step 5: Generate and create encryption key
echo ""
echo "Step 5: Creating encryption key..."
ENCRYPTION_KEY=$(openssl rand -base64 32 | tr -d '\n')
echo "$ENCRYPTION_KEY" | gcloud secrets create encryption-key --data-file=-
echo "Encryption key created and saved"

# Step 6: Create session secret
echo ""
echo "Step 6: Creating session secret..."
SESSION_SECRET=$(openssl rand -base64 48 | tr -d '\n')
echo "$SESSION_SECRET" | gcloud secrets create session-secret --data-file=-
echo "Session secret created and saved"

# Step 7: Create webhook secrets for security
echo ""
echo "Step 7: Creating webhook security secrets..."
WEBHOOK_SECRET=$(openssl rand -base64 32 | tr -d '\n')
echo "$WEBHOOK_SECRET" | gcloud secrets create webhook-secret --data-file=-
echo "Webhook secret created and saved"

# Step 8: Create API rate limiting secret
echo ""
echo "Step 8: Creating API security secrets..."
API_SECRET=$(openssl rand -base64 32 | tr -d '\n')
echo "$API_SECRET" | gcloud secrets create api-secret --data-file=-
echo "API security secret created and saved"

# Step 9: Grant secret access to service account
echo ""
echo "Step 9: Granting secret access permissions..."

# List of all secrets
SECRETS=(
    "database-url"
    "whatsapp-access-token"
    "webhook-verify-token"
    "whatsapp-app-secret"
    "anthropic-api-key"
    "openai-api-key"
    "google-ai-api-key"
    "jwt-secret"
    "encryption-key"
    "session-secret"
    "webhook-secret"
    "api-secret"
)

# Grant access for each secret
for secret in "${SECRETS[@]}"; do
    gcloud secrets add-iam-policy-binding $secret \
        --member="serviceAccount:$SERVICE_ACCOUNT" \
        --role="roles/secretmanager.secretAccessor"
    echo "Granted access to secret: $secret"
done

# Step 10: Test secret access
echo ""
echo "Step 10: Testing secret access..."
echo "Testing JWT secret access:"
gcloud secrets versions access latest --secret="jwt-secret" --format="get(payload.data)" | head -c 20
echo "... (truncated)"

# Step 11: Create secrets management utilities
echo ""
echo "Step 11: Creating secrets reference file..."

cat > secret-references.txt << EOF
# GenSpark AI - Secret Manager References
# Use these references in your application environment variables

# Database
DATABASE_URL=gcloud secrets versions access latest --secret="database-url"

# WhatsApp Business API
WHATSAPP_ACCESS_TOKEN=gcloud secrets versions access latest --secret="whatsapp-access-token"
WEBHOOK_VERIFY_TOKEN=gcloud secrets versions access latest --secret="webhook-verify-token"
WHATSAPP_APP_SECRET=gcloud secrets versions access latest --secret="whatsapp-app-secret"

# AI Services
ANTHROPIC_API_KEY=gcloud secrets versions access latest --secret="anthropic-api-key"
OPENAI_API_KEY=gcloud secrets versions access latest --secret="openai-api-key"
GOOGLE_AI_API_KEY=gcloud secrets versions access latest --secret="google-ai-api-key"

# Application Security
JWT_SECRET=gcloud secrets versions access latest --secret="jwt-secret"
ENCRYPTION_KEY=gcloud secrets versions access latest --secret="encryption-key"
SESSION_SECRET=gcloud secrets versions access latest --secret="session-secret"
WEBHOOK_SECRET=gcloud secrets versions access latest --secret="webhook-secret"
API_SECRET=gcloud secrets versions access latest --secret="api-secret"

# Update commands for secrets:
# gcloud secrets versions add [SECRET_NAME] --data-file=[FILE]
# echo "new_value" | gcloud secrets versions add [SECRET_NAME] --data-file=-
EOF

# Step 12: Save secret information
echo ""
echo "Step 12: Saving secret configuration..."

echo "" >> ~/genspark-credentials.txt
echo "Secret Manager Configuration:" >> ~/genspark-credentials.txt
echo "JWT Secret: [STORED IN SECRET MANAGER]" >> ~/genspark-credentials.txt
echo "Encryption Key: [STORED IN SECRET MANAGER]" >> ~/genspark-credentials.txt
echo "Session Secret: [STORED IN SECRET MANAGER]" >> ~/genspark-credentials.txt
echo "Webhook Secret: [STORED IN SECRET MANAGER]" >> ~/genspark-credentials.txt
echo "API Secret: [STORED IN SECRET MANAGER]" >> ~/genspark-credentials.txt
echo "" >> ~/genspark-credentials.txt
echo "IMPORTANT: Update placeholder secrets with real values:" >> ~/genspark-credentials.txt
echo "- WhatsApp Access Token" >> ~/genspark-credentials.txt
echo "- Anthropic API Key" >> ~/genspark-credentials.txt
echo "- OpenAI API Key" >> ~/genspark-credentials.txt
echo "- Google AI API Key" >> ~/genspark-credentials.txt

echo ""
echo "========================================="
echo "Secret Manager Setup Complete!"
echo "========================================="
echo ""
echo "Secrets created (12 total):"
echo "  🔐 database-url"
echo "  🔐 whatsapp-access-token (placeholder)"
echo "  🔐 webhook-verify-token (placeholder)"
echo "  🔐 whatsapp-app-secret (placeholder)"
echo "  🔐 anthropic-api-key (placeholder)"
echo "  🔐 openai-api-key (placeholder)"
echo "  🔐 google-ai-api-key (placeholder)"
echo "  🔐 jwt-secret (generated)"
echo "  🔐 encryption-key (generated)"
echo "  🔐 session-secret (generated)"
echo "  🔐 webhook-secret (generated)"
echo "  🔐 api-secret (generated)"
echo ""
echo "Next steps:"
echo "1. Update placeholder secrets with real values"
echo "2. See secret-references.txt for usage examples"
echo "3. Proceed to Phase 7 - Security Configuration"
echo "========================================="