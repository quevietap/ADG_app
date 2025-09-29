-- Quick check to see which drivers don't have FCM tokens
SELECT 
    '🚨 DRIVERS WITHOUT FCM TOKENS:' as status,
    first_name,
    last_name,
    driver_id,
    fcm_token IS NULL as missing_token,
    notification_enabled
FROM users 
WHERE role = 'driver' 
  AND fcm_token IS NULL
ORDER BY first_name;

-- And show which operators do have tokens
SELECT 
    '✅ OPERATORS WITH FCM TOKENS:' as status,
    first_name,
    last_name,
    LEFT(fcm_token, 20) as token_preview,
    notification_enabled
FROM users 
WHERE role = 'operator' 
  AND fcm_token IS NOT NULL
ORDER BY first_name;