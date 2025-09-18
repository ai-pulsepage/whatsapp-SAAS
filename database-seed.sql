-- GenSpark AI - Database Seed Data
-- Sample data for testing and development

-- Insert sample organization
INSERT INTO organizations (id, name, domain, subscription_plan, max_users, max_contacts, max_monthly_messages) 
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'GenSpark Demo Organization', 
    'demo.genspark.ai', 
    'premium',
    50,
    10000,
    50000
) ON CONFLICT (id) DO NOTHING;

-- Insert sample admin user
INSERT INTO users (
    id, 
    organization_id, 
    email, 
    firebase_uid, 
    first_name, 
    last_name, 
    role, 
    status
) VALUES (
    '00000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000001',
    'admin@genspark.ai',
    'firebase_admin_uid_demo',
    'Admin',
    'User',
    'admin',
    'active'
) ON CONFLICT (id) DO NOTHING;

-- Insert sample WhatsApp account
INSERT INTO whatsapp_accounts (
    id,
    organization_id,
    business_account_id,
    phone_number_id,
    phone_number,
    display_name,
    access_token,
    webhook_verify_token,
    status,
    webhook_url
) VALUES (
    '00000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000001',
    'demo_business_account_id',
    'demo_phone_number_id',
    '+1234567890',
    'GenSpark Demo Bot',
    'encrypted_access_token_demo',
    'demo_webhook_verify_token',
    'active',
    'https://api.genspark.ai/webhooks/whatsapp'
) ON CONFLICT (id) DO NOTHING;

-- Insert sample contacts
INSERT INTO contacts (
    id,
    organization_id,
    whatsapp_account_id,
    phone_number,
    name,
    profile_name,
    language_code,
    timezone,
    tags,
    custom_fields
) VALUES 
(
    '00000000-0000-0000-0000-000000000004',
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000003',
    '+1234567891',
    'John Demo',
    'John D',
    'en',
    'America/New_York',
    ARRAY['demo', 'test', 'lead'],
    '{"industry": "technology", "company": "Demo Corp", "lead_score": 85}'
),
(
    '00000000-0000-0000-0000-000000000005',
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000003',
    '+1234567892',
    'Maria Ejemplo',
    'Maria E',
    'es',
    'America/Mexico_City',
    ARRAY['demo', 'spanish', 'customer'],
    '{"industry": "retail", "company": "Ejemplo SA", "purchase_history": "premium"}'
) ON CONFLICT (organization_id, phone_number) DO NOTHING;

-- Insert sample contact group
INSERT INTO contact_groups (
    id,
    organization_id,
    name,
    description,
    color,
    contact_ids,
    created_by
) VALUES (
    '00000000-0000-0000-0000-000000000006',
    '00000000-0000-0000-0000-000000000001',
    'Demo Contacts',
    'Sample contacts for testing automation',
    '#007bff',
    ARRAY['00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000005'],
    '00000000-0000-0000-0000-000000000002'
) ON CONFLICT (id) DO NOTHING;

-- Insert sample automation rule
INSERT INTO automation_rules (
    id,
    organization_id,
    whatsapp_account_id,
    name,
    description,
    trigger_type,
    trigger_conditions,
    actions,
    is_active,
    priority,
    created_by
) VALUES (
    '00000000-0000-0000-0000-000000000007',
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000003',
    'Welcome New Contacts',
    'Send welcome message to new contacts who say hello',
    'keyword',
    '{
        "keywords": ["hello", "hi", "hola", "start", "comenzar"],
        "match_type": "contains",
        "case_sensitive": false
    }',
    '{
        "responses": [
            {
                "type": "text",
                "content": "¡Hola! Bienvenido a GenSpark AI. Soy tu asistente virtual. ¿En qué puedo ayudarte hoy?",
                "language": "es"
            },
            {
                "type": "text", 
                "content": "Hello! Welcome to GenSpark AI. I am your virtual assistant. How can I help you today?",
                "language": "en"
            }
        ],
        "ai_followup": true,
        "assign_tags": ["new_contact", "welcomed"]
    }',
    true,
    100,
    '00000000-0000-0000-0000-000000000002'
) ON CONFLICT (id) DO NOTHING;

-- Insert sample bot conversation
INSERT INTO bot_conversations (
    id,
    organization_id,
    whatsapp_account_id,
    contact_id,
    conversation_state,
    current_flow,
    flow_step,
    context_data,
    ai_personality,
    language
) VALUES (
    '00000000-0000-0000-0000-000000000008',
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000004',
    'active',
    'welcome_flow',
    1,
    '{
        "user_name": "John",
        "preferred_language": "en",
        "lead_source": "website",
        "interests": ["automation", "ai"]
    }',
    'professional',
    'en'
) ON CONFLICT (id) DO NOTHING;

-- Insert sample message logs
INSERT INTO message_logs (
    id,
    organization_id,
    whatsapp_account_id,
    contact_id,
    message_id,
    direction,
    message_type,
    content,
    status,
    automation_rule_id,
    processed_by
) VALUES 
(
    '00000000-0000-0000-0000-000000000009',
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000004',
    'wamid_demo_inbound_001',
    'inbound',
    'text',
    '{
        "text": "Hello, I am interested in your services",
        "timestamp": "2024-09-18T10:00:00Z"
    }',
    'read',
    null,
    'user'
),
(
    '00000000-0000-0000-0000-000000000010',
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000004',
    'wamid_demo_outbound_001',
    'outbound',
    'text',
    '{
        "text": "Hello! Welcome to GenSpark AI. I am your virtual assistant. How can I help you today?",
        "timestamp": "2024-09-18T10:00:30Z"
    }',
    'delivered',
    '00000000-0000-0000-0000-000000000007',
    'bot'
) ON CONFLICT (id) DO NOTHING;

-- Update contact last_message_at
UPDATE contacts 
SET last_message_at = CURRENT_TIMESTAMP - INTERVAL '1 hour'
WHERE id IN ('00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000005');

-- Update automation rule execution count
UPDATE automation_rules 
SET execution_count = 1, last_executed_at = CURRENT_TIMESTAMP - INTERVAL '1 hour'
WHERE id = '00000000-0000-0000-0000-000000000007';

COMMIT;