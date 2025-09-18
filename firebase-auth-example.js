/*
 * GenSpark AI - Firebase Authentication Examples
 * Client-side authentication examples for different providers
 */

import { 
  auth 
} from './firebase-config-template.js';
import { 
  signInWithEmailAndPassword,
  createUserWithEmailAndPassword,
  signInWithPopup,
  GoogleAuthProvider,
  RecaptchaVerifier,
  signInWithPhoneNumber,
  signInAnonymously,
  signOut,
  onAuthStateChanged,
  updateProfile
} from 'firebase/auth';

/**
 * Email/Password Authentication
 */
export const emailAuth = {
  // Sign up with email and password
  async signUp(email, password, displayName) {
    try {
      const userCredential = await createUserWithEmailAndPassword(auth, email, password);
      
      // Update user profile with display name
      if (displayName) {
        await updateProfile(userCredential.user, {
          displayName: displayName
        });
      }
      
      return {
        success: true,
        user: userCredential.user,
        token: await userCredential.user.getIdToken()
      };
    } catch (error) {
      console.error('Email sign up error:', error);
      return {
        success: false,
        error: error.message
      };
    }
  },

  // Sign in with email and password
  async signIn(email, password) {
    try {
      const userCredential = await signInWithEmailAndPassword(auth, email, password);
      return {
        success: true,
        user: userCredential.user,
        token: await userCredential.user.getIdToken()
      };
    } catch (error) {
      console.error('Email sign in error:', error);
      return {
        success: false,
        error: error.message
      };
    }
  }
};

/**
 * Google OAuth Authentication
 */
export const googleAuth = {
  async signIn() {
    try {
      const provider = new GoogleAuthProvider();
      provider.addScope('email');
      provider.addScope('profile');
      
      const result = await signInWithPopup(auth, provider);
      const credential = GoogleAuthProvider.credentialFromResult(result);
      
      return {
        success: true,
        user: result.user,
        token: await result.user.getIdToken(),
        accessToken: credential.accessToken
      };
    } catch (error) {
      console.error('Google sign in error:', error);
      return {
        success: false,
        error: error.message
      };
    }
  }
};

/**
 * Phone Authentication
 */
export const phoneAuth = {
  // Initialize reCAPTCHA verifier
  initRecaptcha(containerId = 'recaptcha-container') {
    if (!window.recaptchaVerifier) {
      window.recaptchaVerifier = new RecaptchaVerifier(auth, containerId, {
        'size': 'normal',
        'callback': (response) => {
          console.log('reCAPTCHA solved');
        },
        'expired-callback': () => {
          console.log('reCAPTCHA expired');
        }
      });
    }
    return window.recaptchaVerifier;
  },

  // Send SMS verification code
  async sendCode(phoneNumber, recaptchaVerifier) {
    try {
      const confirmationResult = await signInWithPhoneNumber(auth, phoneNumber, recaptchaVerifier);
      return {
        success: true,
        confirmationResult: confirmationResult,
        message: 'SMS verification code sent'
      };
    } catch (error) {
      console.error('Phone auth error:', error);
      return {
        success: false,
        error: error.message
      };
    }
  },

  // Verify SMS code
  async verifyCode(confirmationResult, code) {
    try {
      const result = await confirmationResult.confirm(code);
      return {
        success: true,
        user: result.user,
        token: await result.user.getIdToken()
      };
    } catch (error) {
      console.error('Phone verification error:', error);
      return {
        success: false,
        error: error.message
      };
    }
  }
};

/**
 * Anonymous Authentication
 */
export const anonymousAuth = {
  async signIn() {
    try {
      const userCredential = await signInAnonymously(auth);
      return {
        success: true,
        user: userCredential.user,
        token: await userCredential.user.getIdToken(),
        isAnonymous: true
      };
    } catch (error) {
      console.error('Anonymous sign in error:', error);
      return {
        success: false,
        error: error.message
      };
    }
  }
};

/**
 * General Authentication Functions
 */
export const authUtils = {
  // Sign out current user
  async signOut() {
    try {
      await signOut(auth);
      return {
        success: true,
        message: 'User signed out successfully'
      };
    } catch (error) {
      console.error('Sign out error:', error);
      return {
        success: false,
        error: error.message
      };
    }
  },

  // Get current user
  getCurrentUser() {
    return auth.currentUser;
  },

  // Listen to authentication state changes
  onAuthStateChanged(callback) {
    return onAuthStateChanged(auth, callback);
  },

  // Get current user ID token
  async getCurrentUserToken() {
    const user = auth.currentUser;
    if (user) {
      return await user.getIdToken();
    }
    return null;
  },

  // Check if user is authenticated
  isAuthenticated() {
    return !!auth.currentUser;
  },

  // Get user claims
  async getUserClaims() {
    const user = auth.currentUser;
    if (user) {
      const idTokenResult = await user.getIdTokenResult();
      return idTokenResult.claims;
    }
    return null;
  }
};

/**
 * Complete Authentication Flow Example
 */
export const authFlow = {
  async handleUserRegistration(email, password, displayName, organizationData) {
    try {
      // 1. Create Firebase user
      const authResult = await emailAuth.signUp(email, password, displayName);
      
      if (!authResult.success) {
        return authResult;
      }

      // 2. Create user in database
      const response = await fetch('/api/auth/register', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${authResult.token}`
        },
        body: JSON.stringify({
          displayName,
          organizationData
        })
      });

      const result = await response.json();
      
      if (!result.success) {
        // If database creation fails, delete Firebase user
        await authResult.user.delete();
        return result;
      }

      return {
        success: true,
        user: authResult.user,
        token: authResult.token,
        userData: result.user
      };
    } catch (error) {
      console.error('User registration flow error:', error);
      return {
        success: false,
        error: error.message
      };
    }
  },

  async handleUserLogin(email, password) {
    try {
      // 1. Authenticate with Firebase
      const authResult = await emailAuth.signIn(email, password);
      
      if (!authResult.success) {
        return authResult;
      }

      // 2. Create application session
      const response = await fetch('/api/auth/session', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${authResult.token}`
        }
      });

      const sessionResult = await response.json();
      
      if (!sessionResult.success) {
        return sessionResult;
      }

      // Store session token
      localStorage.setItem('sessionToken', sessionResult.sessionToken);

      return {
        success: true,
        user: authResult.user,
        token: authResult.token,
        sessionToken: sessionResult.sessionToken,
        userData: sessionResult.user
      };
    } catch (error) {
      console.error('User login flow error:', error);
      return {
        success: false,
        error: error.message
      };
    }
  }
};

// Export all authentication modules
export default {
  emailAuth,
  googleAuth,
  phoneAuth,
  anonymousAuth,
  authUtils,
  authFlow
};