-- GenSpark AI - Database Schema Setup
-- WhatsApp Business Automation Platform
-- PostgreSQL 15 Schema

-- Connect to genspark_production database first
-- psql "host=YOUR_INSTANCE_IP port=5432 dbname=genspark_production user=genspark_app password=YOUR_PASSWORD sslmode=require"

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "unaccent";

-- Set timezone
SET timezone = 'America/Mexico_City';

-- Drop tables if they exist (for development only)
DROP TABLE IF EXISTS message_logs CASCADE;
DROP TABLE IF EXISTS automation_rules CASCADE;
DROP TABLE IF EXISTS bot_conversations CASCADE;
DROP TABLE IF EXISTS contact_groups CASCADE;
DROP TABLE IF EXISTS contacts CASCADE;
DROP TABLE IF EXISTS whatsapp_accounts CASCADE;
DROP TABLE IF EXISTS user_sessions CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS organizations CASCADE;

-- Organizations table
CREATE TABLE organizations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    domain VARCHAR(255) UNIQUE,
    subscription_plan VARCHAR(50) DEFAULT 'free',
    subscription_status VARCHAR(50) DEFAULT 'active',
    max_users INTEGER DEFAULT 5,
    max_contacts INTEGER DEFAULT 1000,
    max_monthly_messages INTEGER DEFAULT 1000,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Users table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    email VARCHAR(255) UNIQUE NOT NULL,
    firebase_uid VARCHAR(255) UNIQUE NOT NULL,
    first_name VARCHAR(255) NOT NULL,
    last_name VARCHAR(255),
    role VARCHAR(50) DEFAULT 'user', -- 'admin', 'manager', 'user'
    status VARCHAR(50) DEFAULT 'active', -- 'active', 'inactive', 'suspended'
    last_login_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- User sessions table (for JWT token management)
CREATE TABLE user_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL,
    device_info JSONB,
    ip_address INET,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- WhatsApp Business Accounts table
CREATE TABLE whatsapp_accounts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    business_account_id VARCHAR(255) NOT NULL,
    phone_number_id VARCHAR(255) NOT NULL,
    phone_number VARCHAR(20) NOT NULL,
    display_name VARCHAR(255),
    access_token TEXT NOT NULL, -- Encrypted
    webhook_verify_token VARCHAR(255) NOT NULL,
    status VARCHAR(50) DEFAULT 'active', -- 'active', 'inactive', 'suspended'
    webhook_url TEXT,
    last_webhook_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Contacts table
CREATE TABLE contacts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    whatsapp_account_id UUID REFERENCES whatsapp_accounts(id) ON DELETE CASCADE,
    phone_number VARCHAR(20) NOT NULL,
    name VARCHAR(255),
    profile_name VARCHAR(255),
    language_code VARCHAR(10) DEFAULT 'es',
    timezone VARCHAR(50) DEFAULT 'America/Mexico_City',
    tags TEXT[], -- Array of tags
    custom_fields JSONB DEFAULT '{}',
    last_message_at TIMESTAMP WITH TIME ZONE,
    is_blocked BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(organization_id, phone_number)
);

