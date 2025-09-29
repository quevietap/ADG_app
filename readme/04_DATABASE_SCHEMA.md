# 🗄️ Database Schema - Complete Guide

## 📊 Database Overview

**TinySync Database** uses Supabase (PostgreSQL) as the primary cloud database with local SQLite storage on the IoT device for offline operation.

### **Database Architecture**
```
┌─────────────────────────────────────────────────────────────────┐
│                        Database Architecture                    │
├─────────────────────────────────────────────────────────────────┤
│  IoT Device (SQLite)    │  Flutter App    │  Supabase (PostgreSQL) │
│  ┌─────────────────┐    │  ┌───────────┐  │  ┌─────────────────┐   │
│  │ behavior_logs   │    │  │ Local     │  │  │ behavior_logs   │   │
│  │ snapshots       │◄───┼──┤ Storage   │◄─┼──┤ snapshots       │   │
│  │ sync_tracking   │    │  │ & Cache   │  │  │ trips           │   │
│  └─────────────────┘    │  └───────────┘  │  │ users           │   │
│           │              │       │         │  │ vehicles        │   │
│           │              │       │         │  │ notifications   │   │
│           ▼              │       ▼         │  └─────────────────┘   │
│  Offline Storage         │  Sync Queue     │  Cloud Database        │
└─────────────────────────────────────────────────────────────────┘
```

## 🏗️ Supabase Schema (PostgreSQL)

### **Core Tables**

#### **Users Table**
```sql
CREATE TABLE public.users (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  first_name character varying NOT NULL,
  last_name character varying NOT NULL,
  middle_name character varying,
  username character varying NOT NULL UNIQUE,
  email character varying UNIQUE,
  password_hash character varying NOT NULL,
  role character varying NOT NULL CHECK (role::text = ANY (ARRAY['operator'::character varying::text, 'driver'::character varying::text])),
  status character varying DEFAULT 'active'::character varying CHECK (status::text = ANY (ARRAY['active'::character varying::text, 'inactive'::character varying::text])),
  contact_number character varying,
  driver_license_number character varying,
  driver_license_expiration_date date,
  created_at timestamp without time zone DEFAULT now(),
  updated_at timestamp without time zone DEFAULT now(),
  profile_picture character varying,
  date_of_birth date,
  address character varying,
  driver_license_class character varying CHECK (driver_license_class IS NULL OR (driver_license_class::text = ANY (ARRAY['Pro'::character varying, 'Non-Pro'::character varying]::text[]))),
  driver_license_restrictions character varying,
  driver_license_date_issued date,
  employee_id character varying UNIQUE,
  date_hired date,
  position character varying,
  operator_id character varying UNIQUE,
  driver_id character varying UNIQUE,
  profile_image_url text,
  fcm_token text,
  notification_enabled boolean DEFAULT true,
  CONSTRAINT users_pkey PRIMARY KEY (id)
);
```

#### **Trips Table**
```sql
CREATE TABLE public.trips (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  trip_ref_number character varying NOT NULL UNIQUE,
  origin character varying NOT NULL,
  destination character varying NOT NULL,
  start_time timestamp without time zone NOT NULL,
  end_time timestamp without time zone,
  priority character varying DEFAULT 'normal'::character varying CHECK (priority::text = ANY (ARRAY['low'::character varying::text, 'normal'::character varying::text, 'high'::character varying::text, 'urgent'::character varying::text])),
  status character varying DEFAULT 'pending'::character varying CHECK (status::text = ANY (ARRAY['pending'::character varying::text, 'assigned'::character varying::text, 'in_progress'::character varying::text, 'completed'::character varying::text, 'cancelled'::character varying::text, 'deleted'::character varying::text, 'archived'::character varying::text])),
  driver_id uuid,
  contact_person character varying,
  contact_phone character varying,
  notes text,
  progress numeric DEFAULT 0.0 CHECK (progress >= 0::numeric AND progress <= 100::numeric),
  created_at timestamp without time zone DEFAULT now(),
  updated_at timestamp without time zone DEFAULT now(),
  sub_driver_id uuid,
  scheduled_deletion timestamp with time zone,
  canceled_at timestamp with time zone,
  deleted_at timestamp with time zone,
  vehicle_id uuid,
  confirmed_by uuid,
  operator_confirmed_at timestamp with time zone,
  started_at timestamp with time zone,
  completed_at timestamp with time zone,
  start_latitude numeric,
  start_longitude numeric,
  end_latitude numeric,
  end_longitude numeric,
  current_latitude numeric,
  current_longitude numeric,
  last_location_update timestamp with time zone,
  archived_at timestamp with time zone,
  accepted_at timestamp with time zone,
  CONSTRAINT trips_pkey PRIMARY KEY (id),
  CONSTRAINT trips_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id),
  CONSTRAINT trips_confirmed_by_fkey FOREIGN KEY (confirmed_by) REFERENCES public.users(id),
  CONSTRAINT trips_sub_driver_id_fkey FOREIGN KEY (sub_driver_id) REFERENCES public.users(id),
  CONSTRAINT trips_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.users(id)
);
```

