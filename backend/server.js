/*
 * GenSpark AI - Main Server Entry Point
 * WhatsApp Business Automation Platform Backend
 */

require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const rateLimit = require('express-rate-limit');
const morgan = require('morgan');
const { createServer } = require('http');
const { Server } = require('socket.io');

// Import custom modules
const logger = require('./utils/logger');
const { connectDatabase } = require('./config/database');
const { connectRedis } = require('./config/redis');
const { initializeFirebase } = require('./config/firebase');
const errorHandler = require('./middleware/errorHandler');
const authMiddleware = require('./middleware/auth');

// Import routes
const authRoutes = require('./routes/auth');
const userRoutes = require('./routes/users');
const organizationRoutes = require('./routes/organizations');
const whatsappRoutes = require('./routes/whatsapp');
const contactRoutes = require('./routes/contacts');
const automationRoutes = require('./routes/automation');
const messageRoutes = require('./routes/messages');
const analyticsRoutes = require('./routes/analytics');
const webhookRoutes = require('./routes/webhooks');
const healthRoutes = require('./routes/health');

// Initialize Express app
const app = express();
const server = createServer(app);
const io = new Server(server, {
  cors: {
    origin: process.env.FRONTEND_URL || "http://localhost:3000",
    credentials: true
  }
});

// Store io instance globally for use in routes
app.set('io', io);

// Port configuration
const PORT = process.env.PORT || 8080;

// Trust proxy for Cloud Run
app.set('trust proxy', 1);

// Security middleware
app.use(helmet({
  contentSecurityPolicy: false, // Disable CSP for API server
  crossOriginEmbedderPolicy: false
}));

// CORS configuration
app.use(cors({
  origin: [
    process.env.FRONTEND_URL || 'http://localhost:3000',
    process.env.ADMIN_URL || 'http://localhost:3001',
    /\.genspark\.ai$/,
    /\.pages\.dev$/
  ],
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'x-session-token']
}));

// Compression middleware
app.use(compression());

// Request logging
if (process.env.NODE_ENV !== 'test') {
  app.use(morgan('combined', { stream: { write: message => logger.info(message.trim()) } }));
}

// Body parsing middleware
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// Rate limiting
const limiter = rateLimit({
  windowMs: parseInt(process.env.RATE_LIMIT_WINDOW) || 15 * 60 * 1000, // 15 minutes
  max: parseInt(process.env.RATE_LIMIT_MAX) || 1000, // limit each IP to 1000 requests per windowMs
  message: {
    error: 'Too many requests from this IP, please try again later'
  },
  standardHeaders: true,
  legacyHeaders: false,
});
app.use(limiter);

// Health check endpoint (unauthenticated)
app.use('/health', healthRoutes);

// API routes with authentication
app.use('/api/auth', authRoutes);
app.use('/api/users', authMiddleware.authenticateToken, userRoutes);
app.use('/api/organizations', authMiddleware.authenticateToken, organizationRoutes);
app.use('/api/whatsapp', authMiddleware.authenticateToken, whatsappRoutes);
app.use('/api/contacts', authMiddleware.authenticateToken, contactRoutes);
app.use('/api/automation', authMiddleware.authenticateToken, automationRoutes);
app.use('/api/messages', authMiddleware.authenticateToken, messageRoutes);
app.use('/api/analytics', authMiddleware.authenticateToken, analyticsRoutes);

// Webhook endpoints (no authentication required)
app.use('/webhooks', webhookRoutes);

// Socket.IO connection handling
io.on('connection', (socket) => {
  logger.info(`Socket connected: ${socket.id}`);
  
  socket.on('join_organization', (organizationId) => {
    socket.join(`org:${organizationId}`);
    logger.info(`Socket ${socket.id} joined organization: ${organizationId}`);
  });
  
  socket.on('disconnect', () => {
    logger.info(`Socket disconnected: ${socket.id}`);
  });
});

// Error handling middleware (must be last)
app.use(errorHandler);

// 404 handler
app.use('*', (req, res) => {
  res.status(404).json({
    success: false,
    error: 'Route not found'
  });
});

// Graceful shutdown handler
process.on('SIGINT', gracefulShutdown);
process.on('SIGTERM', gracefulShutdown);

function gracefulShutdown(signal) {
  logger.info(`Received ${signal}. Starting graceful shutdown...`);
  
  server.close((err) => {
    if (err) {
      logger.error('Error during server shutdown:', err);
      process.exit(1);
    }
    
    logger.info('HTTP server closed');
    process.exit(0);
  });
  
  // Force close after 30 seconds
  setTimeout(() => {
    logger.error('Could not close connections in time, forcefully shutting down');
    process.exit(1);
  }, 30000);
}

// Initialize services and start server
async function startServer() {
  try {
    logger.info('Starting GenSpark AI Backend Server...');
    
    // Initialize Firebase Admin SDK
    await initializeFirebase();
    logger.info('Firebase initialized successfully');
    
    // Connect to PostgreSQL database
    await connectDatabase();
    logger.info('Database connected successfully');
    
    // Connect to Redis
    await connectRedis();
    logger.info('Redis connected successfully');
    
    // Start server
    server.listen(PORT, '0.0.0.0', () => {
      logger.info(`GenSpark AI Backend Server is running on port ${PORT}`);
      logger.info(`Environment: ${process.env.NODE_ENV}`);
      logger.info(`Process ID: ${process.pid}`);
    });
    
  } catch (error) {
    logger.error('Failed to start server:', error);
    process.exit(1);
  }
}

// Start the server
if (require.main === module) {
  startServer();
}

module.exports = { app, server, io };