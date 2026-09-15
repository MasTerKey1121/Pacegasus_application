-- =====================================================================
-- Migration: 013_add_user_uid_and_friendships.sql
-- ระบบเพื่อน (Friends)
--   1) users.uid — รหัสสาธารณะ 10 ตัวอักษรที่สุ่มให้ทุกบัญชี ใช้แชร์เพื่อแอดเพื่อน
--      (ไม่เปิดเผย users.id ที่เป็น UUID ภายใน) — backfill ให้บัญชีเดิมทั้งหมด
--      และสร้างอัตโนมัติผ่าน trigger ทุกครั้งที่ INSERT บัญชีใหม่
--   2) friendships — ความสัมพันธ์ระหว่างผู้ใช้ 1 แถวต่อ 1 คู่
--      status: pending (รอฝั่งผู้รับยืนยัน) -> accepted (เป็นเพื่อนแล้ว)
--      ปฏิเสธ/ยกเลิกคำขอ/ลบเพื่อน = ลบแถวทิ้ง เพื่อให้ส่งคำขอใหม่ได้ภายหลัง
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) users.uid
-- ---------------------------------------------------------------------
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS uid VARCHAR(10);

-- ตัดตัวที่สับสนง่ายออก (0/O, 1/I) ให้พิมพ์/อ่านออกเสียงได้ง่าย: 32 ตัวอักษร x 10 หลัก ≈ 2^50
-- ใช้ไบต์สุ่มจาก gen_random_uuid() (core PG13+, CSPRNG) จึงไม่ต้องพึ่ง pgcrypto
-- ข้ามไบต์ 6 และ 8 ของ UUID v4 เพราะมีบิต version/variant คงที่
CREATE OR REPLACE FUNCTION generate_user_uid()
RETURNS VARCHAR(10)
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  alphabet CONSTANT TEXT := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  byte_positions CONSTANT INT[] := ARRAY[0, 1, 2, 3, 4, 5, 7, 9, 10, 11];
  raw BYTEA;
  pos INT;
  candidate TEXT;
BEGIN
  LOOP
    raw := uuid_send(gen_random_uuid());
    candidate := '';
    FOREACH pos IN ARRAY byte_positions LOOP
      candidate := candidate || substr(alphabet, (get_byte(raw, pos) % 32) + 1, 1);
    END LOOP;
    EXIT WHEN NOT EXISTS (SELECT 1 FROM users WHERE uid = candidate);
  END LOOP;
  RETURN candidate;
END;
$$;

-- สุ่ม uid ให้แถวใหม่อัตโนมัติ และห้ามแก้ uid หลังสร้างแล้ว (เพื่อนที่เคยจด UID ไว้ต้องใช้ได้ตลอด)
CREATE OR REPLACE FUNCTION set_user_uid()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.uid IS NULL THEN
      NEW.uid := generate_user_uid();
    END IF;
  ELSIF NEW.uid IS DISTINCT FROM OLD.uid AND OLD.uid IS NOT NULL THEN
    RAISE EXCEPTION 'users.uid is immutable';
  END IF;
  RETURN NEW;
END;
$$;

-- Backfill บัญชีที่มีอยู่แล้ว
UPDATE users SET uid = generate_user_uid() WHERE uid IS NULL;

ALTER TABLE users
  ALTER COLUMN uid SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS users_uid_key ON users (uid);

DO $$
BEGIN
  ALTER TABLE users
    ADD CONSTRAINT chk_users_uid_format CHECK (uid ~ '^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{10}$');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_users_uid ON users;
CREATE TRIGGER trg_users_uid
  BEFORE INSERT OR UPDATE OF uid ON users
  FOR EACH ROW EXECUTE FUNCTION set_user_uid();

COMMENT ON COLUMN users.uid IS 'รหัสผู้ใช้สาธารณะ 10 ตัวอักษร (สุ่มตอนสร้างบัญชี, แก้ไขไม่ได้) ใช้สำหรับค้นหา/แอดเพื่อน';

-- ---------------------------------------------------------------------
-- 2) friendships
-- ---------------------------------------------------------------------
DO $$
BEGIN
  CREATE TYPE friendship_status_enum AS ENUM ('pending', 'accepted');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS friendships (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  addressee_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status        friendship_status_enum NOT NULL DEFAULT 'pending',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  responded_at  TIMESTAMPTZ,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_friendships_not_self CHECK (requester_id <> addressee_id),
  CONSTRAINT chk_friendships_responded_at
    CHECK ((status = 'pending' AND responded_at IS NULL)
        OR (status = 'accepted' AND responded_at IS NOT NULL))
);

-- 1 คู่มีได้แถวเดียวไม่ว่าใครเป็นคนส่ง (กัน A->B และ B->A ซ้อนกัน รวมถึงกรณียิงพร้อมกัน)
CREATE UNIQUE INDEX IF NOT EXISTS uq_friendships_pair
  ON friendships (LEAST(requester_id, addressee_id), GREATEST(requester_id, addressee_id));

CREATE INDEX IF NOT EXISTS idx_friendships_addressee_status
  ON friendships (addressee_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_friendships_requester_status
  ON friendships (requester_id, status, created_at DESC);

DROP TRIGGER IF EXISTS trg_friendships_updated_at ON friendships;
CREATE TRIGGER trg_friendships_updated_at
  BEFORE UPDATE ON friendships
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE friendships IS 'ความสัมพันธ์เพื่อน 1 แถวต่อ 1 คู่ผู้ใช้: pending = รอผู้รับ (addressee) ยืนยัน, accepted = เป็นเพื่อนแล้ว';