#### **Vehicles Table**
```sql
CREATE TABLE public.vehicles (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  plate_number character varying NOT NULL UNIQUE,
  make character varying NOT NULL,
  model character varying NOT NULL,
  type character varying NOT NULL,
  capacity_kg numeric,
  status character varying DEFAULT 'Available'::character varying CHECK (status::text = ANY (ARRAY['Available'::character varying::text, 'Maintenance'::character varying::text, 'Out_of_service'::character varying::text])),
  last_maintenance_date date,
  next_maintenance_date date,
  created_at timestamp without time zone DEFAULT now(),
  updated_at timestamp without time zone DEFAULT now(),
  CONSTRAINT vehicles_pkey PRIMARY KEY (id)
);
```

### **Monitoring & Behavior Tables**

#### **Snapshots Table** (Unified for behavior logs and images)
```sql
CREATE TABLE public.snapshots (
  id bigint NOT NULL DEFAULT nextval('snapshots_id_seq'::regclass),
  filename character varying NOT NULL,
  behavior_type character varying,
  driver_id uuid,
  trip_id uuid,
  timestamp timestamp with time zone DEFAULT now(),
  device_id character varying NOT NULL,
  image_quality character varying DEFAULT 'HD'::character varying,
  file_size_mb numeric,
  created_at timestamp with time zone DEFAULT now(),
  driver_type text DEFAULT 'main'::text,
  image_data bytea,
  source character varying DEFAULT 'iot'::character varying,
  details jsonb,
  event_type character varying DEFAULT 'snapshot'::character varying CHECK (event_type::text = ANY (ARRAY['behavior'::character varying, 'snapshot'::character varying]::text[])),
  evidence_reason text,
  confidence_score numeric DEFAULT 0.0 CHECK (confidence_score >= 0.0 AND confidence_score <= 1.0),
  event_duration numeric DEFAULT 0.0 CHECK (event_duration >= 0.0),
  gaze_pattern text,
  face_direction text,
  eye_state text,
  is_legitimate_driving boolean DEFAULT true,
  evidence_strength character varying DEFAULT 'medium'::character varying CHECK (evidence_strength::text = ANY (ARRAY['low'::character varying, 'medium'::character varying, 'high'::character varying]::text[])),
  trigger_justification text,
  reflection_detected boolean DEFAULT false,
  detection_reliability numeric DEFAULT 50.0,
  false_positive_count integer DEFAULT 0,
  driver_threshold_adjusted numeric,
  compliance_audit_trail text,
  CONSTRAINT snapshots_pkey PRIMARY KEY (id),
  CONSTRAINT snapshots_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.users(id),
  CONSTRAINT snapshots_trip_id_fkey FOREIGN KEY (trip_id) REFERENCES public.trips(id)
);
```

