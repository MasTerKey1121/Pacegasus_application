-- =====================================================================
-- Migration: 005_add_users_policy_acceptance.sql
-- Additive migration — เพิ่ม field สำหรับติดตามการยอมรับนโยบาย (Privacy Policy /
-- Terms of Service) ก่อนที่ระบบจะอนุญาตให้ส่ง OTP ไปยังผู้ใช้ในขั้นตอน register
-- Flow: สมัคร (กรอกอีเมล) -> ยอมรับ policy -> ระบบส่ง OTP -> ยืนยัน OTP
-- =====================================================================

ALTER TABLE users
ADD COLUMN IF NOT EXISTS policy_accepted BOOLEAN NOT NULL DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS policy_accepted_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS policy_version VARCHAR(20);

COMMENT ON COLUMN users.policy_accepted IS 'สถานะว่าผู้ใช้ยอมรับนโยบาย (Terms/Privacy Policy) แล้วหรือยัง — ต้องเป็น TRUE ก่อนระบบจะอนุญาตให้ส่ง OTP';
COMMENT ON COLUMN users.policy_accepted_at IS 'วันเวลาที่ผู้ใช้กดยอมรับนโยบาย';
COMMENT ON COLUMN users.policy_version IS 'เวอร์ชันของนโยบายที่ผู้ใช้ยอมรับ เช่น "2026-07" เพื่อใช้ตรวจสอบย้อนหลังหากมีการอัปเดตนโยบาย';

-- Index เพื่อให้ query หาผู้ใช้ที่ยังไม่ยอมรับ policy (เช่น ใน background job เตือน)
-- ได้อย่างรวดเร็ว
CREATE INDEX IF NOT EXISTS idx_users_policy_accepted
    ON users (policy_accepted)
    WHERE policy_accepted = FALSE;

-- Constraint: ถ้า policy_accepted = TRUE ต้องมี policy_accepted_at และ policy_version เสมอ
-- (กัน data ไม่ครบจาก path ที่อาจข้ามการบันทึก timestamp/version)
ALTER TABLE users
ADD CONSTRAINT chk_users_policy_accepted_fields
CHECK (
    policy_accepted = FALSE
    OR (policy_accepted_at IS NOT NULL AND policy_version IS NOT NULL)
);