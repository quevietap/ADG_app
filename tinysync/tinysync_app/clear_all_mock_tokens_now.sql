-- STEP 1: Clear all mock tokens to force regeneration
UPDATE users 
SET fcm_token = NULL, 
    updated_at = NOW()
WHERE fcm_token LIKE 'mock_%';

-- STEP 2: Verify they were cleared
SELECT 
    first_name,
    last_name,
    role,
    CASE 
        WHEN fcm_token IS NULL THEN '✅ CLEARED - READY FOR REAL TOKEN'
        WHEN fcm_token LIKE 'mock_%' THEN '❌ STILL HAS MOCK TOKEN'
        ELSE '✅ HAS REAL TOKEN'
    END as status
FROM users 
WHERE role IN ('driver', 'operator')
ORDER BY role, first_name;