#### **Driver Locations Table**
```sql
CREATE TABLE public.driver_locations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  driver_id uuid NOT NULL,
  latitude double precision NOT NULL,
  longitude double precision NOT NULL,
  accuracy double precision DEFAULT 0.0,
  speed double precision DEFAULT 0.0,
  heading double precision DEFAULT 0.0,
  timestamp timestamp with time zone DEFAULT now(),
  is_active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT driver_locations_pkey PRIMARY KEY (id),
  CONSTRAINT driver_locations_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.users(id)
);
```

#### **Trip Locations Table**
```sql
CREATE TABLE public.trip_locations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  trip_id uuid,
  latitude double precision NOT NULL,
  longitude double precision NOT NULL,
  accuracy double precision,
  speed double precision,
  heading double precision,
  altitude double precision,
  location_type character varying DEFAULT 'current'::character varying,
  address text,
  timestamp timestamp with time zone DEFAULT now(),
  created_at timestamp with time zone DEFAULT now(),
  driver_id uuid,
  CONSTRAINT trip_locations_pkey PRIMARY KEY (id),
  CONSTRAINT trip_locations_trip_id_fkey FOREIGN KEY (trip_id) REFERENCES public.trips(id),
  CONSTRAINT trip_locations_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.users(id)
);
```

### **Session & Logging Tables**

#### **Driver Sessions Table**
```sql
CREATE TABLE public.driver_sessions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  driver_id uuid,
  start_time timestamp without time zone NOT NULL,
  end_time timestamp without time zone,
  status character varying DEFAULT 'active'::character varying CHECK (status::text = ANY (ARRAY['active'::character varying::text, 'completed'::character varying::text, 'cancelled'::character varying::text])),
  total_distance numeric DEFAULT 0.0,
  created_at timestamp without time zone DEFAULT now(),
  CONSTRAINT driver_sessions_pkey PRIMARY KEY (id),
  CONSTRAINT driver_sessions_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.users(id)
);
```

#### **Session Logs Table**
```sql
CREATE TABLE public.session_logs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  trip_id uuid,
  driver_id uuid,
  event_type character varying NOT NULL,
  description text,
  origin character varying,
  destination character varying,
  latitude double precision,
  longitude double precision,
  created_at timestamp with time zone DEFAULT now(),
  timestamp timestamp with time zone DEFAULT now(),
  CONSTRAINT session_logs_pkey PRIMARY KEY (id),
  CONSTRAINT session_logs_trip_id_fkey FOREIGN KEY (trip_id) REFERENCES public.trips(id),
  CONSTRAINT session_logs_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.users(id)
);
```

#### **Trip Logs Table**
```sql
CREATE TABLE public.trip_logs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  trip_id uuid NOT NULL,
  driver_id uuid,
  operator_id uuid,
  event_type character varying NOT NULL CHECK (event_type::text = ANY (ARRAY['trip_started'::character varying, 'trip_completed'::character varying, 'trip_confirmed'::character varying, 'break_started'::character varying, 'break_ended'::character varying, 'compliance_alert'::character varying, 'driving_limit_warning'::character varying, 'rest_period_required'::character varying]::text[])),
  event_details jsonb DEFAULT '{}'::jsonb,
  event_timestamp timestamp with time zone NOT NULL DEFAULT now(),
  location_lat numeric,
  location_lng numeric,
  additional_data jsonb DEFAULT '{}'::jsonb,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT trip_logs_pkey PRIMARY KEY (id),
  CONSTRAINT trip_logs_trip_id_fkey FOREIGN KEY (trip_id) REFERENCES public.trips(id),
  CONSTRAINT trip_logs_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.users(id),
  CONSTRAINT trip_logs_operator_id_fkey FOREIGN KEY (operator_id) REFERENCES public.users(id)
);
```

### **Notification Tables**

#### **Notifications Table**
```sql
CREATE TABLE public.notifications (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  trip_id uuid,
  user_id uuid,
  title character varying NOT NULL,
  message text NOT NULL,
  type character varying NOT NULL,
  is_read boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT notifications_pkey PRIMARY KEY (id),
  CONSTRAINT notifications_trip_id_fkey FOREIGN KEY (trip_id) REFERENCES public.trips(id),
  CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id)
);
```

