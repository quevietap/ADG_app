-- Add missing database columns for overdue notification system

-- Add last_overdue_notification_sent column to trips table
ALTER TABLE trips 
ADD COLUMN IF NOT EXISTS last_overdue_notification_sent TIMESTAMP WITH TIME ZONE;

-- Add metadata column to operator_notifications table  
ALTER TABLE operator_notifications 
ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}';

-- Add comment for documentation
COMMENT ON COLUMN trips.last_overdue_notification_sent IS 'Timestamp of last overdue notification sent for this trip';
COMMENT ON COLUMN operator_notifications.metadata IS 'Additional notification metadata in JSON format';

-- Show the updated schema
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'trips' AND column_name = 'last_overdue_notification_sent';

SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'operator_notifications' AND column_name = 'metadata';