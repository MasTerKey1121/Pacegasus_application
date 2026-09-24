-- =====================================================================
-- Migration: 015_create_avatar_items.sql
-- ระบบ Avatar 2.5D
--   1) avatar_slots — ช่องแต่งตัว (ใบหน้า, ผม, เครา, ... , aura) เป็นตาราง lookup
--      ไม่ใช่ enum เพื่อให้ backoffice เพิ่มช่องใหม่ได้โดยไม่ต้อง ALTER TYPE
--      layer_order = ลำดับวาดซ้อนเริ่มต้นของ renderer (น้อย = อยู่ด้านหลัง)
--   2) avatar_items — แคตตาล็อกไอเท็ม 1 ชิ้นอยู่ได้ 1 ช่อง
--      render_data (JSONB) เก็บข้อมูลเฉพาะของ renderer เช่น layers หลายชั้น,
--      anchor/offset, hidesSlots (หมวกบางแบบซ่อนผม) — DB ไม่ตีความ
--   3) user_avatar_items — ไอเท็มที่ผู้ใช้เป็นเจ้าของ (inventory)
--   4) user_avatars + user_avatar_equipment — ชุดที่ใส่อยู่ 1 ชิ้นต่อ 1 ช่อง
--      FK แบบ composite บังคับที่ระดับ DB ว่า (ก) ไอเท็มตรงช่อง (ข) ผู้ใช้เป็นเจ้าของจริง
-- =====================================================================

DO $$
BEGIN
  CREATE TYPE item_rarity_enum AS ENUM ('common', 'rare', 'epic', 'legendary');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE avatar_item_source_enum AS ENUM ('default', 'shop', 'reward', 'admin');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- ---------------------------------------------------------------------
-- 1) avatar_slots
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS avatar_slots (
  code         VARCHAR(30) PRIMARY KEY,
  name         VARCHAR(60) NOT NULL,
  layer_order  SMALLINT NOT NULL,
  sort_order   SMALLINT NOT NULL,
  is_required  BOOLEAN NOT NULL DEFAULT false,
  is_active    BOOLEAN NOT NULL DEFAULT true,
  CONSTRAINT chk_avatar_slots_code CHECK (code ~ '^[a-z_]{1,30}$')
);

COMMENT ON TABLE avatar_slots IS 'ช่องแต่งตัวของ avatar; is_required = ห้ามถอดจนว่าง (ต้องมีไอเท็ม default ของช่องนั้น)';
COMMENT ON COLUMN avatar_slots.layer_order IS 'ลำดับวาดซ้อนเริ่มต้น (น้อย = หลังสุด) ไอเท็มปรับละเอียดได้ใน render_data.layers';
COMMENT ON COLUMN avatar_slots.sort_order IS 'ลำดับแท็บในหน้าแต่งตัว/ร้านค้า';

INSERT INTO avatar_slots (code, name, layer_order, sort_order, is_required) VALUES
  ('aura',      'ออร่า / เอฟเฟกต์',    0,  130, false),
  ('back',      'เครื่องประดับด้านหลัง', 5,  120, false),
  ('socks',     'ถุงเท้า',             12,  100, false),
  ('pants',     'กางเกง',              14,   90, true),
  ('shoes',     'รองเท้า',             16,  110, false),
  ('inner_top', 'เสื้อตัวใน',           18,   70, true),
  ('necklace',  'สร้อยคอ',             20,   60, false),
  ('outer_top', 'เสื้อตัวนอก',          22,   80, false),
  ('face',      'ใบหน้า',              30,   10, true),
  ('beard',     'เครา',                32,   30, false),
  ('mustache',  'หนวด',                34,   40, false),
  ('hair',      'ทรงผม',               36,   20, false),
  ('headwear',  'เครื่องประดับศีรษะ',     38,   50, false)
ON CONFLICT (code) DO NOTHING;

