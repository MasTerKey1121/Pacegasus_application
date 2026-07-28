-- =====================================================================
-- Migration: 004_add_running_session_gps_and_hr.sql
-- Additive migration — เพิ่ม field สำหรับเก็บพิกัดการวิ่งและอัตราการเต้นหัวใจ
-- เพื่อใช้สร้างเส้นทางจาก Google Maps และแสดงข้อมูล HR ตอนจบเซสชัน
-- =====================================================================

ALTER TABLE running_sessions
ADD COLUMN IF NOT EXISTS start_lat NUMERIC(9,6),
ADD COLUMN IF NOT EXISTS start_lng NUMERIC(9,6),
ADD COLUMN IF NOT EXISTS end_lat NUMERIC(9,6),
ADD COLUMN IF NOT EXISTS end_lng NUMERIC(9,6),
ADD COLUMN IF NOT EXISTS route_points JSONB,
ADD COLUMN IF NOT EXISTS avg_heart_rate_bpm SMALLINT,
ADD COLUMN IF NOT EXISTS max_heart_rate_bpm SMALLINT;

COMMENT ON COLUMN running_sessions.start_lat IS 'ละติจูดเริ่มต้นของการวิ่ง';
COMMENT ON COLUMN running_sessions.start_lng IS 'ลองจิจูดเริ่มต้นของการวิ่ง';
COMMENT ON COLUMN running_sessions.end_lat IS 'ละติจูดสิ้นสุดของการวิ่ง';
COMMENT ON COLUMN running_sessions.end_lng IS 'ลองจิจูดสิ้นสุดของการวิ่ง';
COMMENT ON COLUMN running_sessions.route_points IS 'รายการพิกัดเส้นทางในรูปแบบ JSONB เช่น [{"lat":13.7,"lng":100.5,"ts":"..."}]';
COMMENT ON COLUMN running_sessions.avg_heart_rate_bpm IS 'อัตราการเต้นหัวใจเฉลี่ย';
COMMENT ON COLUMN running_sessions.max_heart_rate_bpm IS 'อัตราการเต้นหัวใจสูงสุด';
