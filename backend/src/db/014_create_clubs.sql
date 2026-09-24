-- =====================================================================
-- Migration: 014_create_clubs.sql
-- ระบบคลับ (Clubs)
--   1) clubs — ข้อมูลคลับ (ชื่อ, คำอธิบาย, รูป, tag) สมาชิกสูงสุด 20 คน
--      member_count ดูแลโดย trigger และถูกบังคับด้วย CHECK จึงเกิน max_members ไม่ได้
--      แม้มีการ INSERT พร้อมกันหลาย request (UPDATE clubs ล็อกแถวคลับให้เรียงกันเอง)
--   2) club_members — ผู้ใช้ 1 คนอยู่ได้ 1 คลับ, 1 คลับมี leader ได้คนเดียว
--      ยศ: leader > sub_leader > member (leader นับเป็นสมาชิก 1 ใน 20 คน)
--   3) club_role_permissions — leader กำหนดสิทธิ์ให้ยศ sub_leader / member ได้เอง
--      (leader มีทุกสิทธิ์เสมอ จึงไม่มีแถวของ leader) สร้างค่าเริ่มต้นอัตโนมัติด้วย trigger
--   4) club_join_requests — คำขอเข้าคลับที่ยังรอดำเนินการ 1 แถวต่อ (คลับ, ผู้ใช้)
--      kind: request (ผู้ใช้ขอเข้าเอง รอ staff อนุมัติ) / invite (staff เชิญ รอผู้ใช้ตอบรับ)
--      อนุมัติ/ปฏิเสธ/ยกเลิก = ลบแถวทิ้ง เหมือน friendships (migration 013)
-- =====================================================================

DO $$
BEGIN
  CREATE TYPE club_role_enum AS ENUM ('leader', 'sub_leader', 'member');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE club_join_kind_enum AS ENUM ('request', 'invite');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- ---------------------------------------------------------------------
-- 1) clubs
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS clubs (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          VARCHAR(40) NOT NULL,
  description   VARCHAR(500),
  image_url     TEXT,
  tags          TEXT[] NOT NULL DEFAULT '{}',
  max_members   SMALLINT NOT NULL DEFAULT 20,
  member_count  SMALLINT NOT NULL DEFAULT 0,
  created_by    UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_clubs_name_not_blank CHECK (btrim(name) <> ''),
  CONSTRAINT chk_clubs_max_members CHECK (max_members BETWEEN 1 AND 20),
  CONSTRAINT chk_clubs_member_count CHECK (member_count BETWEEN 0 AND max_members),
  CONSTRAINT chk_clubs_tags CHECK (cardinality(tags) <= 5)
);

-- ชื่อคลับห้ามซ้ำแบบไม่สนตัวพิมพ์เล็ก/ใหญ่
CREATE UNIQUE INDEX IF NOT EXISTS uq_clubs_name_lower ON clubs (lower(name));
-- ค้นหาด้วย tag: WHERE tags @> ARRAY['...']
CREATE INDEX IF NOT EXISTS idx_clubs_tags ON clubs USING GIN (tags);
CREATE INDEX IF NOT EXISTS idx_clubs_member_count ON clubs (member_count DESC, created_at DESC);

DROP TRIGGER IF EXISTS trg_clubs_updated_at ON clubs;
CREATE TRIGGER trg_clubs_updated_at
  BEFORE UPDATE ON clubs
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE clubs IS 'คลับของผู้ใช้ สมาชิกสูงสุด max_members (<= 20) คน รวม leader';
COMMENT ON COLUMN clubs.member_count IS 'จำนวนสมาชิกปัจจุบัน ดูแลโดย trigger trg_club_members_count ห้ามแก้เอง';

-- ---------------------------------------------------------------------
-- 2) club_members
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS club_members (
  club_id     UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role        club_role_enum NOT NULL DEFAULT 'member',
  joined_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (club_id, user_id)
);

-- ผู้ใช้ 1 คนอยู่ได้แค่ 1 คลับ
CREATE UNIQUE INDEX IF NOT EXISTS uq_club_members_user ON club_members (user_id);
-- 1 คลับมี leader ได้คนเดียว (ตอนโอนหัวหน้าต้องลดยศคนเดิมก่อนแล้วค่อยตั้งคนใหม่)
CREATE UNIQUE INDEX IF NOT EXISTS uq_club_members_leader ON club_members (club_id) WHERE role = 'leader';
CREATE INDEX IF NOT EXISTS idx_club_members_club_role ON club_members (club_id, role, joined_at);

