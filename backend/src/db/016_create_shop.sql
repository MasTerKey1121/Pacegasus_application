-- =====================================================================
-- Migration: 016_create_shop.sql
-- ร้านค้าไอเท็ม avatar (จ่ายด้วย coin จาก user_game_progress)
--   1) shop_listings — "รอบขาย" ของไอเท็ม 1 ชิ้น: ราคา + ช่วงเวลาขาย
--      แยกจาก avatar_items เพื่อให้ไอเท็มเดิมกลับมาขายใหม่ในราคา/ช่วงเวลาอื่นได้
--      ends_at = NULL คือขายถาวร; ไอเท็มเดียวกันห้ามมีรอบขายที่ active ซ้อนช่วงเวลากัน
--   2) shop_purchases — ประวัติการซื้อ (ledger ฝั่งจ่าย coin คู่กับ game_reward_events ฝั่งได้)
--      เก็บราคาจริงตอนซื้อไว้ เพราะราคาใน listing แก้ภายหลังได้
-- =====================================================================

-- ใช้กับ exclusion constraint (uuid WITH =) ด้านล่าง
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ---------------------------------------------------------------------
-- 1) shop_listings
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS shop_listings (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id               UUID NOT NULL REFERENCES avatar_items(id) ON DELETE RESTRICT,
  price_coins           INTEGER NOT NULL,
  original_price_coins  INTEGER,
  starts_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  ends_at               TIMESTAMPTZ,
  is_featured           BOOLEAN NOT NULL DEFAULT false,
  sort_order            INTEGER NOT NULL DEFAULT 0,
  is_active             BOOLEAN NOT NULL DEFAULT true,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_shop_listings_price CHECK (price_coins >= 0),
  CONSTRAINT chk_shop_listings_original_price
    CHECK (original_price_coins IS NULL OR original_price_coins > price_coins),
  CONSTRAINT chk_shop_listings_period CHECK (ends_at IS NULL OR ends_at > starts_at),
  CONSTRAINT ex_shop_listings_item_period EXCLUDE USING gist (
    item_id WITH =,
    tstzrange(starts_at, ends_at) WITH &&
  ) WHERE (is_active)
);

CREATE INDEX IF NOT EXISTS idx_shop_listings_period
  ON shop_listings (starts_at, ends_at) WHERE is_active;
CREATE INDEX IF NOT EXISTS idx_shop_listings_item ON shop_listings (item_id);

DROP TRIGGER IF EXISTS trg_shop_listings_updated_at ON shop_listings;
CREATE TRIGGER trg_shop_listings_updated_at
  BEFORE UPDATE ON shop_listings
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE shop_listings IS 'รอบขายไอเท็ม: ขายอยู่เมื่อ is_active และ starts_at <= now() < ends_at (ends_at NULL = ถาวร)';
COMMENT ON COLUMN shop_listings.original_price_coins IS 'ราคาก่อนลด (โชว์ขีดฆ่า) NULL = ไม่ได้ลดราคา';

-- ---------------------------------------------------------------------
-- 2) shop_purchases
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS shop_purchases (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  listing_id          UUID NOT NULL REFERENCES shop_listings(id) ON DELETE RESTRICT,
  item_id             UUID NOT NULL REFERENCES avatar_items(id) ON DELETE RESTRICT,
  price_coins         INTEGER NOT NULL,
  coin_balance_after  INTEGER NOT NULL,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_shop_purchases_price CHECK (price_coins >= 0),
  CONSTRAINT chk_shop_purchases_balance CHECK (coin_balance_after >= 0),
  -- ไอเท็มไม่ใช่ของสิ้นเปลือง ซื้อซ้ำไม่ได้ (กันกดซื้อซ้อนกันด้วย)
  CONSTRAINT uq_shop_purchases_user_item UNIQUE (user_id, item_id)
);

CREATE INDEX IF NOT EXISTS idx_shop_purchases_user_created
  ON shop_purchases (user_id, created_at DESC);

COMMENT ON TABLE shop_purchases IS 'ประวัติการซื้อไอเท็มด้วย coin; price_coins คือราคาจริง ณ เวลาที่ซื้อ';
