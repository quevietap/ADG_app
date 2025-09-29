-- Check FCM token status for all users
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
    notification_enabled,
    LEFT(fcm_token, 30) as token_preview
FROM users 
WHERE role IN ('driver', 'operator')
ORDER BY role, first_name;