#### **Push Notifications Table**
```sql
CREATE TABLE public.push_notifications (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  fcm_token text NOT NULL,
  title text NOT NULL,
  body text NOT NULL,
  data jsonb DEFAULT '{}'::jsonb,
  status text DEFAULT 'pending'::text CHECK (status = ANY (ARRAY['pending'::text, 'sent'::text, 'failed'::text])),
  created_at timestamp with time zone DEFAULT now(),
  processed_at timestamp with time zone,
  error_message text,
  CONSTRAINT push_notifications_pkey PRIMARY KEY (id)
);
```

#### **Notification Logs Table**
```sql
CREATE TABLE public.notification_logs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  fcm_token text NOT NULL,
  title text NOT NULL,
  body text NOT NULL,
  data jsonb DEFAULT '{}'::jsonb,
  status text DEFAULT 'sent'::text CHECK (status = ANY (ARRAY['sent'::text, 'failed'::text])),
  fcm_response jsonb,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT notification_logs_pkey PRIMARY KEY (id)
);
```

### **Management Tables**

#### **Schedules Table**
```sql
CREATE TABLE public.schedules (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  trip_id uuid,
  schedule_date date NOT NULL,
  schedule_time time without time zone,
  driver_id uuid,
  vehicle_id uuid,
  status character varying DEFAULT 'scheduled'::character varying CHECK (status::text = ANY (ARRAY['scheduled'::character varying::text, 'completed'::character varying::text, 'cancelled'::character varying::text])),
  created_at timestamp without time zone DEFAULT now(),
  CONSTRAINT schedules_pkey PRIMARY KEY (id),
  CONSTRAINT schedules_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id),
  CONSTRAINT schedules_trip_id_fkey FOREIGN KEY (trip_id) REFERENCES public.trips(id),
  CONSTRAINT schedules_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.users(id)
);
```

#### **Maintenance History Table**
```sql
CREATE TABLE public.maintenance_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  vehicle_id uuid NOT NULL,
  maintenance_date date NOT NULL,
  maintenance_type character varying NOT NULL,
  description text,
  cost numeric,
  performed_by character varying,
  next_maintenance_date date,
  status character varying DEFAULT 'Completed'::character varying,
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT maintenance_history_pkey PRIMARY KEY (id),
  CONSTRAINT maintenance_history_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id)
);
```

#### **Driver Ratings Table**
```sql
CREATE TABLE public.driver_ratings (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  driver_id uuid NOT NULL,
  rated_by uuid NOT NULL,
  trip_id uuid,
  rating numeric NOT NULL CHECK (rating >= 1::numeric AND rating <= 5::numeric),
  comment text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  metadata jsonb DEFAULT '{}'::jsonb,
  CONSTRAINT driver_ratings_pkey PRIMARY KEY (id),
  CONSTRAINT driver_ratings_rated_by_fkey FOREIGN KEY (rated_by) REFERENCES public.users(id),
  CONSTRAINT driver_ratings_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.users(id)
);
```

### **Sync & Tracking Tables**

#### **Sync Tracking Table**
```sql
CREATE TABLE public.sync_tracking (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  data_id text UNIQUE,
  data_type text NOT NULL,
  sent_to_flutter boolean DEFAULT false,
  sent_to_supabase boolean DEFAULT false,
  timestamp timestamp with time zone DEFAULT now(),
  CONSTRAINT sync_tracking_pkey PRIMARY KEY (id)
);
```

#### **History Table**
```sql
CREATE TABLE public.history (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  driver_id uuid DEFAULT gen_random_uuid(),
  trip_id uuid,
  completed_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  fuel_used numeric,
  weight numeric,
  packages integer,
  delivery_receipt character varying,
  customer_rating numeric,
  notes text,
  client_name character varying,
  requested_at timestamp with time zone,
  CONSTRAINT history_pkey PRIMARY KEY (id),
  CONSTRAINT history_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.users(id),
  CONSTRAINT history_trip_id_fkey FOREIGN KEY (trip_id) REFERENCES public.trips(id)
);
```

