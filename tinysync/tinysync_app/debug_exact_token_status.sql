-- Check the EXACT current FCM token status for all users
-- Run this in your database to see what's happening

SELECT 
    id,
    first_name,
    last_name,
    role,
    CASE 
        WHEN fcm_token IS NULL THEN '❌ NO TOKEN'
        WHEN fcm_token = '' THEN '⚠️ EMPTY TOKEN'
        WHEN fcm_token LIKE 'mock_%' THEN '🧪 MOCK TOKEN (NOT REAL)'
        WHEN LENGTH(fcm_token) < 50 THEN '⚠️ INVALID TOKEN'
        ELSE '✅ VALID REAL TOKEN'
    END as token_status,
    notification_enabled,
    LEFT(fcm_token, 50) as token_preview,
    updated_at
FROM users 
WHERE role IN ('driver', 'operator')
ORDER BY role, first_name;

-- Also check which tokens are mock tokens that need fixing
SELECT 
    'MOCK TOKENS TO FIX:' as issue,
    COUNT(*) as count_of_mock_tokens
FROM users 
WHERE fcm_token LIKE 'mock_%';

-- Show the actual mock tokens
SELECT 
    first_name,
    last_name,
    role,
    LEFT(fcm_token, 30) as mock_token_preview
FROM users 
WHERE fcm_token LIKE 'mock_%';