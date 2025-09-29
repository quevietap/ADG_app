-- Clear all mock tokens and force regeneration of real FCM tokens
UPDATE users 
SET fcm_token = NULL, 
    updated_at = NOW()
WHERE fcm_token LIKE 'mock_%';

-- Check current token status
SELECT 
    first_name,
    last_name,
    role,
    CASE 
        WHEN fcm_token IS NULL THEN '❌ NO TOKEN'
        WHEN fcm_token = '' THEN '⚠️ EMPTY TOKEN'
        WHEN fcm_token LIKE 'mock_%' THEN '🧪 MOCK TOKEN'
        WHEN LENGTH(fcm_token) < 50 THEN '⚠️ INVALID TOKEN'
        ELSE '✅ VALID TOKEN'
    END as token_status,
    notification_enabled
FROM users 
WHERE role IN ('driver', 'operator')
ORDER BY role, first_name;