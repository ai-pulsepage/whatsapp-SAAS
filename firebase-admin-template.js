/*
 * GenSpark AI - Firebase Admin SDK Configuration
 * Server-side Firebase configuration for authentication verification
 */

import admin from 'firebase-admin';

// Initialize Firebase Admin SDK
const initializeFirebaseAdmin = () => {
  if (admin.apps.length === 0) {
    const serviceAccount = JSON.parse(process.env.FIREBASE_ADMIN_KEY);
    
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID,
    });
  }
  
  return admin;
};

// Verify Firebase ID token
export const verifyFirebaseToken = async (idToken) => {
  try {
    const firebaseAdmin = initializeFirebaseAdmin();
    const decodedToken = await firebaseAdmin.auth().verifyIdToken(idToken);
    return {
      success: true,
      user: {
        uid: decodedToken.uid,
        email: decodedToken.email,
        emailVerified: decodedToken.email_verified,
        name: decodedToken.name,
        picture: decodedToken.picture,
        phoneNumber: decodedToken.phone_number,
      }
    };
  } catch (error) {
    console.error('Error verifying Firebase token:', error);
    return {
      success: false,
      error: error.message
    };
  }
};

// Get user by UID
export const getFirebaseUser = async (uid) => {
  try {
    const firebaseAdmin = initializeFirebaseAdmin();
    const userRecord = await firebaseAdmin.auth().getUser(uid);
    return {
      success: true,
      user: {
        uid: userRecord.uid,
        email: userRecord.email,
        emailVerified: userRecord.emailVerified,
        disabled: userRecord.disabled,
        metadata: userRecord.metadata,
        providerData: userRecord.providerData,
      }
    };
  } catch (error) {
    console.error('Error getting Firebase user:', error);
    return {
      success: false,
      error: error.message
    };
  }
};

// Create custom token
export const createCustomToken = async (uid, claims = {}) => {
  try {
    const firebaseAdmin = initializeFirebaseAdmin();
    const customToken = await firebaseAdmin.auth().createCustomToken(uid, claims);
    return {
      success: true,
      token: customToken
    };
  } catch (error) {
    console.error('Error creating custom token:', error);
    return {
      success: false,
      error: error.message
    };
  }
};

// Set custom user claims
export const setCustomUserClaims = async (uid, claims) => {
  try {
    const firebaseAdmin = initializeFirebaseAdmin();
    await firebaseAdmin.auth().setCustomUserClaims(uid, claims);
    return {
      success: true
    };
  } catch (error) {
    console.error('Error setting custom claims:', error);
    return {
      success: false,
      error: error.message
    };
  }
};

export default initializeFirebaseAdmin;