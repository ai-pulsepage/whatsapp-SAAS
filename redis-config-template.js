/*
 * GenSpark AI - Redis Configuration Template
 * Redis connection and utility functions for caching and session management
 */

import Redis from 'ioredis';

// Redis connection configuration
const redisConfig = {
  host: process.env.REDIS_HOST,
  port: process.env.REDIS_PORT || 6379,
  password: process.env.REDIS_AUTH_STRING,
  retryDelayOnFailover: 100,
  maxRetriesPerRequest: 3,
  connectTimeout: 10000,
  commandTimeout: 5000,
  lazyConnect: true,
  keepAlive: 30000,
  family: 4, // IPv4
  db: 0, // Default database
};

// Create Redis client instance
const redis = new Redis(redisConfig);

// Redis connection event handlers
redis.on('connect', () => {
  console.log('Redis connected successfully');
});

redis.on('ready', () => {
  console.log('Redis connection is ready for commands');
});

redis.on('error', (error) => {
  console.error('Redis connection error:', error);
});

redis.on('close', () => {
  console.log('Redis connection closed');
});

redis.on('reconnecting', () => {
  console.log('Redis reconnecting...');
});

redis.on('end', () => {
  console.log('Redis connection ended');
});

/**
 * Redis Cache Utilities
 */
export const cache = {
  /**
   * Set a value in Redis with optional TTL
   */
  async set(key, value, ttlSeconds = 3600) {
    try {
      const serializedValue = JSON.stringify(value);
      if (ttlSeconds) {
        await redis.setex(key, ttlSeconds, serializedValue);
      } else {
        await redis.set(key, serializedValue);
      }
      return true;
    } catch (error) {
      console.error('Redis SET error:', error);
      return false;
    }
  },

  /**
   * Get a value from Redis
   */
  async get(key) {
    try {
      const value = await redis.get(key);
      return value ? JSON.parse(value) : null;
    } catch (error) {
      console.error('Redis GET error:', error);
      return null;
    }
  },

  /**
   * Delete a key from Redis
   */
  async del(key) {
    try {
      const result = await redis.del(key);
      return result > 0;
    } catch (error) {
      console.error('Redis DEL error:', error);
      return false;
    }
  },

  /**
   * Check if key exists
   */
  async exists(key) {
    try {
      const result = await redis.exists(key);
      return result === 1;
    } catch (error) {
      console.error('Redis EXISTS error:', error);
      return false;
    }
  },

  /**
   * Set TTL for existing key
   */
  async expire(key, ttlSeconds) {
    try {
      const result = await redis.expire(key, ttlSeconds);
      return result === 1;
    } catch (error) {
      console.error('Redis EXPIRE error:', error);
      return false;
    }
  },

  /**
   * Get TTL of a key
   */
  async ttl(key) {
    try {
      return await redis.ttl(key);
    } catch (error) {
      console.error('Redis TTL error:', error);
      return -1;
    }
  }
};

/**
 * Session Management Utilities
 */
export const sessionStore = {
  /**
   * Store user session
   */
  async setSession(sessionId, sessionData, ttlSeconds = 86400) {
    const key = `session:${sessionId}`;
    return await cache.set(key, sessionData, ttlSeconds);
  },

  /**
   * Get user session
   */
  async getSession(sessionId) {
    const key = `session:${sessionId}`;
    return await cache.get(key);
  },

  /**
   * Delete user session
   */
  async deleteSession(sessionId) {
    const key = `session:${sessionId}`;
    return await cache.del(key);
  },

  /**
   * Extend session TTL
   */
  async extendSession(sessionId, ttlSeconds = 86400) {
    const key = `session:${sessionId}`;
    return await cache.expire(key, ttlSeconds);
  },

  /**
   * Get all sessions for a user
   */
  async getUserSessions(userId) {
    try {
      const pattern = `session:*`;
      const keys = await redis.keys(pattern);
      const sessions = [];
      
      for (const key of keys) {
        const sessionData = await cache.get(key);
        if (sessionData && sessionData.userId === userId) {
          sessions.push({
            sessionId: key.replace('session:', ''),
            ...sessionData
          });
        }
      }
      
      return sessions;
    } catch (error) {
      console.error('Error getting user sessions:', error);
      return [];
    }
  }
};

/**
 * Rate Limiting Utilities
 */
