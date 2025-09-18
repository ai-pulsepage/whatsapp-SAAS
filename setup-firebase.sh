#!/bin/bash

# GenSpark AI - Firebase Setup Script
# Phase 3: Firebase Authentication Setup

# Load environment variables
source .env

echo "========================================="
echo "GenSpark AI - Firebase Setup"
echo "Project ID: $PROJECT_ID"
echo "========================================="

# Step 1: Login to Firebase (requires user interaction)
echo "Step 1: Login to Firebase..."
echo "Please run: firebase login"
echo "This will open a browser for authentication"

# Step 2: Create Firebase project
echo ""
echo "Step 2: Creating Firebase project..."
echo "Creating Firebase project with ID: $PROJECT_ID"
firebase projects:create $PROJECT_ID --display-name="GenSpark AI"

# Step 3: Use the Firebase project
echo ""
echo "Step 3: Setting Firebase project..."
firebase use $PROJECT_ID

# Step 4: Initialize Firebase Auth
echo ""
echo "Step 4: Initialize Firebase Authentication..."
firebase init auth --project $PROJECT_ID

echo ""
echo "========================================="
echo "Firebase CLI Setup Complete!"
echo "========================================="
echo ""
echo "Next steps (Manual configuration required):"
echo ""
echo "1. Go to Firebase Console: https://console.firebase.google.com/project/$PROJECT_ID"
echo ""
echo "2. Configure Authentication providers:"
echo "   - Go to Authentication > Sign-in method"
echo "   - Enable Email/Password"
echo "   - Enable Google (configure OAuth consent screen)"
echo "   - Enable Phone (for WhatsApp verification)"
echo "   - Enable Anonymous (for guest sessions)"
echo ""
echo "3. Get Firebase configuration:"
echo "   - Go to Project Settings"
echo "   - Add a web app"
echo "   - Copy the config object"
echo "   - Save to firebase-config.json"
echo ""
echo "4. Generate Admin SDK key:"
echo "   - Go to Project Settings > Service accounts"
echo "   - Click 'Generate new private key'"
echo "   - Save as firebase-admin-key.json"
echo ""
echo "========================================="