-- ---------------------------------------------------------------------
-- 2) avatar_items
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS avatar_items (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code           VARCHAR(60) NOT NULL UNIQUE,
  slot_code      VARCHAR(30) NOT NULL REFERENCES avatar_slots(code),
  name           VARCHAR(80) NOT NULL,
  description    VARCHAR(300),
  rarity         item_rarity_enum NOT NULL DEFAULT 'common',
  thumbnail_url  TEXT NOT NULL,
  asset_url      TEXT NOT NULL,
  render_data    JSONB NOT NULL DEFAULT '{}',
  is_tintable    BOOLEAN NOT NULL DEFAULT false,
  is_default     BOOLEAN NOT NULL DEFAULT false,
  is_active      BOOLEAN NOT NULL DEFAULT true,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- เป้าหมายของ composite FK ใน user_avatar_equipment (บังคับว่าไอเท็มใส่ถูกช่อง)
  CONSTRAINT uq_avatar_items_id_slot UNIQUE (id, slot_code),
  CONSTRAINT chk_avatar_items_code CHECK (code ~ '^[a-z0-9_]{1,60}$'),
  CONSTRAINT chk_avatar_items_render_data CHECK (jsonb_typeof(render_data) = 'object')
);

CREATE INDEX IF NOT EXISTS idx_avatar_items_slot_rarity
  ON avatar_items (slot_code, rarity) WHERE is_active;
CREATE INDEX IF NOT EXISTS idx_avatar_items_default
  ON avatar_items (slot_code, created_at) WHERE is_default AND is_active;

DROP TRIGGER IF EXISTS trg_avatar_items_updated_at ON avatar_items;
CREATE TRIGGER trg_avatar_items_updated_at
  BEFORE UPDATE ON avatar_items
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE avatar_items IS 'แคตตาล็อกไอเท็มแต่งตัว; is_default = ทุกคนได้ฟรี, is_active = false คือเลิกแจก/เลิกขาย แต่คนที่มีแล้วยังใส่ได้';
COMMENT ON COLUMN avatar_items.render_data IS 'ข้อมูลของ renderer 2.5D เช่น {"layers":[{"url":"...","z":36}],"anchor":{"x":0,"y":0},"hidesSlots":["hair"]}';
COMMENT ON COLUMN avatar_items.is_tintable IS 'true = ผู้เล่นเลือกสี (color_hex) ตอนใส่ได้';

-- ---------------------------------------------------------------------
-- 3) user_avatar_items (inventory)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_avatar_items (
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  item_id      UUID NOT NULL REFERENCES avatar_items(id) ON DELETE RESTRICT,
  source       avatar_item_source_enum NOT NULL,
  source_ref   UUID,
  acquired_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, item_id)
);

CREATE INDEX IF NOT EXISTS idx_user_avatar_items_user_acquired
  ON user_avatar_items (user_id, acquired_at DESC);

COMMENT ON TABLE user_avatar_items IS 'ไอเท็มที่ผู้ใช้เป็นเจ้าของ; source_ref ชี้ไปที่ต้นทาง เช่น shop_purchases.id';

-- ---------------------------------------------------------------------
-- 4) user_avatars + user_avatar_equipment
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_avatars (
  user_id     UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  skin_tone   VARCHAR(7) NOT NULL DEFAULT '#F1C27D',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_user_avatars_skin_tone CHECK (skin_tone ~ '^#[0-9A-F]{6}$')
);

DROP TRIGGER IF EXISTS trg_user_avatars_updated_at ON user_avatars;
CREATE TRIGGER trg_user_avatars_updated_at
  BEFORE UPDATE ON user_avatars
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS user_avatar_equipment (
  user_id      UUID NOT NULL REFERENCES user_avatars(user_id) ON DELETE CASCADE,
  slot_code    VARCHAR(30) NOT NULL,
  item_id      UUID NOT NULL,
  color_hex    VARCHAR(7),
  equipped_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, slot_code),
  CONSTRAINT fk_user_avatar_equipment_item_slot
    FOREIGN KEY (item_id, slot_code) REFERENCES avatar_items (id, slot_code),
  CONSTRAINT fk_user_avatar_equipment_owned
    FOREIGN KEY (user_id, item_id) REFERENCES user_avatar_items (user_id, item_id) ON DELETE CASCADE,
  CONSTRAINT chk_user_avatar_equipment_color CHECK (color_hex IS NULL OR color_hex ~ '^#[0-9A-F]{6}$')
);

COMMENT ON TABLE user_avatar_equipment IS 'ชุดที่ใส่อยู่ 1 ไอเท็มต่อ 1 ช่อง; FK บังคับว่าไอเท็มตรงช่องและผู้ใช้เป็นเจ้าของ';
