-- Migration: Add 'driver_completed' status to trips table
-- This allows proper workflow where driver completion requires operator confirmation

-- Drop the existing constraint
ALTER TABLE trips DROP CONSTRAINT IF EXISTS trips_status_check;

-- Add the new constraint with 'driver_completed' status included
ALTER TABLE trips ADD CONSTRAINT trips_status_check 
CHECK (status::text = ANY (ARRAY[
  'pending'::character varying::text, 
  'assigned'::character varying::text, 
  'in_progress'::character varying::text, 
  'driver_completed'::character varying::text,  -- NEW STATUS ADDED
  'completed'::character varying::text, 
  'cancelled'::character varying::text, 
  'deleted'::character varying::text, 
  'archived'::character varying::text
]));

-- Add comment to document the new status
COMMENT ON COLUMN trips.status IS 'Trip status: pending, assigned, in_progress, driver_completed (awaiting operator confirmation), completed (operator confirmed), cancelled, deleted, archived';