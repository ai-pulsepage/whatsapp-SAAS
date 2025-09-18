#!/bin/bash

# GenSpark AI - Database Connection Script
# Connect to Cloud SQL PostgreSQL and setup schema

# Load environment variables
source .env

echo "========================================="
echo "GenSpark AI - Database Connection"
echo "Project ID: $PROJECT_ID"
echo "========================================="

# Get database connection details
echo "Getting database connection details..."
CONNECTION_NAME=$(gcloud sql instances describe genspark-db --format="value(connectionName)")
IP_ADDRESS=$(gcloud sql instances describe genspark-db --format="value(ipAddresses[0].ipAddress)")

echo "Connection Name: $CONNECTION_NAME"
echo "IP Address: $IP_ADDRESS"

# Option 1: Connect via Cloud SQL Proxy (Recommended for production)
echo ""
echo "Option 1: Using Cloud SQL Proxy (Recommended)"
echo "----------------------------------------"
echo "1. Download and install Cloud SQL Proxy:"
echo "   curl -o cloud-sql-proxy https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.14.0/cloud-sql-proxy.linux.amd64"
echo "   chmod +x cloud-sql-proxy"
echo ""
echo "2. Start the proxy:"
echo "   ./cloud-sql-proxy $CONNECTION_NAME"
echo ""
echo "3. In another terminal, connect to database:"
echo "   psql 'host=localhost port=5432 dbname=genspark_production user=genspark_app sslmode=disable'"

# Option 2: Direct connection
echo ""
echo "Option 2: Direct Connection"
echo "----------------------------------------"
echo "Connect directly using:"
echo "psql 'host=$IP_ADDRESS port=5432 dbname=genspark_production user=genspark_app sslmode=require'"

# Option 3: gcloud sql connect
echo ""
echo "Option 3: Using gcloud sql connect"
echo "----------------------------------------"
echo "gcloud sql connect genspark-db --user=genspark_app --database=genspark_production"

echo ""
echo "========================================="
echo "Database Schema Setup Commands"
echo "========================================="
echo "After connecting to the database, run:"
echo ""
echo "1. Setup schema:"
echo "   \\i database-schema.sql"
echo ""
echo "2. Load seed data:"
echo "   \\i database-seed.sql"
echo ""
echo "3. Verify tables:"
echo "   \\dt"
echo ""
echo "4. Check sample data:"
echo "   SELECT count(*) FROM organizations;"
echo "   SELECT count(*) FROM users;"
echo "   SELECT count(*) FROM contacts;"

echo ""
echo "Password for genspark_app user can be found in:"
echo "~/genspark-credentials.txt"