## 💾 IoT Device Database (SQLite)

### **Local Database Schema**

#### **Behavior Logs Table**
```sql
CREATE TABLE behavior_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    driver_id TEXT,
    trip_id TEXT,
    behavior_type TEXT NOT NULL,
    confidence_score REAL,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    details TEXT,
    session_id TEXT,
    device_id TEXT NOT NULL
);
```

#### **Snapshots Table**
```sql
CREATE TABLE snapshots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    filename TEXT NOT NULL,
    behavior_type TEXT,
    driver_id TEXT,
    trip_id TEXT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    device_id TEXT NOT NULL,
    image_quality TEXT DEFAULT 'HD',
    file_size_mb REAL,
    image_data BLOB,
    source TEXT DEFAULT 'iot',
    details TEXT,
    event_type TEXT DEFAULT 'snapshot',
    confidence_score REAL DEFAULT 0.0,
    event_duration REAL DEFAULT 0.0,
    gaze_pattern TEXT,
    face_direction TEXT,
    eye_state TEXT,
    is_legitimate_driving BOOLEAN DEFAULT 1,
    evidence_strength TEXT DEFAULT 'medium',
    trigger_justification TEXT,
    reflection_detected BOOLEAN DEFAULT 0,
    detection_reliability REAL DEFAULT 50.0,
    false_positive_count INTEGER DEFAULT 0,
    driver_threshold_adjusted REAL
);
```

## 🔄 Data Synchronization

### **Sync Strategy**
```
IoT Device → Flutter App → Supabase Database
     │            │              │
     ▼            ▼              ▼
Local SQLite → Processing → PostgreSQL
     │            │              │
     ▼            ▼              ▼
Offline Queue → Validation → Real-time Sync
```

### **Sync Process**
1. **Data Capture**: IoT device captures behavior events and snapshots
2. **Local Storage**: Data stored in local SQLite database
3. **WiFi Direct**: Data transmitted to Flutter app via HTTP POST
4. **Processing**: Flutter app validates and processes data
5. **Cloud Sync**: Data uploaded to Supabase in chronological order
6. **Real-time Updates**: UI updated with new data via subscriptions

### **Timestamp Preservation**
- **IoT Timestamps**: Original detection timestamps preserved
- **Phone Processing**: Phone processing time tracked separately
- **Chronological Order**: Data sorted by original timestamps before sync
- **Audit Trail**: Complete timestamp tracking from IoT → Phone → Cloud

## 📊 Database Performance

### **Indexes**
```sql
-- Performance indexes
CREATE INDEX idx_snapshots_timestamp ON snapshots(timestamp);
CREATE INDEX idx_snapshots_driver_id ON snapshots(driver_id);
CREATE INDEX idx_snapshots_trip_id ON snapshots(trip_id);
CREATE INDEX idx_trips_status ON trips(status);
CREATE INDEX idx_trips_driver_id ON trips(driver_id);
CREATE INDEX idx_driver_locations_timestamp ON driver_locations(timestamp);
CREATE INDEX idx_trip_locations_trip_id ON trip_locations(trip_id);
```

### **Query Optimization**
- **Partitioning**: Trip-based data partitioning for large datasets
- **Caching**: Frequently accessed data cached in Flutter app
- **Batch Operations**: Efficient batch inserts and updates
- **Real-time Subscriptions**: Optimized for live data updates

## 🔐 Security & Access Control

### **Row Level Security (RLS)**
```sql
-- Enable RLS on sensitive tables
ALTER TABLE snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE driver_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE trip_logs ENABLE ROW LEVEL SECURITY;

-- Create policies for data access
CREATE POLICY "Users can view their own data" ON snapshots
    FOR SELECT USING (auth.uid() = driver_id);
```

### **Data Encryption**
- **In Transit**: HTTPS/WSS encryption for all API communication
- **At Rest**: Database-level encryption for sensitive data
- **Local Storage**: Encrypted local storage on IoT device

---

**Database Status**: Production Ready ✅  
**Last Updated**: December 2024  
**Version**: 1.0.1+5