-- Contact Groups table
CREATE TABLE contact_groups (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    color VARCHAR(7), -- Hex color code
    contact_ids UUID[], -- Array of contact IDs
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Bot Conversations table
CREATE TABLE bot_conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    whatsapp_account_id UUID REFERENCES whatsapp_accounts(id) ON DELETE CASCADE,
    contact_id UUID REFERENCES contacts(id) ON DELETE CASCADE,
    conversation_state VARCHAR(50) DEFAULT 'active', -- 'active', 'paused', 'completed'
    current_flow VARCHAR(255), -- Current automation flow
    flow_step INTEGER DEFAULT 0,
    context_data JSONB DEFAULT '{}', -- Store conversation context
    ai_personality VARCHAR(255) DEFAULT 'professional', -- AI personality type
    language VARCHAR(10) DEFAULT 'es',
    last_activity_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Automation Rules table
CREATE TABLE automation_rules (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    whatsapp_account_id UUID REFERENCES whatsapp_accounts(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    trigger_type VARCHAR(50) NOT NULL, -- 'keyword', 'new_contact', 'time_based', 'webhook'
    trigger_conditions JSONB NOT NULL, -- Conditions for rule activation
    actions JSONB NOT NULL, -- Actions to perform when triggered
    is_active BOOLEAN DEFAULT TRUE,
    priority INTEGER DEFAULT 0, -- Higher priority rules execute first
    execution_count INTEGER DEFAULT 0,
    last_executed_at TIMESTAMP WITH TIME ZONE,
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Message Logs table
CREATE TABLE message_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    whatsapp_account_id UUID REFERENCES whatsapp_accounts(id) ON DELETE CASCADE,
    contact_id UUID REFERENCES contacts(id) ON DELETE CASCADE,
    message_id VARCHAR(255), -- WhatsApp message ID
    direction VARCHAR(10) NOT NULL, -- 'inbound', 'outbound'
    message_type VARCHAR(50) NOT NULL, -- 'text', 'image', 'audio', 'video', 'document'
    content JSONB NOT NULL, -- Message content and metadata
    status VARCHAR(50) DEFAULT 'pending', -- 'pending', 'sent', 'delivered', 'read', 'failed'
    automation_rule_id UUID REFERENCES automation_rules(id), -- If sent by automation
    error_message TEXT,
    webhook_data JSONB, -- Original webhook data
    processed_by VARCHAR(50), -- 'user', 'bot', 'automation'
    processing_time_ms INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for better performance
CREATE INDEX idx_users_organization_id ON users(organization_id);
CREATE INDEX idx_users_firebase_uid ON users(firebase_uid);
CREATE INDEX idx_users_email ON users(email);

CREATE INDEX idx_user_sessions_user_id ON user_sessions(user_id);
CREATE INDEX idx_user_sessions_expires_at ON user_sessions(expires_at);

CREATE INDEX idx_whatsapp_accounts_organization_id ON whatsapp_accounts(organization_id);
CREATE INDEX idx_whatsapp_accounts_business_account_id ON whatsapp_accounts(business_account_id);
CREATE INDEX idx_whatsapp_accounts_phone_number_id ON whatsapp_accounts(phone_number_id);

CREATE INDEX idx_contacts_organization_id ON contacts(organization_id);
CREATE INDEX idx_contacts_whatsapp_account_id ON contacts(whatsapp_account_id);
CREATE INDEX idx_contacts_phone_number ON contacts(phone_number);
CREATE INDEX idx_contacts_last_message_at ON contacts(last_message_at);

CREATE INDEX idx_contact_groups_organization_id ON contact_groups(organization_id);

CREATE INDEX idx_bot_conversations_organization_id ON bot_conversations(organization_id);
CREATE INDEX idx_bot_conversations_contact_id ON bot_conversations(contact_id);
CREATE INDEX idx_bot_conversations_conversation_state ON bot_conversations(conversation_state);

CREATE INDEX idx_automation_rules_organization_id ON automation_rules(organization_id);
CREATE INDEX idx_automation_rules_trigger_type ON automation_rules(trigger_type);
CREATE INDEX idx_automation_rules_is_active ON automation_rules(is_active);
CREATE INDEX idx_automation_rules_priority ON automation_rules(priority);

CREATE INDEX idx_message_logs_organization_id ON message_logs(organization_id);
CREATE INDEX idx_message_logs_contact_id ON message_logs(contact_id);
CREATE INDEX idx_message_logs_direction ON message_logs(direction);
CREATE INDEX idx_message_logs_message_type ON message_logs(message_type);
CREATE INDEX idx_message_logs_status ON message_logs(status);
CREATE INDEX idx_message_logs_created_at ON message_logs(created_at);
CREATE INDEX idx_message_logs_automation_rule_id ON message_logs(automation_rule_id);

-- Full text search indexes
CREATE INDEX idx_contacts_name_trgm ON contacts USING gin(name gin_trgm_ops);
CREATE INDEX idx_contacts_phone_trgm ON contacts USING gin(phone_number gin_trgm_ops);

-- Functions for updated_at timestamps
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create triggers for updated_at
CREATE TRIGGER update_organizations_updated_at BEFORE UPDATE ON organizations FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_whatsapp_accounts_updated_at BEFORE UPDATE ON whatsapp_accounts FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_contacts_updated_at BEFORE UPDATE ON contacts FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_contact_groups_updated_at BEFORE UPDATE ON contact_groups FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_bot_conversations_updated_at BEFORE UPDATE ON bot_conversations FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_automation_rules_updated_at BEFORE UPDATE ON automation_rules FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_message_logs_updated_at BEFORE UPDATE ON message_logs FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Initial data setup
INSERT INTO organizations (id, name, domain, subscription_plan) 
VALUES (uuid_generate_v4(), 'GenSpark AI Demo', 'demo.genspark.ai', 'premium');

COMMENT ON TABLE organizations IS 'Multi-tenant organizations for the SaaS platform';
COMMENT ON TABLE users IS 'Platform users with Firebase authentication integration';
COMMENT ON TABLE whatsapp_accounts IS 'WhatsApp Business API account configurations';
COMMENT ON TABLE contacts IS 'Customer contacts managed through WhatsApp';
COMMENT ON TABLE automation_rules IS 'AI-powered automation rules and workflows';
COMMENT ON TABLE message_logs IS 'Complete message history and analytics';
COMMENT ON TABLE bot_conversations IS 'AI conversation states and context management';

-- Grant permissions to application user
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO genspark_app;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO genspark_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO genspark_app;

COMMIT;