export const rateLimiter = {
  /**
   * Check and increment rate limit counter
   */
  async checkLimit(identifier, maxRequests = 100, windowSeconds = 3600) {
    try {
      const key = `ratelimit:${identifier}`;
      const currentCount = await redis.incr(key);
      
      if (currentCount === 1) {
        await redis.expire(key, windowSeconds);
      }
      
      const remaining = Math.max(0, maxRequests - currentCount);
      const ttl = await redis.ttl(key);
      
      return {
        allowed: currentCount <= maxRequests,
        count: currentCount,
        remaining,
        resetTime: ttl > 0 ? Date.now() + (ttl * 1000) : null
      };
    } catch (error) {
      console.error('Rate limiter error:', error);
      return { allowed: true, count: 0, remaining: maxRequests, resetTime: null };
    }
  },

  /**
   * Reset rate limit for identifier
   */
  async resetLimit(identifier) {
    const key = `ratelimit:${identifier}`;
    return await cache.del(key);
  }
};

/**
 * Queue Management Utilities
 */
export const queue = {
  /**
   * Add job to queue
   */
  async addJob(queueName, jobData, priority = 0) {
    try {
      const jobId = `job:${Date.now()}:${Math.random().toString(36).substring(7)}`;
      const job = {
        id: jobId,
        data: jobData,
        priority,
        createdAt: new Date().toISOString(),
        status: 'pending'
      };
      
      await redis.zadd(`queue:${queueName}`, priority, JSON.stringify(job));
      return jobId;
    } catch (error) {
      console.error('Queue add job error:', error);
      return null;
    }
  },

  /**
   * Get next job from queue
   */
  async getNextJob(queueName) {
    try {
      const result = await redis.zpopmax(`queue:${queueName}`);
      if (result.length === 0) return null;
      
      const job = JSON.parse(result[0]);
      return job;
    } catch (error) {
      console.error('Queue get job error:', error);
      return null;
    }
  },

  /**
   * Get queue length
   */
  async getQueueLength(queueName) {
    try {
      return await redis.zcard(`queue:${queueName}`);
    } catch (error) {
      console.error('Queue length error:', error);
      return 0;
    }
  }
};

/**
 * WhatsApp Message Queue Utilities
 */
export const messageQueue = {
  /**
   * Add WhatsApp message to send queue
   */
  async queueMessage(messageData) {
    return await queue.addJob('whatsapp_messages', messageData, messageData.priority || 0);
  },

  /**
   * Get next message to send
   */
  async getNextMessage() {
    return await queue.getNextJob('whatsapp_messages');
  },

  /**
   * Queue automation rule execution
   */
  async queueAutomation(automationData) {
    return await queue.addJob('automation_rules', automationData, automationData.priority || 0);
  },

  /**
   * Get next automation to execute
   */
  async getNextAutomation() {
    return await queue.getNextJob('automation_rules');
  }
};

/**
 * Conversation State Management
 */
export const conversationCache = {
  /**
   * Store conversation state
   */
  async setState(contactId, conversationData, ttlSeconds = 7200) {
    const key = `conversation:${contactId}`;
    return await cache.set(key, conversationData, ttlSeconds);
  },

  /**
   * Get conversation state
   */
  async getState(contactId) {
    const key = `conversation:${contactId}`;
    return await cache.get(key);
  },

  /**
   * Update conversation step
   */
  async updateStep(contactId, step, contextData = {}) {
    const key = `conversation:${contactId}`;
    const currentState = await cache.get(key) || {};
    
    const updatedState = {
      ...currentState,
      step,
      contextData: { ...currentState.contextData, ...contextData },
      updatedAt: new Date().toISOString()
    };
    
    return await cache.set(key, updatedState, 7200);
  },

  /**
   * Clear conversation state
   */
  async clearState(contactId) {
    const key = `conversation:${contactId}`;
    return await cache.del(key);
  }
};

/**
 * Health Check Utilities
 */
export const healthCheck = {
  /**
   * Check Redis connection health
   */
  async checkHealth() {
    try {
      const start = Date.now();
      await redis.ping();
      const responseTime = Date.now() - start;
      
      const info = await redis.info('memory');
      const memoryInfo = {};
      info.split('\r\n').forEach(line => {
        const [key, value] = line.split(':');
        if (key && value) {
          memoryInfo[key] = value;
        }
      });
      
      return {
        status: 'healthy',
        responseTime,
        memory: {
          used: memoryInfo.used_memory_human,
          peak: memoryInfo.used_memory_peak_human,
          fragmentation: parseFloat(memoryInfo.mem_fragmentation_ratio)
        }
      };
    } catch (error) {
      return {
        status: 'unhealthy',
        error: error.message
      };
    }
  }
};

// Export Redis client and utilities
export { redis };
export default {
  redis,
  cache,
  sessionStore,
  rateLimiter,
  queue,
  messageQueue,
  conversationCache,
  healthCheck
};