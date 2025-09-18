/*
 * GenSpark AI - Cloud Storage Utilities
 * Google Cloud Storage integration for file management
 */

const { Storage } = require('@google-cloud/storage');
const { SecretManagerServiceClient } = require('@google-cloud/secret-manager');
const sharp = require('sharp');
const path = require('path');
const crypto = require('crypto');

// Initialize Google Cloud Storage
const storage = new Storage({
  projectId: process.env.GOOGLE_CLOUD_PROJECT,
  keyFilename: process.env.GOOGLE_CLOUD_KEYFILE
});

// Initialize Secret Manager client
const secretManagerClient = new SecretManagerServiceClient();

// Storage bucket references
const mediaBucket = storage.bucket(`${process.env.GOOGLE_CLOUD_PROJECT}-media`);
const privateBucket = storage.bucket(`${process.env.GOOGLE_CLOUD_PROJECT}-private`);
const backupBucket = storage.bucket(`${process.env.GOOGLE_CLOUD_PROJECT}-backups`);

/**
 * Secret Manager Utilities
 */
const secretManager = {
  /**
   * Get secret value from Secret Manager
   */
  async getSecret(secretName, version = 'latest') {
    try {
      const name = `projects/${process.env.GOOGLE_CLOUD_PROJECT}/secrets/${secretName}/versions/${version}`;
      const [accessResponse] = await secretManagerClient.accessSecretVersion({ name });
      return accessResponse.payload.data.toString('utf8');
    } catch (error) {
      console.error(`Error accessing secret ${secretName}:`, error);
      throw new Error(`Failed to access secret: ${secretName}`);
    }
  },

  /**
   * Create or update a secret
   */
  async setSecret(secretName, secretValue) {
    try {
      const projectId = process.env.GOOGLE_CLOUD_PROJECT;
      
      // Try to create the secret first
      try {
        await secretManagerClient.createSecret({
          parent: `projects/${projectId}`,
          secretId: secretName,
          secret: {
            replication: { automatic: {} }
          }
        });
      } catch (err) {
        // Secret might already exist, continue to add version
        if (!err.message.includes('already exists')) {
          throw err;
        }
      }

      // Add secret version
      const [version] = await secretManagerClient.addSecretVersion({
        parent: `projects/${projectId}/secrets/${secretName}`,
        payload: {
          data: Buffer.from(secretValue, 'utf8')
        }
      });

      return version.name;
    } catch (error) {
      console.error(`Error setting secret ${secretName}:`, error);
      throw new Error(`Failed to set secret: ${secretName}`);
    }
  },

  /**
   * Get multiple secrets at once
   */
  async getSecrets(secretNames) {
    const secrets = {};
    
    for (const secretName of secretNames) {
      try {
        secrets[secretName] = await this.getSecret(secretName);
      } catch (error) {
        console.error(`Failed to get secret ${secretName}:`, error);
        secrets[secretName] = null;
      }
    }
    
    return secrets;
  }
};

/**
 * File Upload Utilities
 */
const fileUpload = {
  /**
   * Upload file to media bucket (public)
   */
  async uploadToMedia(file, destination, options = {}) {
    try {
      const fileName = destination || `${Date.now()}-${Math.random().toString(36).substring(7)}${path.extname(file.originalname)}`;
      const fileRef = mediaBucket.file(fileName);
      
      const stream = fileRef.createWriteStream({
        metadata: {
          contentType: file.mimetype,
          metadata: {
            uploadedBy: options.userId || 'system',
            organizationId: options.organizationId || null,
            originalName: file.originalname,
            uploadedAt: new Date().toISOString()
          }
        },
        resumable: false
      });

      return new Promise((resolve, reject) => {
        stream.on('error', reject);
        stream.on('finish', () => {
          const publicUrl = `https://storage.googleapis.com/${mediaBucket.name}/${fileName}`;
          resolve({
            fileName,
            publicUrl,
            bucket: mediaBucket.name,
            size: file.size,
            contentType: file.mimetype
          });
        });
        stream.end(file.buffer);
      });
    } catch (error) {
      console.error('Media upload error:', error);
      throw new Error('Failed to upload file to media bucket');
    }
  },

  /**
   * Upload file to private bucket (authenticated)
   */
  async uploadToPrivate(file, destination, options = {}) {
    try {
      const fileName = destination || `${Date.now()}-${Math.random().toString(36).substring(7)}${path.extname(file.originalname)}`;
      const fileRef = privateBucket.file(fileName);
      
      const stream = fileRef.createWriteStream({
        metadata: {
          contentType: file.mimetype,
          metadata: {
            uploadedBy: options.userId || 'system',
            organizationId: options.organizationId || null,
            originalName: file.originalname,
            uploadedAt: new Date().toISOString(),
            encrypted: options.encrypted || false
          }
        },
        resumable: false
      });

      return new Promise((resolve, reject) => {
        stream.on('error', reject);
        stream.on('finish', () => {
          resolve({
            fileName,
            bucket: privateBucket.name,
            size: file.size,
            contentType: file.mimetype,
            private: true
          });
        });
        stream.end(file.buffer);
      });
    } catch (error) {
      console.error('Private upload error:', error);
      throw new Error('Failed to upload file to private bucket');
    }
  },

  /**
   * Generate signed URL for private file access
   */
  async generateSignedUrl(fileName, bucketType = 'private', expiresInMinutes = 60) {
    try {
      const bucket = bucketType === 'private' ? privateBucket : mediaBucket;
      const file = bucket.file(fileName);
      
      const options = {
        version: 'v4',
        action: 'read',
        expires: Date.now() + expiresInMinutes * 60 * 1000
      };
      
      const [signedUrl] = await file.getSignedUrl(options);
      return signedUrl;
    } catch (error) {
      console.error('Signed URL generation error:', error);
      throw new Error('Failed to generate signed URL');
    }
  },

  /**
   * Delete file from storage
   */
  async deleteFile(fileName, bucketType = 'media') {
    try {
      const bucket = bucketType === 'private' ? privateBucket : mediaBucket;
      const file = bucket.file(fileName);
      
      await file.delete();
      return true;
    } catch (error) {
      console.error('File deletion error:', error);
      return false;
    }
  }
};

