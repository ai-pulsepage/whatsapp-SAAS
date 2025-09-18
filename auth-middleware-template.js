/*
 * GenSpark AI - Authentication Middleware
 * Express.js middleware for Firebase token verification and user session management
 */

import { verifyFirebaseToken, getFirebaseUser } from './firebase-admin-template.js';
import jwt from 'jsonwebtoken';

// Database connection (replace with your actual database connection)
// import { pool } from './database-connection.js';

/**
 * Firebase Authentication Middleware
 * Verifies Firebase ID token and loads user information
 */
export const authenticateFirebase = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({
        success: false,
        error: 'No authorization token provided'
      });
    }
    
    const idToken = authHeader.split('Bearer ')[1];
    const verificationResult = await verifyFirebaseToken(idToken);
    
    if (!verificationResult.success) {
      return res.status(401).json({
        success: false,
        error: 'Invalid authentication token'
      });
    }
    
    // Load user from database using Firebase UID
    const user = await getUserByFirebaseUid(verificationResult.user.uid);
    
    if (!user) {
      return res.status(401).json({
        success: false,
        error: 'User not found in database'
      });
    }
    
    // Attach user information to request
    req.user = user;
    req.firebaseUser = verificationResult.user;
    
    next();
  } catch (error) {
    console.error('Authentication middleware error:', error);
    return res.status(500).json({
      success: false,
      error: 'Authentication failed'
    });
  }
};

/**
 * JWT Session Middleware
 * Creates and manages JWT sessions for authenticated users
 */
export const createUserSession = async (req, res, next) => {
  try {
    const { user } = req;
    
    // Generate JWT token with user information
    const sessionToken = jwt.sign(
      {
        userId: user.id,
        organizationId: user.organization_id,
        role: user.role,
        email: user.email
      },
      process.env.JWT_SECRET,
      { 
        expiresIn: process.env.SESSION_TIMEOUT || '24h',
        issuer: 'genspark-ai',
        audience: 'genspark-users'
      }
    );
    
    // Store session in database
    const sessionData = {
      user_id: user.id,
      token_hash: hashToken(sessionToken),
      device_info: {
        userAgent: req.headers['user-agent'],
        ip: req.ip,
        timestamp: new Date()
      },
      ip_address: req.ip,
      expires_at: new Date(Date.now() + 24 * 60 * 60 * 1000) // 24 hours
    };
    
    await createUserSessionRecord(sessionData);
    
    // Attach session token to response
    res.locals.sessionToken = sessionToken;
    
    next();
  } catch (error) {
    console.error('Session creation error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to create user session'
    });
  }
};

/**
 * Role-based Authorization Middleware
 * Checks user role permissions
 */
export const requireRole = (requiredRoles) => {
  return (req, res, next) => {
    const { user } = req;
    
    if (!user || !user.role) {
      return res.status(403).json({
        success: false,
        error: 'Access denied: No role assigned'
      });
    }
    
    const userRoles = Array.isArray(user.role) ? user.role : [user.role];
    const hasRequiredRole = requiredRoles.some(role => userRoles.includes(role));
    
    if (!hasRequiredRole) {
      return res.status(403).json({
        success: false,
        error: `Access denied: Requires role(s): ${requiredRoles.join(', ')}`
      });
    }
    
    next();
  };
};

/**
 * Organization Access Control
 * Ensures user can only access their organization's data
 */
export const requireOrganizationAccess = (req, res, next) => {
  const { user } = req;
  const requestedOrgId = req.params.organizationId || req.body.organizationId || req.query.organizationId;
  
  if (requestedOrgId && requestedOrgId !== user.organization_id) {
    return res.status(403).json({
      success: false,
      error: 'Access denied: Cannot access other organization data'
    });
  }
  
  next();
};

/**
 * Session Validation Middleware
 * Validates JWT session token
 */
export const validateSession = async (req, res, next) => {
  try {
    const sessionToken = req.headers['x-session-token'];
    
    if (!sessionToken) {
      return res.status(401).json({
        success: false,
        error: 'No session token provided'
      });
    }
    
    const decoded = jwt.verify(sessionToken, process.env.JWT_SECRET);
    const sessionRecord = await getUserSession(decoded.userId, hashToken(sessionToken));
    
    if (!sessionRecord || new Date() > new Date(sessionRecord.expires_at)) {
      return res.status(401).json({
        success: false,
        error: 'Session expired or invalid'
      });
    }
    
    // Load current user data
    const user = await getUserById(decoded.userId);
    req.user = user;
    req.session = sessionRecord;
    
    next();
  } catch (error) {
    console.error('Session validation error:', error);
    return res.status(401).json({
      success: false,
      error: 'Invalid session token'
    });
  }
};

// Helper functions (replace with actual database queries)
const getUserByFirebaseUid = async (firebaseUid) => {
  // Implement database query to get user by Firebase UID
  // Example: SELECT * FROM users WHERE firebase_uid = $1
  return null; // Replace with actual implementation
};

const getUserById = async (userId) => {
  // Implement database query to get user by ID
  // Example: SELECT * FROM users WHERE id = $1
  return null; // Replace with actual implementation
};

const createUserSessionRecord = async (sessionData) => {
  // Implement database insert for user session
  // Example: INSERT INTO user_sessions (user_id, token_hash, device_info, ip_address, expires_at) VALUES (...)
  return null; // Replace with actual implementation
};

const getUserSession = async (userId, tokenHash) => {
  // Implement database query for user session
  // Example: SELECT * FROM user_sessions WHERE user_id = $1 AND token_hash = $2
  return null; // Replace with actual implementation
};

const hashToken = (token) => {
  // Implement token hashing (e.g., using crypto.createHash)
  const crypto = require('crypto');
  return crypto.createHash('sha256').update(token).digest('hex');
};

// Export middleware functions
export const authMiddleware = {
  authenticateFirebase,
  createUserSession,
  requireRole,
  requireOrganizationAccess,
  validateSession
};