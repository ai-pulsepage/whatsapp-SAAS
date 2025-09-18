#!/bin/bash

# GenSpark AI - Redis Setup Script
# Phase 4: Redis Memorystore Setup

# Load environment variables
source .env

echo "========================================="
echo "GenSpark AI - Redis Memorystore Setup"
echo "Project ID: $PROJECT_ID"
echo "Region: $REGION"
echo "========================================="

# Step 1: Create Redis instance
echo "Step 1: Creating Redis Memorystore instance..."
gcloud redis instances create genspark-cache \
  --size=1 \
  --region=$REGION \
  --redis-version=redis_7_0 \
  --enable-auth

echo "Redis instance creation initiated. This may take several minutes..."

# Wait for instance to be ready
echo "Waiting for Redis instance to be ready..."
gcloud redis instances describe genspark-cache --region=$REGION --format="value(state)"

while [ "$(gcloud redis instances describe genspark-cache --region=$REGION --format='value(state)')" != "READY" ]; do
    echo "Redis instance is still being created. Waiting 30 seconds..."
    sleep 30
done

echo "Redis instance is ready!"

# Step 2: Get connection details
echo ""
echo "Step 2: Getting Redis connection details..."
REDIS_HOST=$(gcloud redis instances describe genspark-cache --region=$REGION --format="value(host)")
REDIS_PORT=$(gcloud redis instances describe genspark-cache --region=$REGION --format="value(port)")
REDIS_AUTH=$(gcloud redis instances describe genspark-cache --region=$REGION --format="value(authString)")

echo "Redis Host: $REDIS_HOST"
echo "Redis Port: $REDIS_PORT"
echo "Redis Auth String: $REDIS_AUTH"

# Step 3: Save connection details to credentials file
echo ""
echo "Step 3: Saving Redis connection details..."
echo "" >> ~/genspark-credentials.txt
echo "Redis Memorystore Connection Details:" >> ~/genspark-credentials.txt
echo "Host: $REDIS_HOST" >> ~/genspark-credentials.txt
echo "Port: $REDIS_PORT" >> ~/genspark-credentials.txt
echo "Auth String: $REDIS_AUTH" >> ~/genspark-credentials.txt
echo "Connection URL: redis://:$REDIS_AUTH@$REDIS_HOST:$REDIS_PORT" >> ~/genspark-credentials.txt

# Step 4: Test Redis connection (basic connectivity test)
echo ""
echo "Step 4: Testing Redis connectivity..."
echo "Testing basic Redis commands..."

# Create a simple test script
cat > test-redis-connection.js << EOF
const Redis = require('ioredis');

const redis = new Redis({
  host: '$REDIS_HOST',
  port: $REDIS_PORT,
  password: '$REDIS_AUTH',
  retryDelayOnFailover: 100,
  maxRetriesPerRequest: 3,
});

redis.ping()
  .then((result) => {
    console.log('Redis PING successful:', result);
    return redis.set('test_key', 'GenSpark AI Test');
  })
  .then(() => {
    return redis.get('test_key');
  })
  .then((value) => {
    console.log('Redis GET successful:', value);
    return redis.del('test_key');
  })
  .then(() => {
    console.log('Redis connection test completed successfully!');
    redis.disconnect();
    process.exit(0);
  })
  .catch((error) => {
    console.error('Redis connection test failed:', error);
    redis.disconnect();
    process.exit(1);
  });
EOF

# Install ioredis if not already installed (for testing)
if [ ! -d "node_modules/ioredis" ]; then
    echo "Installing ioredis for connection test..."
    npm init -y > /dev/null 2>&1
    npm install ioredis > /dev/null 2>&1
fi

# Run the test
echo "Running Redis connection test..."
node test-redis-connection.js

# Clean up test file
rm -f test-redis-connection.js

echo ""
echo "========================================="
echo "Redis Memorystore Setup Complete!"
echo "========================================="
echo ""
echo "Connection details saved to ~/genspark-credentials.txt"
echo ""
echo "Redis instance information:"
echo "  Instance Name: genspark-cache"
echo "  Host: $REDIS_HOST"
echo "  Port: $REDIS_PORT"
echo "  Version: Redis 7.0"
echo "  Size: 1GB"
echo "  Region: $REGION"
echo ""
echo "To connect from your application:"
echo "  Host: $REDIS_HOST"
echo "  Port: $REDIS_PORT"
echo "  Password: [See credentials file]"
echo ""
echo "Next: Proceed to Phase 5 - Application Structure"
echo "========================================="