DROP TRIGGER IF EXISTS trg_club_members_updated_at ON club_members;
CREATE TRIGGER trg_club_members_updated_at
  BEFORE UPDATE ON club_members
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION sync_club_member_count()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- ถ้าคลับเต็มจะชน chk_clubs_member_count แล้วทั้ง INSERT ถูก rollback
    UPDATE clubs SET member_count = member_count + 1 WHERE id = NEW.club_id;
    RETURN NEW;
  END IF;
  -- ตอนลบคลับ (cascade) แถว clubs หายไปแล้ว UPDATE นี้จะไม่โดนแถวไหน
  UPDATE clubs SET member_count = member_count - 1 WHERE id = OLD.club_id;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_club_members_count ON club_members;
CREATE TRIGGER trg_club_members_count
  AFTER INSERT OR DELETE ON club_members
  FOR EACH ROW EXECUTE FUNCTION sync_club_member_count();

COMMENT ON TABLE club_members IS 'สมาชิกคลับ: ผู้ใช้ 1 คนอยู่ได้ 1 คลับ, 1 คลับมี leader 1 คน';

-- ---------------------------------------------------------------------
-- 3) club_role_permissions
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS club_role_permissions (
  club_id               UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
  role                  club_role_enum NOT NULL,
  can_approve_requests  BOOLEAN NOT NULL DEFAULT false,
  can_invite            BOOLEAN NOT NULL DEFAULT false,
  can_kick              BOOLEAN NOT NULL DEFAULT false,
  can_edit_info         BOOLEAN NOT NULL DEFAULT false,
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (club_id, role),
  CONSTRAINT chk_club_role_permissions_not_leader CHECK (role <> 'leader')
);

DROP TRIGGER IF EXISTS trg_club_role_permissions_updated_at ON club_role_permissions;
CREATE TRIGGER trg_club_role_permissions_updated_at
  BEFORE UPDATE ON club_role_permissions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ค่าเริ่มต้น: sub_leader อนุมัติ/เชิญ/เตะได้ แต่แก้ข้อมูลคลับไม่ได้, member ไม่มีสิทธิ์จัดการ
CREATE OR REPLACE FUNCTION create_default_club_permissions()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO club_role_permissions (club_id, role, can_approve_requests, can_invite, can_kick, can_edit_info)
  VALUES (NEW.id, 'sub_leader', true, true, true, false),
         (NEW.id, 'member', false, false, false, false)
  ON CONFLICT (club_id, role) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_clubs_default_permissions ON clubs;
CREATE TRIGGER trg_clubs_default_permissions
  AFTER INSERT ON clubs
  FOR EACH ROW EXECUTE FUNCTION create_default_club_permissions();

COMMENT ON TABLE club_role_permissions IS 'สิทธิ์จัดการคลับของแต่ละยศ (leader มีทุกสิทธิ์เสมอ) เตะได้เฉพาะคนที่ยศต่ำกว่า';

-- ---------------------------------------------------------------------
-- 4) club_join_requests
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS club_join_requests (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id     UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind        club_join_kind_enum NOT NULL,
  invited_by  UUID REFERENCES users(id) ON DELETE CASCADE,
  message     VARCHAR(200),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_club_join_requests_inviter CHECK ((kind = 'invite') = (invited_by IS NOT NULL))
);

-- 1 คู่ (คลับ, ผู้ใช้) มีคำขอค้างได้แถวเดียว ไม่ว่าจะเป็น request หรือ invite
CREATE UNIQUE INDEX IF NOT EXISTS uq_club_join_requests_pair ON club_join_requests (club_id, user_id);
CREATE INDEX IF NOT EXISTS idx_club_join_requests_club_kind
  ON club_join_requests (club_id, kind, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_club_join_requests_user_kind
  ON club_join_requests (user_id, kind, created_at DESC);

COMMENT ON TABLE club_join_requests IS 'คำขอเข้าคลับที่รอดำเนินการ: request = ผู้ใช้ขอเข้า รอ staff อนุมัติ, invite = staff เชิญ รอผู้ใช้ตอบรับ';