/**
 * Image Processing Utilities
 */
const imageProcessing = {
  /**
   * Resize and optimize image
   */
  async processImage(buffer, options = {}) {
    try {
      const {
        width = 800,
        height = 600,
        quality = 80,
        format = 'jpeg'
      } = options;
      
      let image = sharp(buffer);
      
      // Get image metadata
      const metadata = await image.metadata();
      
      // Resize if needed
      if (metadata.width > width || metadata.height > height) {
        image = image.resize(width, height, {
          fit: 'inside',
          withoutEnlargement: true
        });
      }
      
      // Convert and optimize
      switch (format.toLowerCase()) {
        case 'jpeg':
        case 'jpg':
          image = image.jpeg({ quality, progressive: true });
          break;
        case 'png':
          image = image.png({ compressionLevel: 9 });
          break;
        case 'webp':
          image = image.webp({ quality });
          break;
        default:
          image = image.jpeg({ quality, progressive: true });
      }
      
      const processedBuffer = await image.toBuffer();
      
      return {
        buffer: processedBuffer,
        size: processedBuffer.length,
        format: format.toLowerCase(),
        width: metadata.width,
        height: metadata.height
      };
    } catch (error) {
      console.error('Image processing error:', error);
      throw new Error('Failed to process image');
    }
  },

  /**
   * Generate image thumbnails
   */
  async generateThumbnails(buffer, sizes = [150, 300, 600]) {
    try {
      const thumbnails = {};
      
      for (const size of sizes) {
        const processed = await this.processImage(buffer, {
          width: size,
          height: size,
          quality: 85,
          format: 'jpeg'
        });
        
        thumbnails[size] = processed.buffer;
      }
      
      return thumbnails;
    } catch (error) {
      console.error('Thumbnail generation error:', error);
      throw new Error('Failed to generate thumbnails');
    }
  }
};

/**
 * Backup and Archive Utilities
 */
const backup = {
  /**
   * Create database backup
   */
  async backupDatabase(organizationId = null) {
    try {
      const timestamp = new Date().toISOString().slice(0, 10);
      const filename = organizationId 
        ? `database-backup-org-${organizationId}-${timestamp}.sql`
        : `database-backup-full-${timestamp}.sql`;
      
      // This would typically use pg_dump or similar
      // Implementation depends on your backup strategy
      console.log(`Creating database backup: ${filename}`);
      
      return {
        filename,
        bucket: backupBucket.name,
        timestamp: new Date().toISOString()
      };
    } catch (error) {
      console.error('Database backup error:', error);
      throw new Error('Failed to create database backup');
    }
  },

  /**
   * Archive old files
   */
  async archiveOldFiles(daysOld = 30) {
    try {
      const cutoffDate = new Date();
      cutoffDate.setDate(cutoffDate.getDate() - daysOld);
      
      const [mediaFiles] = await mediaBucket.getFiles({
        prefix: 'temp/',
        maxResults: 1000
      });
      
      let archivedCount = 0;
      
      for (const file of mediaFiles) {
        const [metadata] = await file.getMetadata();
        const createdDate = new Date(metadata.timeCreated);
        
        if (createdDate < cutoffDate) {
          // Move to archive folder
          const newName = `archive/${file.name}`;
          await file.move(newName);
          archivedCount++;
        }
      }
      
      return { archivedCount };
    } catch (error) {
      console.error('File archival error:', error);
      throw new Error('Failed to archive old files');
    }
  }
};

/**
 * Storage Health Check
 */
const healthCheck = {
  async checkStorageHealth() {
    try {
      const results = {
        media: false,
        private: false,
        backup: false,
        secretManager: false
      };
      
      // Test media bucket
      try {
        await mediaBucket.getMetadata();
        results.media = true;
      } catch (error) {
        console.error('Media bucket health check failed:', error);
      }
      
      // Test private bucket
      try {
        await privateBucket.getMetadata();
        results.private = true;
      } catch (error) {
        console.error('Private bucket health check failed:', error);
      }
      
      // Test backup bucket
      try {
        await backupBucket.getMetadata();
        results.backup = true;
      } catch (error) {
        console.error('Backup bucket health check failed:', error);
      }
      
      // Test Secret Manager
      try {
        await secretManager.getSecret('jwt-secret');
        results.secretManager = true;
      } catch (error) {
        console.error('Secret Manager health check failed:', error);
      }
      
      return {
        healthy: Object.values(results).every(result => result === true),
        components: results
      };
    } catch (error) {
      console.error('Storage health check error:', error);
      return {
        healthy: false,
        error: error.message
      };
    }
  }
};

// Export all utilities
module.exports = {
  secretManager,
  fileUpload,
  imageProcessing,
  backup,
  healthCheck,
  storage,
  mediaBucket,
  privateBucket,
  backupBucket
};