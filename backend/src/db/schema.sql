-- ============================================================================
-- Pacegasus — Migration: Main Quest + Side Quest System
-- ============================================================================
-- ต่อยอดจาก 07_database_schema.md (10 ตารางเดิม)
-- เพิ่ม: Main Quest (Adaptive Program Progression), Side Quest (Environment x
--        Training Type scavenger hunt), running_sessions skeleton
-- PostgreSQL 14+ / Supabase
-- ============================================================================


-- ============================================================================
-- SECTION 0: แก้ไข ENUM เดิม
-- ============================================================================

-- experience_level_enum เดิมมี: beginner, intermediate, advanced, elite
-- เพิ่ม lower_intermediate / upper_intermediate เพื่อให้ตรงกับ program_templates
-- คง 'intermediate' เดิมไว้เพื่อไม่กระทบ record เก่า (ไม่ใช้ต่อสำหรับ user ใหม่)
ALTER TYPE experience_level_enum ADD VALUE IF NOT EXISTS 'lower_intermediate';
ALTER TYPE experience_level_enum ADD VALUE IF NOT EXISTS 'upper_intermediate';


-- ============================================================================
-- SECTION 1: ENUM ใหม่
-- ============================================================================

CREATE TYPE program_level_enum AS ENUM (
  'beginner', 'lower_intermediate', 'upper_intermediate'
);

CREATE TYPE phase_code_enum AS ENUM (
  'base', 'build', 'peak', 'taper_easy', 'race'
);

CREATE TYPE session_type_enum AS ENUM (
  'easy', 'long_run', 'tempo', 'vo2max', 'threshold'
);

CREATE TYPE session_unit_enum AS ENUM (
  'minutes', 'km', 'reps'
);

CREATE TYPE sequencing_rule_enum AS ENUM (
  'must_precede', 'cannot_adjacent', 'rest_after'
);

CREATE TYPE main_quest_status_enum AS ENUM (
  'pending', 'in_progress', 'completed', 'partial', 'skipped'
);

CREATE TYPE running_session_status_enum AS ENUM (
  'planned', 'in_progress', 'completed', 'abandoned'
);

CREATE TYPE side_quest_training_type_enum AS ENUM (
  'easy', 'long_run', 'tempo', 'interval'
);

CREATE TYPE side_quest_mechanic_enum AS ENUM (
  'collect_distance', 'pace_trigger', 'sprint_marker'
);

CREATE TYPE side_quest_status_enum AS ENUM (
  'in_progress', 'completed', 'partial', 'expired'
);

CREATE TYPE badge_code_enum AS ENUM (
  'park_regular', 'road_runner', 'city_explorer',
  'treadmill_warrior', 'trail_blazer', 'pacegasus_explorer'
);

CREATE TYPE program_status_enum AS ENUM (
  'active', 'completed', 'paused'
);


-- ============================================================================
-- SECTION 2: Experience Level Ranking (ใช้เช็ค prerequisite)
-- ============================================================================

CREATE TABLE experience_level_ranks (
  level experience_level_enum PRIMARY KEY,
  rank  SMALLINT NOT NULL
);

INSERT INTO experience_level_ranks (level, rank) VALUES
  ('beginner', 1),
  ('lower_intermediate', 2),
  ('upper_intermediate', 3),
  ('advanced', 4),
  ('elite', 5);
  -- 'intermediate' (ค่าเดิม legacy) ไม่ใส่ rank เพราะไม่ใช้ต่อสำหรับ user ใหม่


-- ============================================================================
-- SECTION 3: Main Quest — Program Template (ข้อมูลนิ่ง)
-- ============================================================================

CREATE TABLE program_templates (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  level              program_level_enum NOT NULL UNIQUE,
  require_exp_level  experience_level_enum,          -- NULL = ไม่มี prerequisite
  goal_label         VARCHAR(50),                     -- 'sub_50' / '10k_sub_1.40' / '21k_sub_3.30'
  duration_weeks_min SMALLINT,
  duration_weeks_max SMALLINT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE program_phases (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  program_template_id UUID NOT NULL REFERENCES program_templates(id) ON DELETE CASCADE,
  phase_code          phase_code_enum,   -- NULL = single-phase program (Beginner)
  phase_order         SMALLINT NOT NULL,
  UNIQUE (program_template_id, phase_order)
);

CREATE TABLE session_type_specs (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  program_template_id   UUID NOT NULL REFERENCES program_templates(id) ON DELETE CASCADE,
  phase_id              UUID REFERENCES program_phases(id) ON DELETE CASCADE, -- NULL = ทั้งโปรแกรม
  session_type          session_type_enum NOT NULL,
  unit                  session_unit_enum NOT NULL,
  multiplier            NUMERIC(5,2) NOT NULL DEFAULT 1.00,  -- ตัวคูณกับ user baseline
  weekly_cap            SMALLINT,                            -- จำกัดสูงสุดต่อสัปดาห์
  program_total_target  SMALLINT,                            -- เป้ารวมทั้งโปรแกรม (จบคอร์ส)
  value_low             NUMERIC(6,2),                         -- ช่วงค่าอ้างอิงต่อครั้ง (ต่ำสุด)
  value_high            NUMERIC(6,2),                         -- ช่วงค่าอ้างอิงต่อครั้ง (สูงสุด)
  is_bonus              BOOLEAN NOT NULL DEFAULT false        -- true = Threshold ของ Beginner (ไม่บังคับ)
);

CREATE TABLE program_sequencing_rules (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  program_template_id  UUID NOT NULL REFERENCES program_templates(id) ON DELETE CASCADE,
  rule_type            sequencing_rule_enum NOT NULL,
  session_type_a       session_type_enum NOT NULL,
  session_type_b       session_type_enum,             -- NULL เมื่อ rule_type = rest_after
  applies_to_phase_id  UUID REFERENCES program_phases(id) ON DELETE CASCADE  -- NULL = ทุก phase
);


-- ============================================================================
-- SECTION 4: Running Session (skeleton — รอ Training Session state diagram)
-- ============================================================================

CREATE TABLE running_sessions (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  environment      preferred_environment_enum,        -- park/road/city/treadmill/trail
  session_type     session_type_enum,                 -- easy/long_run/tempo/vo2max/threshold
  status           running_session_status_enum NOT NULL DEFAULT 'planned',
  started_at       TIMESTAMPTZ,
  ended_at         TIMESTAMPTZ,
  distance_km      NUMERIC(6,2),
  duration_seconds INT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_running_sessions_user ON running_sessions (user_id, created_at DESC);


-- ============================================================================
-- SECTION 5: Main Quest — ข้อมูลผู้ใช้ (dynamic)
-- ============================================================================

CREATE TABLE user_programs (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  program_template_id   UUID NOT NULL REFERENCES program_templates(id),
  start_date            DATE NOT NULL DEFAULT CURRENT_DATE,
  current_phase_id      UUID REFERENCES program_phases(id),
  current_week          SMALLINT NOT NULL DEFAULT 1,
  status                program_status_enum NOT NULL DEFAULT 'active',
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 1 คน มีโปรแกรม active พร้อมกันได้แค่ 1 อัน
CREATE UNIQUE INDEX uq_user_programs_active
  ON user_programs (user_id) WHERE status = 'active';

CREATE TABLE user_program_baselines (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_program_id   UUID NOT NULL REFERENCES user_programs(id) ON DELETE CASCADE,
  session_type      session_type_enum NOT NULL,
  base_value        NUMERIC(6,2) NOT NULL,
  unit              session_unit_enum NOT NULL,
  UNIQUE (user_program_id, session_type)
);

CREATE TABLE main_quest_instances (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_program_id     UUID NOT NULL REFERENCES user_programs(id) ON DELETE CASCADE,
  scheduled_date      DATE NOT NULL,
  session_type        session_type_enum NOT NULL,
  phase_id            UUID REFERENCES program_phases(id),
  planned_value       NUMERIC(6,2) NOT NULL,     -- = base_value x multiplier ตอน generate
  unit                session_unit_enum NOT NULL,
  is_bonus            BOOLEAN NOT NULL DEFAULT false,
  status              main_quest_status_enum NOT NULL DEFAULT 'pending',
  actual_value        NUMERIC(6,2),
  rpe_reported        SMALLINT CHECK (rpe_reported BETWEEN 1 AND 10),
  running_session_id  UUID REFERENCES running_sessions(id),
  completed_at        TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_main_quest_program_date
  ON main_quest_instances (user_program_id, scheduled_date);

CREATE TABLE user_program_completion (
  user_program_id  UUID NOT NULL REFERENCES user_programs(id) ON DELETE CASCADE,
  session_type     session_type_enum NOT NULL,
  completed_count  INT NOT NULL DEFAULT 0,
  target_count     SMALLINT,
  PRIMARY KEY (user_program_id, session_type)
);


-- ============================================================================
-- SECTION 6: Side Quest
-- ============================================================================

CREATE TABLE side_quest_templates (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  environment        preferred_environment_enum NOT NULL,  -- reuse enum เดิม
  training_type      side_quest_training_type_enum NOT NULL,
  title              VARCHAR(150) NOT NULL,
  description        TEXT NOT NULL,
  target_object      VARCHAR(100) NOT NULL,
  mechanic_type      side_quest_mechanic_enum NOT NULL,
  km_per             NUMERIC(4,2),      -- ใช้กับ collect_distance เท่านั้น
  cap_count          SMALLINT,          -- ใช้กับ collect_distance เท่านั้น
  fixed_count        SMALLINT,          -- ใช้กับ pace_trigger / sprint_marker
  coin_reward_base   SMALLINT NOT NULL DEFAULT 10,
  is_active          BOOLEAN NOT NULL DEFAULT true,
  UNIQUE (environment, training_type, title)
);

CREATE TABLE user_side_quest_instances (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  running_session_id       UUID REFERENCES running_sessions(id),
  user_id                  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  side_quest_template_id   UUID NOT NULL REFERENCES side_quest_templates(id),
  target_count             SMALLINT NOT NULL,
  found_count              SMALLINT NOT NULL DEFAULT 0,
  status                   side_quest_status_enum NOT NULL DEFAULT 'in_progress',
  coin_awarded             SMALLINT NOT NULL DEFAULT 0,
  started_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at             TIMESTAMPTZ
);

CREATE INDEX idx_user_side_quest_user ON user_side_quest_instances (user_id, started_at DESC);
CREATE INDEX idx_user_side_quest_session ON user_side_quest_instances (running_session_id);

CREATE TABLE quest_album_photos (
  id                              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_side_quest_instance_id     UUID NOT NULL REFERENCES user_side_quest_instances(id) ON DELETE CASCADE,
  photo_url                       TEXT NOT NULL,
  gps_lat                         NUMERIC(9,6),
  gps_lng                         NUMERIC(9,6),
  captured_at                     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE user_badges (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  badge_code  badge_code_enum NOT NULL,
  earned_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, badge_code)
);

CREATE TABLE user_environment_progress (
  user_id                 UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  environment             preferred_environment_enum NOT NULL,
  completed_quest_count   INT NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, environment)
);


-- ============================================================================
-- SECTION 7: Triggers
-- ============================================================================

-- reuse set_updated_at() ที่มีอยู่แล้วจาก schema เดิม
CREATE TRIGGER trg_user_programs_updated_at
  BEFORE UPDATE ON user_programs
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_main_quest_updated_at
  BEFORE UPDATE ON main_quest_instances
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_running_sessions_updated_at
  BEFORE UPDATE ON running_sessions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ---- trg_program_completion_check ----
-- เมื่อ main_quest_instances เปลี่ยนเป็น completed:
--   1) อัปเดต user_program_completion.completed_count
--   2) ถ้าทุก session_type ที่มี target_count ครบแล้ว → user_programs.status = 'completed'
CREATE OR REPLACE FUNCTION fn_program_completion_check()
RETURNS TRIGGER AS $$
DECLARE
  v_target SMALLINT;
  v_all_done BOOLEAN;
BEGIN
  IF NEW.status = 'completed' AND (OLD.status IS DISTINCT FROM 'completed') THEN

    SELECT program_total_target INTO v_target
    FROM session_type_specs s
    JOIN user_programs up ON up.program_template_id = s.program_template_id
    WHERE up.id = NEW.user_program_id
      AND s.session_type = NEW.session_type
      AND (s.phase_id IS NULL OR s.phase_id = NEW.phase_id)
    LIMIT 1;

    INSERT INTO user_program_completion (user_program_id, session_type, completed_count, target_count)
    VALUES (NEW.user_program_id, NEW.session_type, 1, v_target)
    ON CONFLICT (user_program_id, session_type)
    DO UPDATE SET completed_count = user_program_completion.completed_count + 1;

    SELECT bool_and(completed_count >= COALESCE(target_count, 0))
    INTO v_all_done
    FROM user_program_completion
    WHERE user_program_id = NEW.user_program_id
      AND target_count IS NOT NULL;

    IF v_all_done THEN
      UPDATE user_programs SET status = 'completed', updated_at = now()
      WHERE id = NEW.user_program_id AND status = 'active';
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_program_completion_check
  AFTER UPDATE ON main_quest_instances
  FOR EACH ROW EXECUTE FUNCTION fn_program_completion_check();


-- ---- trg_side_quest_badge_check ----
-- เมื่อ user_side_quest_instances เปลี่ยนเป็น completed:
--   1) +1 ที่ user_environment_progress
--   2) ถ้าครบ 5 → award badge เฉพาะ environment นั้น
CREATE OR REPLACE FUNCTION fn_side_quest_badge_check()
RETURNS TRIGGER AS $$
DECLARE
  v_env preferred_environment_enum;
  v_count INT;
  v_badge badge_code_enum;
BEGIN
  IF NEW.status = 'completed' AND (OLD.status IS DISTINCT FROM 'completed') THEN

    SELECT environment INTO v_env
    FROM side_quest_templates WHERE id = NEW.side_quest_template_id;

    INSERT INTO user_environment_progress (user_id, environment, completed_quest_count)
    VALUES (NEW.user_id, v_env, 1)
    ON CONFLICT (user_id, environment)
    DO UPDATE SET completed_quest_count = user_environment_progress.completed_quest_count + 1
    RETURNING completed_quest_count INTO v_count;

    IF v_count = 5 THEN
      v_badge := CASE v_env
        WHEN 'park' THEN 'park_regular'
        WHEN 'road' THEN 'road_runner'
        WHEN 'city' THEN 'city_explorer'
        WHEN 'treadmill' THEN 'treadmill_warrior'
        WHEN 'trail' THEN 'trail_blazer'
      END;

      INSERT INTO user_badges (user_id, badge_code)
      VALUES (NEW.user_id, v_badge)
      ON CONFLICT (user_id, badge_code) DO NOTHING;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_side_quest_badge_check
  AFTER UPDATE ON user_side_quest_instances
  FOR EACH ROW EXECUTE FUNCTION fn_side_quest_badge_check();


-- ---- trg_explorer_badge_check ----
-- เมื่อครบทุก 5 environment (แต่ละ environment completed_quest_count >= 5)
-- → award 'pacegasus_explorer'
CREATE OR REPLACE FUNCTION fn_explorer_badge_check()
RETURNS TRIGGER AS $$
DECLARE
  v_env_done_count INT;
BEGIN
  SELECT COUNT(*) INTO v_env_done_count
  FROM user_environment_progress
  WHERE user_id = NEW.user_id AND completed_quest_count >= 5;

  IF v_env_done_count = 5 THEN
    INSERT INTO user_badges (user_id, badge_code)
    VALUES (NEW.user_id, 'pacegasus_explorer')
    ON CONFLICT (user_id, badge_code) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_explorer_badge_check
  AFTER INSERT OR UPDATE ON user_environment_progress
  FOR EACH ROW EXECUTE FUNCTION fn_explorer_badge_check();


-- ============================================================================
-- SECTION 8: Seed — program_templates / phases / session_type_specs / rules
-- ============================================================================

-- ---- Beginner (single-phase, 6-10 สัปดาห์, sub 50) ----
WITH tpl AS (
  INSERT INTO program_templates (level, require_exp_level, goal_label, duration_weeks_min, duration_weeks_max)
  VALUES ('beginner', NULL, 'sub_50', 6, 10)
  RETURNING id
)
INSERT INTO session_type_specs (program_template_id, phase_id, session_type, unit, multiplier, weekly_cap, program_total_target, value_low, value_high, is_bonus)
SELECT id, NULL, 'easy', 'minutes', 1.00, 3, 20, 20, 30, false FROM tpl
UNION ALL
SELECT id, NULL, 'long_run', 'km', 1.00, 1, 10, 3, 4, false FROM tpl
UNION ALL
SELECT id, NULL, 'threshold', 'reps', 1.00, 1, NULL, 200, 200, true FROM tpl;  -- 200m x 4, bonus

INSERT INTO program_sequencing_rules (program_template_id, rule_type, session_type_a, session_type_b)
SELECT id, 'must_precede', 'easy', 'long_run' FROM program_templates WHERE level = 'beginner'
UNION ALL
SELECT id, 'rest_after', 'threshold', NULL FROM program_templates WHERE level = 'beginner';


-- ---- Lower Intermediate (goal 10k, 8-10 สัปดาห์, sub 1.40) ----
WITH tpl AS (
  INSERT INTO program_templates (level, require_exp_level, goal_label, duration_weeks_min, duration_weeks_max)
  VALUES ('lower_intermediate', 'beginner', '10k_sub_1.40', 8, 10)
  RETURNING id
),
phases AS (
  INSERT INTO program_phases (program_template_id, phase_code, phase_order)
  SELECT id, phase_code, phase_order FROM tpl,
    (VALUES ('base'::phase_code_enum,1), ('build'::phase_code_enum,2),
            ('peak'::phase_code_enum,3), ('taper_easy'::phase_code_enum,4),
            ('race'::phase_code_enum,5)) AS p(phase_code, phase_order)
  RETURNING id, phase_code, program_template_id
)
-- phase 1-3 (base/build/peak) ใช้ spec เดียวกัน (apply on phase 1-3)
INSERT INTO session_type_specs (program_template_id, phase_id, session_type, unit, multiplier, weekly_cap, program_total_target, value_low, value_high, is_bonus)
SELECT program_template_id, id, 'easy', 'minutes', 1.00, 2, 16, 30, 40, false FROM phases WHERE phase_code IN ('base','build','peak')
UNION ALL
SELECT program_template_id, id, 'long_run', 'km', 1.00, 1, 8, 6, 8, false FROM phases WHERE phase_code IN ('base','build','peak')
UNION ALL
SELECT program_template_id, id, 'tempo', 'minutes', 1.00, 1, 4, 10, 20, false FROM phases WHERE phase_code IN ('base','build','peak')
UNION ALL
SELECT program_template_id, id, 'vo2max', 'reps', 1.00, 1, 4, 200, 200, false FROM phases WHERE phase_code IN ('base','build','peak')
UNION ALL
-- phase 4.1 taper
SELECT program_template_id, id, 'easy', 'km', 1.00, 2, NULL, 4, 4, false FROM phases WHERE phase_code = 'taper_easy'
UNION ALL
SELECT program_template_id, id, 'tempo', 'minutes', 1.00, 1, NULL, 10, 10, false FROM phases WHERE phase_code = 'taper_easy'
UNION ALL
SELECT program_template_id, id, 'long_run', 'km', 1.00, 1, NULL, 6, 6, false FROM phases WHERE phase_code = 'taper_easy'
UNION ALL
-- phase 4.2 race week
SELECT program_template_id, id, 'easy', 'km', 1.00, 4, NULL, 3, 4, false FROM phases WHERE phase_code = 'race';

INSERT INTO program_sequencing_rules (program_template_id, rule_type, session_type_a, session_type_b)
SELECT id, 'cannot_adjacent', 'vo2max', 'tempo' FROM program_templates WHERE level = 'lower_intermediate'
UNION ALL
SELECT id, 'cannot_adjacent', 'vo2max', 'long_run' FROM program_templates WHERE level = 'lower_intermediate'
UNION ALL
SELECT id, 'cannot_adjacent', 'tempo', 'long_run' FROM program_templates WHERE level = 'lower_intermediate';


-- ---- Upper Intermediate (goal 21k, 10-12 สัปดาห์, sub 3.30) ----
WITH tpl AS (
  INSERT INTO program_templates (level, require_exp_level, goal_label, duration_weeks_min, duration_weeks_max)
  VALUES ('upper_intermediate', 'lower_intermediate', '21k_sub_3.30', 10, 12)
  RETURNING id
),
phases AS (
  INSERT INTO program_phases (program_template_id, phase_code, phase_order)
  SELECT id, phase_code, phase_order FROM tpl,
    (VALUES ('base'::phase_code_enum,1), ('build'::phase_code_enum,2),
            ('peak'::phase_code_enum,3), ('taper_easy'::phase_code_enum,4),
            ('race'::phase_code_enum,5)) AS p(phase_code, phase_order)
  RETURNING id, phase_code, program_template_id
)
INSERT INTO session_type_specs (program_template_id, phase_id, session_type, unit, multiplier, weekly_cap, program_total_target, value_low, value_high, is_bonus)
SELECT program_template_id, id, 'easy', 'minutes', 1.00, 2, 20, 40, 50, false FROM phases WHERE phase_code IN ('base','build','peak')
UNION ALL
SELECT program_template_id, id, 'long_run', 'km', 1.00, 1, 10, 12, 16, false FROM phases WHERE phase_code IN ('base','build','peak')
UNION ALL
SELECT program_template_id, id, 'tempo', 'minutes', 1.00, 1, 5, 20, 30, false FROM phases WHERE phase_code IN ('base','build','peak')
UNION ALL
SELECT program_template_id, id, 'vo2max', 'reps', 1.00, 1, 5, 400, 400, false FROM phases WHERE phase_code IN ('base','build','peak')
UNION ALL
SELECT program_template_id, id, 'easy', 'km', 1.00, 2, NULL, 8, 8, false FROM phases WHERE phase_code = 'taper_easy'
UNION ALL
SELECT program_template_id, id, 'tempo', 'minutes', 1.00, 1, NULL, 10, 10, false FROM phases WHERE phase_code = 'taper_easy'
UNION ALL
SELECT program_template_id, id, 'long_run', 'km', 1.00, 1, NULL, 12, 12, false FROM phases WHERE phase_code = 'taper_easy'
UNION ALL
SELECT program_template_id, id, 'easy', 'km', 1.00, 4, NULL, 3, 5, false FROM phases WHERE phase_code = 'race';

INSERT INTO program_sequencing_rules (program_template_id, rule_type, session_type_a, session_type_b)
SELECT id, 'cannot_adjacent', 'vo2max', 'tempo' FROM program_templates WHERE level = 'upper_intermediate'
UNION ALL
SELECT id, 'cannot_adjacent', 'vo2max', 'long_run' FROM program_templates WHERE level = 'upper_intermediate'
UNION ALL
SELECT id, 'cannot_adjacent', 'tempo', 'long_run' FROM program_templates WHERE level = 'upper_intermediate';


-- ============================================================================
-- หมายเหตุ:
-- 1. ค่า multiplier ตั้งต้นเป็น 1.00 ทุกแถว (placeholder) — ต้องปรับตามสูตรจริง
--    ที่จะใช้คูณกับ user_program_baselines.base_value ในภายหลัง (ยังไม่ได้ล็อก
--    สูตรคำนวณ multiplier ที่แท้จริงในบทสนทนานี้)
-- 2. session_type_specs ที่ NULL phase_id ใช้เฉพาะ Beginner (single-phase program)
-- 3. side_quest_templates (400 แถว) อยู่ในไฟล์ 002_seed_side_quests.sql แยกต่างหาก
--    เพราะ generate ด้วย Python script จากชุดข้อมูลเดียวกับ pacegasus_side_quests.md
-- ============================================================================
-- ============================================================================
-- Pacegasus — Seed: side_quest_templates (400 rows)
-- Generated by generate_side_quest_seed.py — mirrors pacegasus_side_quests.md
-- ============================================================================

INSERT INTO side_quest_templates (environment, training_type, title, description, target_object, mechanic_type, km_per, cap_count, fixed_count, coin_reward_base) VALUES
  ('park', 'easy', 'ตามหาหมา', 'ถ่ายรูปหมาที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ตัว ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ตัว) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'หมา', 'collect_distance', 2, 3, NULL, 10),
  ('park', 'long_run', 'สะสมหมาระยะไกล', 'เก็บสะสมภาพหมาตลอดเส้นทาง Long Run (ถ่าย 1 ตัว ทุก 3 กม. สูงสุด 6 ตัว) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'หมา', 'collect_distance', 3, 6, NULL, 10),
  ('park', 'tempo', 'เร่งจังหวะที่หมา', 'ทุกครั้งที่พบหมาระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'หมา', 'pace_trigger', NULL, NULL, 3, 10),
  ('park', 'interval', 'สปรินต์ข้ามหมา', 'ใช้หมาเป็นจุด Sprint Marker วิ่งเร็วจากหมาหนึ่งไปอีกหมา สลับพัก ทำให้ครบ 4 รอบ', 'หมา', 'sprint_marker', NULL, NULL, 4, 10),
  ('park', 'easy', 'ตามหาแมว', 'ถ่ายรูปแมวที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ตัว ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ตัว) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'แมว', 'collect_distance', 2, 3, NULL, 10),
  ('park', 'long_run', 'สะสมแมวระยะไกล', 'เก็บสะสมภาพแมวตลอดเส้นทาง Long Run (ถ่าย 1 ตัว ทุก 3 กม. สูงสุด 6 ตัว) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'แมว', 'collect_distance', 3, 6, NULL, 10),
  ('park', 'tempo', 'เร่งจังหวะที่แมว', 'ทุกครั้งที่พบแมวระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'แมว', 'pace_trigger', NULL, NULL, 3, 10),
  ('park', 'interval', 'สปรินต์ข้ามแมว', 'ใช้แมวเป็นจุด Sprint Marker วิ่งเร็วจากแมวหนึ่งไปอีกแมว สลับพัก ทำให้ครบ 4 รอบ', 'แมว', 'sprint_marker', NULL, NULL, 4, 10),
  ('park', 'easy', 'ตามหานกพิราบ', 'ถ่ายรูปนกพิราบที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ตัว ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ตัว) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'นกพิราบ', 'collect_distance', 2, 3, NULL, 10),
  ('park', 'long_run', 'สะสมนกพิราบระยะไกล', 'เก็บสะสมภาพนกพิราบตลอดเส้นทาง Long Run (ถ่าย 1 ตัว ทุก 3 กม. สูงสุด 6 ตัว) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'นกพิราบ', 'collect_distance', 3, 6, NULL, 10),
  ('park', 'tempo', 'เร่งจังหวะที่นกพิราบ', 'ทุกครั้งที่พบนกพิราบระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'นกพิราบ', 'pace_trigger', NULL, NULL, 3, 10),
  ('park', 'interval', 'สปรินต์ข้ามนกพิราบ', 'ใช้นกพิราบเป็นจุด Sprint Marker วิ่งเร็วจากนกพิราบหนึ่งไปอีกนกพิราบ สลับพัก ทำให้ครบ 4 รอบ', 'นกพิราบ', 'sprint_marker', NULL, NULL, 4, 10),
  ('park', 'easy', 'ตามหากระรอก', 'ถ่ายรูปกระรอกที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ตัว ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ตัว) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'กระรอก', 'collect_distance', 2, 3, NULL, 10),
  ('park', 'long_run', 'สะสมกระรอกระยะไกล', 'เก็บสะสมภาพกระรอกตลอดเส้นทาง Long Run (ถ่าย 1 ตัว ทุก 3 กม. สูงสุด 6 ตัว) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'กระรอก', 'collect_distance', 3, 6, NULL, 10),
  ('park', 'tempo', 'เร่งจังหวะที่กระรอก', 'ทุกครั้งที่พบกระรอกระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'กระรอก', 'pace_trigger', NULL, NULL, 3, 10),
  ('park', 'interval', 'สปรินต์ข้ามกระรอก', 'ใช้กระรอกเป็นจุด Sprint Marker วิ่งเร็วจากกระรอกหนึ่งไปอีกกระรอก สลับพัก ทำให้ครบ 4 รอบ', 'กระรอก', 'sprint_marker', NULL, NULL, 4, 10),
  ('park', 'easy', 'ตามหาม้านั่ง', 'ถ่ายรูปม้านั่งที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ตัว ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ตัว) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ม้านั่ง', 'collect_distance', 2, 3, NULL, 10),
  ('park', 'long_run', 'สะสมม้านั่งระยะไกล', 'เก็บสะสมภาพม้านั่งตลอดเส้นทาง Long Run (ถ่าย 1 ตัว ทุก 3 กม. สูงสุด 6 ตัว) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ม้านั่ง', 'collect_distance', 3, 6, NULL, 10),
  ('park', 'tempo', 'เร่งจังหวะที่ม้านั่ง', 'ทุกครั้งที่พบม้านั่งระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ม้านั่ง', 'pace_trigger', NULL, NULL, 3, 10),
  ('park', 'interval', 'สปรินต์ข้ามม้านั่ง', 'ใช้ม้านั่งเป็นจุด Sprint Marker วิ่งเร็วจากม้านั่งหนึ่งไปอีกม้านั่ง สลับพัก ทำให้ครบ 4 รอบ', 'ม้านั่ง', 'sprint_marker', NULL, NULL, 4, 10),
  ('park', 'easy', 'ตามหาต้นไม้ใหญ่', 'ถ่ายรูปต้นไม้ใหญ่ที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ต้น ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ต้น) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ต้นไม้ใหญ่', 'collect_distance', 2, 3, NULL, 10),
  ('park', 'long_run', 'สะสมต้นไม้ใหญ่ระยะไกล', 'เก็บสะสมภาพต้นไม้ใหญ่ตลอดเส้นทาง Long Run (ถ่าย 1 ต้น ทุก 3 กม. สูงสุด 6 ต้น) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ต้นไม้ใหญ่', 'collect_distance', 3, 6, NULL, 10),
  ('park', 'tempo', 'เร่งจังหวะที่ต้นไม้ใหญ่', 'ทุกครั้งที่พบต้นไม้ใหญ่ระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ต้นไม้ใหญ่', 'pace_trigger', NULL, NULL, 3, 10),
  ('park', 'interval', 'สปรินต์ข้ามต้นไม้ใหญ่', 'ใช้ต้นไม้ใหญ่เป็นจุด Sprint Marker วิ่งเร็วจากต้นไม้ใหญ่หนึ่งไปอีกต้นไม้ใหญ่ สลับพัก ทำให้ครบ 4 รอบ', 'ต้นไม้ใหญ่', 'sprint_marker', NULL, NULL, 4, 10),
  ('park', 'easy', 'ตามหาดอกไม้', 'ถ่ายรูปดอกไม้ที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ดอก ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ดอก) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ดอกไม้', 'collect_distance', 2, 3, NULL, 10),
  ('park', 'long_run', 'สะสมดอกไม้ระยะไกล', 'เก็บสะสมภาพดอกไม้ตลอดเส้นทาง Long Run (ถ่าย 1 ดอก ทุก 3 กม. สูงสุด 6 ดอก) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ดอกไม้', 'collect_distance', 3, 6, NULL, 10),
  ('park', 'tempo', 'เร่งจังหวะที่ดอกไม้', 'ทุกครั้งที่พบดอกไม้ระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ดอกไม้', 'pace_trigger', NULL, NULL, 3, 10),
  ('park', 'interval', 'สปรินต์ข้ามดอกไม้', 'ใช้ดอกไม้เป็นจุด Sprint Marker วิ่งเร็วจากดอกไม้หนึ่งไปอีกดอกไม้ สลับพัก ทำให้ครบ 4 รอบ', 'ดอกไม้', 'sprint_marker', NULL, NULL, 4, 10),
  ('park', 'easy', 'ตามหาคนวิ่งสวนทาง', 'ถ่ายรูปคนวิ่งสวนทางที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 คน ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 คน) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'คนวิ่งสวนทาง', 'collect_distance', 2, 3, NULL, 10),
  ('park', 'long_run', 'สะสมคนวิ่งสวนทางระยะไกล', 'เก็บสะสมภาพคนวิ่งสวนทางตลอดเส้นทาง Long Run (ถ่าย 1 คน ทุก 3 กม. สูงสุด 6 คน) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'คนวิ่งสวนทาง', 'collect_distance', 3, 6, NULL, 10),
  ('park', 'tempo', 'เร่งจังหวะที่คนวิ่งสวนทาง', 'ทุกครั้งที่พบคนวิ่งสวนทางระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'คนวิ่งสวนทาง', 'pace_trigger', NULL, NULL, 3, 10),
  ('park', 'interval', 'สปรินต์ข้ามคนวิ่งสวนทาง', 'ใช้คนวิ่งสวนทางเป็นจุด Sprint Marker วิ่งเร็วจากคนวิ่งสวนทางหนึ่งไปอีกคนวิ่งสวนทาง สลับพัก ทำให้ครบ 4 รอบ', 'คนวิ่งสวนทาง', 'sprint_marker', NULL, NULL, 4, 10),
  ('park', 'easy', 'ตามหาจักรยาน', 'ถ่ายรูปจักรยานที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 คัน ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 คัน) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'จักรยาน', 'collect_distance', 2, 3, NULL, 10),
  ('park', 'long_run', 'สะสมจักรยานระยะไกล', 'เก็บสะสมภาพจักรยานตลอดเส้นทาง Long Run (ถ่าย 1 คัน ทุก 3 กม. สูงสุด 6 คัน) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'จักรยาน', 'collect_distance', 3, 6, NULL, 10),
  ('park', 'tempo', 'เร่งจังหวะที่จักรยาน', 'ทุกครั้งที่พบจักรยานระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'จักรยาน', 'pace_trigger', NULL, NULL, 3, 10),
  ('park', 'interval', 'สปรินต์ข้ามจักรยาน', 'ใช้จักรยานเป็นจุด Sprint Marker วิ่งเร็วจากจักรยานหนึ่งไปอีกจักรยาน สลับพัก ทำให้ครบ 4 รอบ', 'จักรยาน', 'sprint_marker', NULL, NULL, 4, 10),
  ('park', 'easy', 'ตามหาเครื่องเล่นสนามเด็กเล่น', 'ถ่ายรูปเครื่องเล่นสนามเด็กเล่นที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ชิ้น ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ชิ้น) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'เครื่องเล่นสนามเด็กเล่น', 'collect_distance', 2, 3, NULL, 10),
  ('park', 'long_run', 'สะสมเครื่องเล่นสนามเด็กเล่นระยะไกล', 'เก็บสะสมภาพเครื่องเล่นสนามเด็กเล่นตลอดเส้นทาง Long Run (ถ่าย 1 ชิ้น ทุก 3 กม. สูงสุด 6 ชิ้น) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'เครื่องเล่นสนามเด็กเล่น', 'collect_distance', 3, 6, NULL, 10),
  ('park', 'tempo', 'เร่งจังหวะที่เครื่องเล่นสนามเด็กเล่น', 'ทุกครั้งที่พบเครื่องเล่นสนามเด็กเล่นระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'เครื่องเล่นสนามเด็กเล่น', 'pace_trigger', NULL, NULL, 3, 10),
  ('park', 'interval', 'สปรินต์ข้ามเครื่องเล่นสนามเด็กเล่น', 'ใช้เครื่องเล่นสนามเด็กเล่นเป็นจุด Sprint Marker วิ่งเร็วจากเครื่องเล่นสนามเด็กเล่นหนึ่งไปอีกเครื่องเล่นสนามเด็กเล่น สลับพัก ทำให้ครบ 4 รอบ', 'เครื่องเล่นสนามเด็กเล่น', 'sprint_marker', NULL, NULL, 4, 10),
  ('park', 'easy', 'ตามหาบ่อน้ำ/สระ', 'ถ่ายรูปบ่อน้ำ/สระที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 แห่ง ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 แห่ง) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'บ่อน้ำ/สระ', 'collect_distance', 2, 3, NULL, 10),
  ('park', 'long_run', 'สะสมบ่อน้ำ/สระระยะไกล', 'เก็บสะสมภาพบ่อน้ำ/สระตลอดเส้นทาง Long Run (ถ่าย 1 แห่ง ทุก 3 กม. สูงสุด 6 แห่ง) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'บ่อน้ำ/สระ', 'collect_distance', 3, 6, NULL, 10),
  ('park', 'tempo', 'เร่งจังหวะที่บ่อน้ำ/สระ', 'ทุกครั้งที่พบบ่อน้ำ/สระระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'บ่อน้ำ/สระ', 'pace_trigger', NULL, NULL, 3, 10),
  ('park', 'interval', 'สปรินต์ข้ามบ่อน้ำ/สระ', 'ใช้บ่อน้ำ/สระเป็นจุด Sprint Marker วิ่งเร็วจากบ่อน้ำ/สระหนึ่งไปอีกบ่อน้ำ/สระ สลับพัก ทำให้ครบ 4 รอบ', 'บ่อน้ำ/สระ', 'sprint_marker', NULL, NULL, 4, 10),
  ('park', 'easy', 'ตามหารถเข็นเด็ก', 'ถ่ายรูปรถเข็นเด็กที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 คัน ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 คัน) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'รถเข็นเด็ก', 'collect_distance', 2, 3, NULL, 10),
  ('park', 'long_run', 'สะสมรถเข็นเด็กระยะไกล', 'เก็บสะสมภาพรถเข็นเด็กตลอดเส้นทาง Long Run (ถ่าย 1 คัน ทุก 3 กม. สูงสุด 6 คัน) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'รถเข็นเด็ก', 'collect_distance', 3, 6, NULL, 10),
  ('park', 'tempo', 'เร่งจังหวะที่รถเข็นเด็ก', 'ทุกครั้งที่พบรถเข็นเด็กระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'รถเข็นเด็ก', 'pace_trigger', NULL, NULL, 3, 10),
  ('park', 'interval', 'สปรินต์ข้ามรถเข็นเด็ก', 'ใช้รถเข็นเด็กเป็นจุด Sprint Marker วิ่งเร็วจากรถเข็นเด็กหนึ่งไปอีกรถเข็นเด็ก สลับพัก ทำให้ครบ 4 รอบ', 'รถเข็นเด็ก', 'sprint_marker', NULL, NULL, 4, 10),
  ('park', 'easy', 'ตามหาคนเล่นโยคะ/แอโรบิค', 'ถ่ายรูปคนเล่นโยคะ/แอโรบิคที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 คน ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 คน) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'คนเล่นโยคะ/แอโรบิค', 'collect_distance', 2, 3, NULL, 10),
  ('park', 'long_run', 'สะสมคนเล่นโยคะ/แอโรบิคระยะไกล', 'เก็บสะสมภาพคนเล่นโยคะ/แอโรบิคตลอดเส้นทาง Long Run (ถ่าย 1 คน ทุก 3 กม. สูงสุด 6 คน) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'คนเล่นโยคะ/แอโรบิค', 'collect_distance', 3, 6, NULL, 10),
  ('park', 'tempo', 'เร่งจังหวะที่คนเล่นโยคะ/แอโรบิค', 'ทุกครั้งที่พบคนเล่นโยคะ/แอโรบิคระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'คนเล่นโยคะ/แอโรบิค', 'pace_trigger', NULL, NULL, 3, 10),
  ('park', 'interval', 'สปรินต์ข้ามคนเล่นโยคะ/แอโรบิค', 'ใช้คนเล่นโยคะ/แอโรบิคเป็นจุด Sprint Marker วิ่งเร็วจากคนเล่นโยคะ/แอโรบิคหนึ่งไปอีกคนเล่นโยคะ/แอโรบิค สลับพัก ทำให้ครบ 4 รอบ', 'คนเล่นโยคะ/แอโรบิค', 'sprint_marker', NULL, NULL, 4, 10),
  ('park', 'easy', 'ตามหาศาลาพักผ่อน', 'ถ่ายรูปศาลาพักผ่อนที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 หลัง ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 หลัง) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ศาลาพักผ่อน', 'collect_distance', 2, 3, NULL, 10),
  ('park', 'long_run', 'สะสมศาลาพักผ่อนระยะไกล', 'เก็บสะสมภาพศาลาพักผ่อนตลอดเส้นทาง Long Run (ถ่าย 1 หลัง ทุก 3 กม. สูงสุด 6 หลัง) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ศาลาพักผ่อน', 'collect_distance', 3, 6, NULL, 10),
  ('park', 'tempo', 'เร่งจังหวะที่ศาลาพักผ่อน', 'ทุกครั้งที่พบศาลาพักผ่อนระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ศาลาพักผ่อน', 'pace_trigger', NULL, NULL, 3, 10),
  ('park', 'interval', 'สปรินต์ข้ามศาลาพักผ่อน', 'ใช้ศาลาพักผ่อนเป็นจุด Sprint Marker วิ่งเร็วจากศาลาพักผ่อนหนึ่งไปอีกศาลาพักผ่อน สลับพัก ทำให้ครบ 4 รอบ', 'ศาลาพักผ่อน', 'sprint_marker', NULL, NULL, 4, 10),
  ('park', 'easy', 'ตามหาป้ายชื่อสวน', 'ถ่ายรูปป้ายชื่อสวนที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ป้าย ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ป้าย) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ป้ายชื่อสวน', 'collect_distance', 2, 3, NULL, 10),
  ('park', 'long_run', 'สะสมป้ายชื่อสวนระยะไกล', 'เก็บสะสมภาพป้ายชื่อสวนตลอดเส้นทาง Long Run (ถ่าย 1 ป้าย ทุก 3 กม. สูงสุด 6 ป้าย) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ป้ายชื่อสวน', 'collect_distance', 3, 6, NULL, 10),
  ('park', 'tempo', 'เร่งจังหวะที่ป้ายชื่อสวน', 'ทุกครั้งที่พบป้ายชื่อสวนระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ป้ายชื่อสวน', 'pace_trigger', NULL, NULL, 3, 10),
  ('park', 'interval', 'สปรินต์ข้ามป้ายชื่อสวน', 'ใช้ป้ายชื่อสวนเป็นจุด Sprint Marker วิ่งเร็วจากป้ายชื่อสวนหนึ่งไปอีกป้ายชื่อสวน สลับพัก ทำให้ครบ 4 รอบ', 'ป้ายชื่อสวน', 'sprint_marker', NULL, NULL, 4, 10),
  ('park', 'easy', 'ตามหาราวยืดเหยียดกล้ามเนื้อ', 'ถ่ายรูปราวยืดเหยียดกล้ามเนื้อที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 จุด ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 จุด) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ราวยืดเหยียดกล้ามเนื้อ', 'collect_distance', 2, 3, NULL, 10),
  ('park', 'long_run', 'สะสมราวยืดเหยียดกล้ามเนื้อระยะไกล', 'เก็บสะสมภาพราวยืดเหยียดกล้ามเนื้อตลอดเส้นทาง Long Run (ถ่าย 1 จุด ทุก 3 กม. สูงสุด 6 จุด) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ราวยืดเหยียดกล้ามเนื้อ', 'collect_distance', 3, 6, NULL, 10),
  ('park', 'tempo', 'เร่งจังหวะที่ราวยืดเหยียดกล้ามเนื้อ', 'ทุกครั้งที่พบราวยืดเหยียดกล้ามเนื้อระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ราวยืดเหยียดกล้ามเนื้อ', 'pace_trigger', NULL, NULL, 3, 10),
  ('park', 'interval', 'สปรินต์ข้ามราวยืดเหยียดกล้ามเนื้อ', 'ใช้ราวยืดเหยียดกล้ามเนื้อเป็นจุด Sprint Marker วิ่งเร็วจากราวยืดเหยียดกล้ามเนื้อหนึ่งไปอีกราวยืดเหยียดกล้ามเนื้อ สลับพัก ทำให้ครบ 4 รอบ', 'ราวยืดเหยียดกล้ามเนื้อ', 'sprint_marker', NULL, NULL, 4, 10),
  ('park', 'easy', 'ตามหาถังขยะสีเขียว', 'ถ่ายรูปถังขยะสีเขียวที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ใบ ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ใบ) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ถังขยะสีเขียว', 'collect_distance', 2, 3, NULL, 10),
  ('park', 'long_run', 'สะสมถังขยะสีเขียวระยะไกล', 'เก็บสะสมภาพถังขยะสีเขียวตลอดเส้นทาง Long Run (ถ่าย 1 ใบ ทุก 3 กม. สูงสุด 6 ใบ) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ถังขยะสีเขียว', 'collect_distance', 3, 6, NULL, 10),
  ('park', 'tempo', 'เร่งจังหวะที่ถังขยะสีเขียว', 'ทุกครั้งที่พบถังขยะสีเขียวระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ถังขยะสีเขียว', 'pace_trigger', NULL, NULL, 3, 10),
  ('park', 'interval', 'สปรินต์ข้ามถังขยะสีเขียว', 'ใช้ถังขยะสีเขียวเป็นจุด Sprint Marker วิ่งเร็วจากถังขยะสีเขียวหนึ่งไปอีกถังขยะสีเขียว สลับพัก ทำให้ครบ 4 รอบ', 'ถังขยะสีเขียว', 'sprint_marker', NULL, NULL, 4, 10),
  ('park', 'easy', 'ตามหาทางจักรยานในสวน', 'ถ่ายรูปทางจักรยานในสวนที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 จุด ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 จุด) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ทางจักรยานในสวน', 'collect_distance', 2, 3, NULL, 10),
  ('park', 'long_run', 'สะสมทางจักรยานในสวนระยะไกล', 'เก็บสะสมภาพทางจักรยานในสวนตลอดเส้นทาง Long Run (ถ่าย 1 จุด ทุก 3 กม. สูงสุด 6 จุด) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ทางจักรยานในสวน', 'collect_distance', 3, 6, NULL, 10),
  ('park', 'tempo', 'เร่งจังหวะที่ทางจักรยานในสวน', 'ทุกครั้งที่พบทางจักรยานในสวนระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ทางจักรยานในสวน', 'pace_trigger', NULL, NULL, 3, 10),
  ('park', 'interval', 'สปรินต์ข้ามทางจักรยานในสวน', 'ใช้ทางจักรยานในสวนเป็นจุด Sprint Marker วิ่งเร็วจากทางจักรยานในสวนหนึ่งไปอีกทางจักรยานในสวน สลับพัก ทำให้ครบ 4 รอบ', 'ทางจักรยานในสวน', 'sprint_marker', NULL, NULL, 4, 10),
  ('park', 'easy', 'ตามหารูปปั้น/อนุสาวรีย์เล็กๆ', 'ถ่ายรูปรูปปั้น/อนุสาวรีย์เล็กๆที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ชิ้น ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ชิ้น) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'รูปปั้น/อนุสาวรีย์เล็กๆ', 'collect_distance', 2, 3, NULL, 10),
  ('park', 'long_run', 'สะสมรูปปั้น/อนุสาวรีย์เล็กๆระยะไกล', 'เก็บสะสมภาพรูปปั้น/อนุสาวรีย์เล็กๆตลอดเส้นทาง Long Run (ถ่าย 1 ชิ้น ทุก 3 กม. สูงสุด 6 ชิ้น) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'รูปปั้น/อนุสาวรีย์เล็กๆ', 'collect_distance', 3, 6, NULL, 10),
  ('park', 'tempo', 'เร่งจังหวะที่รูปปั้น/อนุสาวรีย์เล็กๆ', 'ทุกครั้งที่พบรูปปั้น/อนุสาวรีย์เล็กๆระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'รูปปั้น/อนุสาวรีย์เล็กๆ', 'pace_trigger', NULL, NULL, 3, 10),
  ('park', 'interval', 'สปรินต์ข้ามรูปปั้น/อนุสาวรีย์เล็กๆ', 'ใช้รูปปั้น/อนุสาวรีย์เล็กๆเป็นจุด Sprint Marker วิ่งเร็วจากรูปปั้น/อนุสาวรีย์เล็กๆหนึ่งไปอีกรูปปั้น/อนุสาวรีย์เล็กๆ สลับพัก ทำให้ครบ 4 รอบ', 'รูปปั้น/อนุสาวรีย์เล็กๆ', 'sprint_marker', NULL, NULL, 4, 10),
  ('park', 'easy', 'ตามหาสะพานเล็กในสวน', 'ถ่ายรูปสะพานเล็กในสวนที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 แห่ง ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 แห่ง) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'สะพานเล็กในสวน', 'collect_distance', 2, 3, NULL, 10),
  ('park', 'long_run', 'สะสมสะพานเล็กในสวนระยะไกล', 'เก็บสะสมภาพสะพานเล็กในสวนตลอดเส้นทาง Long Run (ถ่าย 1 แห่ง ทุก 3 กม. สูงสุด 6 แห่ง) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'สะพานเล็กในสวน', 'collect_distance', 3, 6, NULL, 10),
  ('park', 'tempo', 'เร่งจังหวะที่สะพานเล็กในสวน', 'ทุกครั้งที่พบสะพานเล็กในสวนระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'สะพานเล็กในสวน', 'pace_trigger', NULL, NULL, 3, 10),
  ('park', 'interval', 'สปรินต์ข้ามสะพานเล็กในสวน', 'ใช้สะพานเล็กในสวนเป็นจุด Sprint Marker วิ่งเร็วจากสะพานเล็กในสวนหนึ่งไปอีกสะพานเล็กในสวน สลับพัก ทำให้ครบ 4 รอบ', 'สะพานเล็กในสวน', 'sprint_marker', NULL, NULL, 4, 10),
  ('road', 'easy', 'ตามหารถสีแดง', 'ถ่ายรูปรถสีแดงที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 คัน ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 คัน) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'รถสีแดง', 'collect_distance', 2, 3, NULL, 10),
  ('road', 'long_run', 'สะสมรถสีแดงระยะไกล', 'เก็บสะสมภาพรถสีแดงตลอดเส้นทาง Long Run (ถ่าย 1 คัน ทุก 3 กม. สูงสุด 6 คัน) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'รถสีแดง', 'collect_distance', 3, 6, NULL, 10),
  ('road', 'tempo', 'เร่งจังหวะที่รถสีแดง', 'ทุกครั้งที่พบรถสีแดงระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'รถสีแดง', 'pace_trigger', NULL, NULL, 3, 10),
  ('road', 'interval', 'สปรินต์ข้ามรถสีแดง', 'ใช้รถสีแดงเป็นจุด Sprint Marker วิ่งเร็วจากรถสีแดงหนึ่งไปอีกรถสีแดง สลับพัก ทำให้ครบ 4 รอบ', 'รถสีแดง', 'sprint_marker', NULL, NULL, 4, 10),
  ('road', 'easy', 'ตามหารถสีขาว', 'ถ่ายรูปรถสีขาวที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 คัน ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 คัน) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'รถสีขาว', 'collect_distance', 2, 3, NULL, 10),
  ('road', 'long_run', 'สะสมรถสีขาวระยะไกล', 'เก็บสะสมภาพรถสีขาวตลอดเส้นทาง Long Run (ถ่าย 1 คัน ทุก 3 กม. สูงสุด 6 คัน) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'รถสีขาว', 'collect_distance', 3, 6, NULL, 10),
  ('road', 'tempo', 'เร่งจังหวะที่รถสีขาว', 'ทุกครั้งที่พบรถสีขาวระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'รถสีขาว', 'pace_trigger', NULL, NULL, 3, 10),
  ('road', 'interval', 'สปรินต์ข้ามรถสีขาว', 'ใช้รถสีขาวเป็นจุด Sprint Marker วิ่งเร็วจากรถสีขาวหนึ่งไปอีกรถสีขาว สลับพัก ทำให้ครบ 4 รอบ', 'รถสีขาว', 'sprint_marker', NULL, NULL, 4, 10),
  ('road', 'easy', 'ตามหามอเตอร์ไซค์รับจ้าง (เสื้อวิน)', 'ถ่ายรูปมอเตอร์ไซค์รับจ้าง (เสื้อวิน)ที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 คัน ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 คัน) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'มอเตอร์ไซค์รับจ้าง (เสื้อวิน)', 'collect_distance', 2, 3, NULL, 10),
  ('road', 'long_run', 'สะสมมอเตอร์ไซค์รับจ้าง (เสื้อวิน)ระยะไกล', 'เก็บสะสมภาพมอเตอร์ไซค์รับจ้าง (เสื้อวิน)ตลอดเส้นทาง Long Run (ถ่าย 1 คัน ทุก 3 กม. สูงสุด 6 คัน) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'มอเตอร์ไซค์รับจ้าง (เสื้อวิน)', 'collect_distance', 3, 6, NULL, 10),
  ('road', 'tempo', 'เร่งจังหวะที่มอเตอร์ไซค์รับจ้าง (เสื้อวิน)', 'ทุกครั้งที่พบมอเตอร์ไซค์รับจ้าง (เสื้อวิน)ระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'มอเตอร์ไซค์รับจ้าง (เสื้อวิน)', 'pace_trigger', NULL, NULL, 3, 10),
  ('road', 'interval', 'สปรินต์ข้ามมอเตอร์ไซค์รับจ้าง (เสื้อวิน)', 'ใช้มอเตอร์ไซค์รับจ้าง (เสื้อวิน)เป็นจุด Sprint Marker วิ่งเร็วจากมอเตอร์ไซค์รับจ้าง (เสื้อวิน)หนึ่งไปอีกมอเตอร์ไซค์รับจ้าง (เสื้อวิน) สลับพัก ทำให้ครบ 4 รอบ', 'มอเตอร์ไซค์รับจ้าง (เสื้อวิน)', 'sprint_marker', NULL, NULL, 4, 10),
  ('road', 'easy', 'ตามหาร้านสะดวกซื้อ', 'ถ่ายรูปร้านสะดวกซื้อที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ร้าน ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ร้าน) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ร้านสะดวกซื้อ', 'collect_distance', 2, 3, NULL, 10),
  ('road', 'long_run', 'สะสมร้านสะดวกซื้อระยะไกล', 'เก็บสะสมภาพร้านสะดวกซื้อตลอดเส้นทาง Long Run (ถ่าย 1 ร้าน ทุก 3 กม. สูงสุด 6 ร้าน) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ร้านสะดวกซื้อ', 'collect_distance', 3, 6, NULL, 10),
  ('road', 'tempo', 'เร่งจังหวะที่ร้านสะดวกซื้อ', 'ทุกครั้งที่พบร้านสะดวกซื้อระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ร้านสะดวกซื้อ', 'pace_trigger', NULL, NULL, 3, 10),
  ('road', 'interval', 'สปรินต์ข้ามร้านสะดวกซื้อ', 'ใช้ร้านสะดวกซื้อเป็นจุด Sprint Marker วิ่งเร็วจากร้านสะดวกซื้อหนึ่งไปอีกร้านสะดวกซื้อ สลับพัก ทำให้ครบ 4 รอบ', 'ร้านสะดวกซื้อ', 'sprint_marker', NULL, NULL, 4, 10),
  ('road', 'easy', 'ตามหาป้ายรถเมล์', 'ถ่ายรูปป้ายรถเมล์ที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ป้าย ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ป้าย) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ป้ายรถเมล์', 'collect_distance', 2, 3, NULL, 10),
  ('road', 'long_run', 'สะสมป้ายรถเมล์ระยะไกล', 'เก็บสะสมภาพป้ายรถเมล์ตลอดเส้นทาง Long Run (ถ่าย 1 ป้าย ทุก 3 กม. สูงสุด 6 ป้าย) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ป้ายรถเมล์', 'collect_distance', 3, 6, NULL, 10),
  ('road', 'tempo', 'เร่งจังหวะที่ป้ายรถเมล์', 'ทุกครั้งที่พบป้ายรถเมล์ระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ป้ายรถเมล์', 'pace_trigger', NULL, NULL, 3, 10),
  ('road', 'interval', 'สปรินต์ข้ามป้ายรถเมล์', 'ใช้ป้ายรถเมล์เป็นจุด Sprint Marker วิ่งเร็วจากป้ายรถเมล์หนึ่งไปอีกป้ายรถเมล์ สลับพัก ทำให้ครบ 4 รอบ', 'ป้ายรถเมล์', 'sprint_marker', NULL, NULL, 4, 10),
  ('road', 'easy', 'ตามหาสะพานลอย', 'ถ่ายรูปสะพานลอยที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 แห่ง ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 แห่ง) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'สะพานลอย', 'collect_distance', 2, 3, NULL, 10),
  ('road', 'long_run', 'สะสมสะพานลอยระยะไกล', 'เก็บสะสมภาพสะพานลอยตลอดเส้นทาง Long Run (ถ่าย 1 แห่ง ทุก 3 กม. สูงสุด 6 แห่ง) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'สะพานลอย', 'collect_distance', 3, 6, NULL, 10),
  ('road', 'tempo', 'เร่งจังหวะที่สะพานลอย', 'ทุกครั้งที่พบสะพานลอยระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'สะพานลอย', 'pace_trigger', NULL, NULL, 3, 10),
  ('road', 'interval', 'สปรินต์ข้ามสะพานลอย', 'ใช้สะพานลอยเป็นจุด Sprint Marker วิ่งเร็วจากสะพานลอยหนึ่งไปอีกสะพานลอย สลับพัก ทำให้ครบ 4 รอบ', 'สะพานลอย', 'sprint_marker', NULL, NULL, 4, 10),
  ('road', 'easy', 'ตามหาไฟจราจร', 'ถ่ายรูปไฟจราจรที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 จุด ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 จุด) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ไฟจราจร', 'collect_distance', 2, 3, NULL, 10),
  ('road', 'long_run', 'สะสมไฟจราจรระยะไกล', 'เก็บสะสมภาพไฟจราจรตลอดเส้นทาง Long Run (ถ่าย 1 จุด ทุก 3 กม. สูงสุด 6 จุด) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ไฟจราจร', 'collect_distance', 3, 6, NULL, 10),
  ('road', 'tempo', 'เร่งจังหวะที่ไฟจราจร', 'ทุกครั้งที่พบไฟจราจรระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ไฟจราจร', 'pace_trigger', NULL, NULL, 3, 10),
  ('road', 'interval', 'สปรินต์ข้ามไฟจราจร', 'ใช้ไฟจราจรเป็นจุด Sprint Marker วิ่งเร็วจากไฟจราจรหนึ่งไปอีกไฟจราจร สลับพัก ทำให้ครบ 4 รอบ', 'ไฟจราจร', 'sprint_marker', NULL, NULL, 4, 10),
  ('road', 'easy', 'ตามหาป้ายชื่อซอย', 'ถ่ายรูปป้ายชื่อซอยที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ป้าย ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ป้าย) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ป้ายชื่อซอย', 'collect_distance', 2, 3, NULL, 10),
  ('road', 'long_run', 'สะสมป้ายชื่อซอยระยะไกล', 'เก็บสะสมภาพป้ายชื่อซอยตลอดเส้นทาง Long Run (ถ่าย 1 ป้าย ทุก 3 กม. สูงสุด 6 ป้าย) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ป้ายชื่อซอย', 'collect_distance', 3, 6, NULL, 10),
  ('road', 'tempo', 'เร่งจังหวะที่ป้ายชื่อซอย', 'ทุกครั้งที่พบป้ายชื่อซอยระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ป้ายชื่อซอย', 'pace_trigger', NULL, NULL, 3, 10),
  ('road', 'interval', 'สปรินต์ข้ามป้ายชื่อซอย', 'ใช้ป้ายชื่อซอยเป็นจุด Sprint Marker วิ่งเร็วจากป้ายชื่อซอยหนึ่งไปอีกป้ายชื่อซอย สลับพัก ทำให้ครบ 4 รอบ', 'ป้ายชื่อซอย', 'sprint_marker', NULL, NULL, 4, 10),
  ('road', 'easy', 'ตามหาเสาไฟฟ้า', 'ถ่ายรูปเสาไฟฟ้าที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ต้น ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ต้น) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'เสาไฟฟ้า', 'collect_distance', 2, 3, NULL, 10),
  ('road', 'long_run', 'สะสมเสาไฟฟ้าระยะไกล', 'เก็บสะสมภาพเสาไฟฟ้าตลอดเส้นทาง Long Run (ถ่าย 1 ต้น ทุก 3 กม. สูงสุด 6 ต้น) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'เสาไฟฟ้า', 'collect_distance', 3, 6, NULL, 10),
  ('road', 'tempo', 'เร่งจังหวะที่เสาไฟฟ้า', 'ทุกครั้งที่พบเสาไฟฟ้าระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'เสาไฟฟ้า', 'pace_trigger', NULL, NULL, 3, 10),
  ('road', 'interval', 'สปรินต์ข้ามเสาไฟฟ้า', 'ใช้เสาไฟฟ้าเป็นจุด Sprint Marker วิ่งเร็วจากเสาไฟฟ้าหนึ่งไปอีกเสาไฟฟ้า สลับพัก ทำให้ครบ 4 รอบ', 'เสาไฟฟ้า', 'sprint_marker', NULL, NULL, 4, 10),
  ('road', 'easy', 'ตามหาร้านอาหารข้างทาง', 'ถ่ายรูปร้านอาหารข้างทางที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ร้าน ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ร้าน) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ร้านอาหารข้างทาง', 'collect_distance', 2, 3, NULL, 10),
  ('road', 'long_run', 'สะสมร้านอาหารข้างทางระยะไกล', 'เก็บสะสมภาพร้านอาหารข้างทางตลอดเส้นทาง Long Run (ถ่าย 1 ร้าน ทุก 3 กม. สูงสุด 6 ร้าน) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ร้านอาหารข้างทาง', 'collect_distance', 3, 6, NULL, 10),
  ('road', 'tempo', 'เร่งจังหวะที่ร้านอาหารข้างทาง', 'ทุกครั้งที่พบร้านอาหารข้างทางระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ร้านอาหารข้างทาง', 'pace_trigger', NULL, NULL, 3, 10),
  ('road', 'interval', 'สปรินต์ข้ามร้านอาหารข้างทาง', 'ใช้ร้านอาหารข้างทางเป็นจุด Sprint Marker วิ่งเร็วจากร้านอาหารข้างทางหนึ่งไปอีกร้านอาหารข้างทาง สลับพัก ทำให้ครบ 4 รอบ', 'ร้านอาหารข้างทาง', 'sprint_marker', NULL, NULL, 4, 10),
  ('road', 'easy', 'ตามหาวัด', 'ถ่ายรูปวัดที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 แห่ง ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 แห่ง) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'วัด', 'collect_distance', 2, 3, NULL, 10),
  ('road', 'long_run', 'สะสมวัดระยะไกล', 'เก็บสะสมภาพวัดตลอดเส้นทาง Long Run (ถ่าย 1 แห่ง ทุก 3 กม. สูงสุด 6 แห่ง) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'วัด', 'collect_distance', 3, 6, NULL, 10),
  ('road', 'tempo', 'เร่งจังหวะที่วัด', 'ทุกครั้งที่พบวัดระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'วัด', 'pace_trigger', NULL, NULL, 3, 10),
  ('road', 'interval', 'สปรินต์ข้ามวัด', 'ใช้วัดเป็นจุด Sprint Marker วิ่งเร็วจากวัดหนึ่งไปอีกวัด สลับพัก ทำให้ครบ 4 รอบ', 'วัด', 'sprint_marker', NULL, NULL, 4, 10),
  ('road', 'easy', 'ตามหาปั๊มน้ำมัน', 'ถ่ายรูปปั๊มน้ำมันที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 แห่ง ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 แห่ง) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ปั๊มน้ำมัน', 'collect_distance', 2, 3, NULL, 10),
  ('road', 'long_run', 'สะสมปั๊มน้ำมันระยะไกล', 'เก็บสะสมภาพปั๊มน้ำมันตลอดเส้นทาง Long Run (ถ่าย 1 แห่ง ทุก 3 กม. สูงสุด 6 แห่ง) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ปั๊มน้ำมัน', 'collect_distance', 3, 6, NULL, 10),
  ('road', 'tempo', 'เร่งจังหวะที่ปั๊มน้ำมัน', 'ทุกครั้งที่พบปั๊มน้ำมันระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ปั๊มน้ำมัน', 'pace_trigger', NULL, NULL, 3, 10),
  ('road', 'interval', 'สปรินต์ข้ามปั๊มน้ำมัน', 'ใช้ปั๊มน้ำมันเป็นจุด Sprint Marker วิ่งเร็วจากปั๊มน้ำมันหนึ่งไปอีกปั๊มน้ำมัน สลับพัก ทำให้ครบ 4 รอบ', 'ปั๊มน้ำมัน', 'sprint_marker', NULL, NULL, 4, 10),
  ('road', 'easy', 'ตามหาสุนัขจรจัด', 'ถ่ายรูปสุนัขจรจัดที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ตัว ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ตัว) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'สุนัขจรจัด', 'collect_distance', 2, 3, NULL, 10),
  ('road', 'long_run', 'สะสมสุนัขจรจัดระยะไกล', 'เก็บสะสมภาพสุนัขจรจัดตลอดเส้นทาง Long Run (ถ่าย 1 ตัว ทุก 3 กม. สูงสุด 6 ตัว) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'สุนัขจรจัด', 'collect_distance', 3, 6, NULL, 10),
  ('road', 'tempo', 'เร่งจังหวะที่สุนัขจรจัด', 'ทุกครั้งที่พบสุนัขจรจัดระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'สุนัขจรจัด', 'pace_trigger', NULL, NULL, 3, 10),
  ('road', 'interval', 'สปรินต์ข้ามสุนัขจรจัด', 'ใช้สุนัขจรจัดเป็นจุด Sprint Marker วิ่งเร็วจากสุนัขจรจัดหนึ่งไปอีกสุนัขจรจัด สลับพัก ทำให้ครบ 4 รอบ', 'สุนัขจรจัด', 'sprint_marker', NULL, NULL, 4, 10),
  ('road', 'easy', 'ตามหาต้นไม้ริมทาง', 'ถ่ายรูปต้นไม้ริมทางที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ต้น ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ต้น) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ต้นไม้ริมทาง', 'collect_distance', 2, 3, NULL, 10),
  ('road', 'long_run', 'สะสมต้นไม้ริมทางระยะไกล', 'เก็บสะสมภาพต้นไม้ริมทางตลอดเส้นทาง Long Run (ถ่าย 1 ต้น ทุก 3 กม. สูงสุด 6 ต้น) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ต้นไม้ริมทาง', 'collect_distance', 3, 6, NULL, 10),
  ('road', 'tempo', 'เร่งจังหวะที่ต้นไม้ริมทาง', 'ทุกครั้งที่พบต้นไม้ริมทางระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ต้นไม้ริมทาง', 'pace_trigger', NULL, NULL, 3, 10),
  ('road', 'interval', 'สปรินต์ข้ามต้นไม้ริมทาง', 'ใช้ต้นไม้ริมทางเป็นจุด Sprint Marker วิ่งเร็วจากต้นไม้ริมทางหนึ่งไปอีกต้นไม้ริมทาง สลับพัก ทำให้ครบ 4 รอบ', 'ต้นไม้ริมทาง', 'sprint_marker', NULL, NULL, 4, 10),
  ('road', 'easy', 'ตามหาแผงขายของริมถนน', 'ถ่ายรูปแผงขายของริมถนนที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 แผง ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 แผง) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'แผงขายของริมถนน', 'collect_distance', 2, 3, NULL, 10),
  ('road', 'long_run', 'สะสมแผงขายของริมถนนระยะไกล', 'เก็บสะสมภาพแผงขายของริมถนนตลอดเส้นทาง Long Run (ถ่าย 1 แผง ทุก 3 กม. สูงสุด 6 แผง) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'แผงขายของริมถนน', 'collect_distance', 3, 6, NULL, 10),
  ('road', 'tempo', 'เร่งจังหวะที่แผงขายของริมถนน', 'ทุกครั้งที่พบแผงขายของริมถนนระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'แผงขายของริมถนน', 'pace_trigger', NULL, NULL, 3, 10),
  ('road', 'interval', 'สปรินต์ข้ามแผงขายของริมถนน', 'ใช้แผงขายของริมถนนเป็นจุด Sprint Marker วิ่งเร็วจากแผงขายของริมถนนหนึ่งไปอีกแผงขายของริมถนน สลับพัก ทำให้ครบ 4 รอบ', 'แผงขายของริมถนน', 'sprint_marker', NULL, NULL, 4, 10),
  ('road', 'easy', 'ตามหาตุ๊กตุ๊ก/สามล้อ', 'ถ่ายรูปตุ๊กตุ๊ก/สามล้อที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 คัน ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 คัน) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ตุ๊กตุ๊ก/สามล้อ', 'collect_distance', 2, 3, NULL, 10),
  ('road', 'long_run', 'สะสมตุ๊กตุ๊ก/สามล้อระยะไกล', 'เก็บสะสมภาพตุ๊กตุ๊ก/สามล้อตลอดเส้นทาง Long Run (ถ่าย 1 คัน ทุก 3 กม. สูงสุด 6 คัน) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ตุ๊กตุ๊ก/สามล้อ', 'collect_distance', 3, 6, NULL, 10),
  ('road', 'tempo', 'เร่งจังหวะที่ตุ๊กตุ๊ก/สามล้อ', 'ทุกครั้งที่พบตุ๊กตุ๊ก/สามล้อระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ตุ๊กตุ๊ก/สามล้อ', 'pace_trigger', NULL, NULL, 3, 10),
  ('road', 'interval', 'สปรินต์ข้ามตุ๊กตุ๊ก/สามล้อ', 'ใช้ตุ๊กตุ๊ก/สามล้อเป็นจุด Sprint Marker วิ่งเร็วจากตุ๊กตุ๊ก/สามล้อหนึ่งไปอีกตุ๊กตุ๊ก/สามล้อ สลับพัก ทำให้ครบ 4 รอบ', 'ตุ๊กตุ๊ก/สามล้อ', 'sprint_marker', NULL, NULL, 4, 10),
  ('road', 'easy', 'ตามหาทางม้าลาย', 'ถ่ายรูปทางม้าลายที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 จุด ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 จุด) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ทางม้าลาย', 'collect_distance', 2, 3, NULL, 10),
  ('road', 'long_run', 'สะสมทางม้าลายระยะไกล', 'เก็บสะสมภาพทางม้าลายตลอดเส้นทาง Long Run (ถ่าย 1 จุด ทุก 3 กม. สูงสุด 6 จุด) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ทางม้าลาย', 'collect_distance', 3, 6, NULL, 10),
  ('road', 'tempo', 'เร่งจังหวะที่ทางม้าลาย', 'ทุกครั้งที่พบทางม้าลายระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ทางม้าลาย', 'pace_trigger', NULL, NULL, 3, 10),
  ('road', 'interval', 'สปรินต์ข้ามทางม้าลาย', 'ใช้ทางม้าลายเป็นจุด Sprint Marker วิ่งเร็วจากทางม้าลายหนึ่งไปอีกทางม้าลาย สลับพัก ทำให้ครบ 4 รอบ', 'ทางม้าลาย', 'sprint_marker', NULL, NULL, 4, 10),
  ('road', 'easy', 'ตามหาร้านซ่อมรถ', 'ถ่ายรูปร้านซ่อมรถที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ร้าน ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ร้าน) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ร้านซ่อมรถ', 'collect_distance', 2, 3, NULL, 10),
  ('road', 'long_run', 'สะสมร้านซ่อมรถระยะไกล', 'เก็บสะสมภาพร้านซ่อมรถตลอดเส้นทาง Long Run (ถ่าย 1 ร้าน ทุก 3 กม. สูงสุด 6 ร้าน) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ร้านซ่อมรถ', 'collect_distance', 3, 6, NULL, 10),
  ('road', 'tempo', 'เร่งจังหวะที่ร้านซ่อมรถ', 'ทุกครั้งที่พบร้านซ่อมรถระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ร้านซ่อมรถ', 'pace_trigger', NULL, NULL, 3, 10),
  ('road', 'interval', 'สปรินต์ข้ามร้านซ่อมรถ', 'ใช้ร้านซ่อมรถเป็นจุด Sprint Marker วิ่งเร็วจากร้านซ่อมรถหนึ่งไปอีกร้านซ่อมรถ สลับพัก ทำให้ครบ 4 รอบ', 'ร้านซ่อมรถ', 'sprint_marker', NULL, NULL, 4, 10),
  ('road', 'easy', 'ตามหาบ้านทาสีสวย', 'ถ่ายรูปบ้านทาสีสวยที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 หลัง ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 หลัง) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'บ้านทาสีสวย', 'collect_distance', 2, 3, NULL, 10),
  ('road', 'long_run', 'สะสมบ้านทาสีสวยระยะไกล', 'เก็บสะสมภาพบ้านทาสีสวยตลอดเส้นทาง Long Run (ถ่าย 1 หลัง ทุก 3 กม. สูงสุด 6 หลัง) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'บ้านทาสีสวย', 'collect_distance', 3, 6, NULL, 10),
  ('road', 'tempo', 'เร่งจังหวะที่บ้านทาสีสวย', 'ทุกครั้งที่พบบ้านทาสีสวยระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'บ้านทาสีสวย', 'pace_trigger', NULL, NULL, 3, 10),
  ('road', 'interval', 'สปรินต์ข้ามบ้านทาสีสวย', 'ใช้บ้านทาสีสวยเป็นจุด Sprint Marker วิ่งเร็วจากบ้านทาสีสวยหนึ่งไปอีกบ้านทาสีสวย สลับพัก ทำให้ครบ 4 รอบ', 'บ้านทาสีสวย', 'sprint_marker', NULL, NULL, 4, 10),
  ('road', 'easy', 'ตามหากำแพงกราฟฟิตี้', 'ถ่ายรูปกำแพงกราฟฟิตี้ที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 จุด ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 จุด) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'กำแพงกราฟฟิตี้', 'collect_distance', 2, 3, NULL, 10),
  ('road', 'long_run', 'สะสมกำแพงกราฟฟิตี้ระยะไกล', 'เก็บสะสมภาพกำแพงกราฟฟิตี้ตลอดเส้นทาง Long Run (ถ่าย 1 จุด ทุก 3 กม. สูงสุด 6 จุด) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'กำแพงกราฟฟิตี้', 'collect_distance', 3, 6, NULL, 10),
  ('road', 'tempo', 'เร่งจังหวะที่กำแพงกราฟฟิตี้', 'ทุกครั้งที่พบกำแพงกราฟฟิตี้ระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'กำแพงกราฟฟิตี้', 'pace_trigger', NULL, NULL, 3, 10),
  ('road', 'interval', 'สปรินต์ข้ามกำแพงกราฟฟิตี้', 'ใช้กำแพงกราฟฟิตี้เป็นจุด Sprint Marker วิ่งเร็วจากกำแพงกราฟฟิตี้หนึ่งไปอีกกำแพงกราฟฟิตี้ สลับพัก ทำให้ครบ 4 รอบ', 'กำแพงกราฟฟิตี้', 'sprint_marker', NULL, NULL, 4, 10),
  ('city', 'easy', 'ตามหาคาเฟ่', 'ถ่ายรูปคาเฟ่ที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ร้าน ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ร้าน) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'คาเฟ่', 'collect_distance', 2, 3, NULL, 10),
  ('city', 'long_run', 'สะสมคาเฟ่ระยะไกล', 'เก็บสะสมภาพคาเฟ่ตลอดเส้นทาง Long Run (ถ่าย 1 ร้าน ทุก 3 กม. สูงสุด 6 ร้าน) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'คาเฟ่', 'collect_distance', 3, 6, NULL, 10),
  ('city', 'tempo', 'เร่งจังหวะที่คาเฟ่', 'ทุกครั้งที่พบคาเฟ่ระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'คาเฟ่', 'pace_trigger', NULL, NULL, 3, 10),
  ('city', 'interval', 'สปรินต์ข้ามคาเฟ่', 'ใช้คาเฟ่เป็นจุด Sprint Marker วิ่งเร็วจากคาเฟ่หนึ่งไปอีกคาเฟ่ สลับพัก ทำให้ครบ 4 รอบ', 'คาเฟ่', 'sprint_marker', NULL, NULL, 4, 10),
  ('city', 'easy', 'ตามหาร้านสะดวกซื้อ', 'ถ่ายรูปร้านสะดวกซื้อที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ร้าน ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ร้าน) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ร้านสะดวกซื้อ', 'collect_distance', 2, 3, NULL, 10),
  ('city', 'long_run', 'สะสมร้านสะดวกซื้อระยะไกล', 'เก็บสะสมภาพร้านสะดวกซื้อตลอดเส้นทาง Long Run (ถ่าย 1 ร้าน ทุก 3 กม. สูงสุด 6 ร้าน) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ร้านสะดวกซื้อ', 'collect_distance', 3, 6, NULL, 10),
  ('city', 'tempo', 'เร่งจังหวะที่ร้านสะดวกซื้อ', 'ทุกครั้งที่พบร้านสะดวกซื้อระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ร้านสะดวกซื้อ', 'pace_trigger', NULL, NULL, 3, 10),
  ('city', 'interval', 'สปรินต์ข้ามร้านสะดวกซื้อ', 'ใช้ร้านสะดวกซื้อเป็นจุด Sprint Marker วิ่งเร็วจากร้านสะดวกซื้อหนึ่งไปอีกร้านสะดวกซื้อ สลับพัก ทำให้ครบ 4 รอบ', 'ร้านสะดวกซื้อ', 'sprint_marker', NULL, NULL, 4, 10),
  ('city', 'easy', 'ตามหาตึกสูง', 'ถ่ายรูปตึกสูงที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ตึก ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ตึก) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ตึกสูง', 'collect_distance', 2, 3, NULL, 10),
  ('city', 'long_run', 'สะสมตึกสูงระยะไกล', 'เก็บสะสมภาพตึกสูงตลอดเส้นทาง Long Run (ถ่าย 1 ตึก ทุก 3 กม. สูงสุด 6 ตึก) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ตึกสูง', 'collect_distance', 3, 6, NULL, 10),
  ('city', 'tempo', 'เร่งจังหวะที่ตึกสูง', 'ทุกครั้งที่พบตึกสูงระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ตึกสูง', 'pace_trigger', NULL, NULL, 3, 10),
  ('city', 'interval', 'สปรินต์ข้ามตึกสูง', 'ใช้ตึกสูงเป็นจุด Sprint Marker วิ่งเร็วจากตึกสูงหนึ่งไปอีกตึกสูง สลับพัก ทำให้ครบ 4 รอบ', 'ตึกสูง', 'sprint_marker', NULL, NULL, 4, 10),
  ('city', 'easy', 'ตามหาป้ายโฆษณาไฟ LED', 'ถ่ายรูปป้ายโฆษณาไฟ LEDที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ป้าย ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ป้าย) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ป้ายโฆษณาไฟ LED', 'collect_distance', 2, 3, NULL, 10),
  ('city', 'long_run', 'สะสมป้ายโฆษณาไฟ LEDระยะไกล', 'เก็บสะสมภาพป้ายโฆษณาไฟ LEDตลอดเส้นทาง Long Run (ถ่าย 1 ป้าย ทุก 3 กม. สูงสุด 6 ป้าย) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ป้ายโฆษณาไฟ LED', 'collect_distance', 3, 6, NULL, 10),
  ('city', 'tempo', 'เร่งจังหวะที่ป้ายโฆษณาไฟ LED', 'ทุกครั้งที่พบป้ายโฆษณาไฟ LEDระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ป้ายโฆษณาไฟ LED', 'pace_trigger', NULL, NULL, 3, 10),
  ('city', 'interval', 'สปรินต์ข้ามป้ายโฆษณาไฟ LED', 'ใช้ป้ายโฆษณาไฟ LEDเป็นจุด Sprint Marker วิ่งเร็วจากป้ายโฆษณาไฟ LEDหนึ่งไปอีกป้ายโฆษณาไฟ LED สลับพัก ทำให้ครบ 4 รอบ', 'ป้ายโฆษณาไฟ LED', 'sprint_marker', NULL, NULL, 4, 10),
  ('city', 'easy', 'ตามหาป้ายสถานีรถไฟฟ้า', 'ถ่ายรูปป้ายสถานีรถไฟฟ้าที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ป้าย ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ป้าย) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ป้ายสถานีรถไฟฟ้า', 'collect_distance', 2, 3, NULL, 10),
  ('city', 'long_run', 'สะสมป้ายสถานีรถไฟฟ้าระยะไกล', 'เก็บสะสมภาพป้ายสถานีรถไฟฟ้าตลอดเส้นทาง Long Run (ถ่าย 1 ป้าย ทุก 3 กม. สูงสุด 6 ป้าย) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ป้ายสถานีรถไฟฟ้า', 'collect_distance', 3, 6, NULL, 10),
  ('city', 'tempo', 'เร่งจังหวะที่ป้ายสถานีรถไฟฟ้า', 'ทุกครั้งที่พบป้ายสถานีรถไฟฟ้าระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ป้ายสถานีรถไฟฟ้า', 'pace_trigger', NULL, NULL, 3, 10),
  ('city', 'interval', 'สปรินต์ข้ามป้ายสถานีรถไฟฟ้า', 'ใช้ป้ายสถานีรถไฟฟ้าเป็นจุด Sprint Marker วิ่งเร็วจากป้ายสถานีรถไฟฟ้าหนึ่งไปอีกป้ายสถานีรถไฟฟ้า สลับพัก ทำให้ครบ 4 รอบ', 'ป้ายสถานีรถไฟฟ้า', 'sprint_marker', NULL, NULL, 4, 10),
  ('city', 'easy', 'ตามหาทางม้าลาย', 'ถ่ายรูปทางม้าลายที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 จุด ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 จุด) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ทางม้าลาย', 'collect_distance', 2, 3, NULL, 10),
  ('city', 'long_run', 'สะสมทางม้าลายระยะไกล', 'เก็บสะสมภาพทางม้าลายตลอดเส้นทาง Long Run (ถ่าย 1 จุด ทุก 3 กม. สูงสุด 6 จุด) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ทางม้าลาย', 'collect_distance', 3, 6, NULL, 10),
  ('city', 'tempo', 'เร่งจังหวะที่ทางม้าลาย', 'ทุกครั้งที่พบทางม้าลายระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ทางม้าลาย', 'pace_trigger', NULL, NULL, 3, 10),
  ('city', 'interval', 'สปรินต์ข้ามทางม้าลาย', 'ใช้ทางม้าลายเป็นจุด Sprint Marker วิ่งเร็วจากทางม้าลายหนึ่งไปอีกทางม้าลาย สลับพัก ทำให้ครบ 4 รอบ', 'ทางม้าลาย', 'sprint_marker', NULL, NULL, 4, 10),
  ('city', 'easy', 'ตามหาคนถือร่ม', 'ถ่ายรูปคนถือร่มที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 คน ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 คน) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'คนถือร่ม', 'collect_distance', 2, 3, NULL, 10),
  ('city', 'long_run', 'สะสมคนถือร่มระยะไกล', 'เก็บสะสมภาพคนถือร่มตลอดเส้นทาง Long Run (ถ่าย 1 คน ทุก 3 กม. สูงสุด 6 คน) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'คนถือร่ม', 'collect_distance', 3, 6, NULL, 10),
  ('city', 'tempo', 'เร่งจังหวะที่คนถือร่ม', 'ทุกครั้งที่พบคนถือร่มระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'คนถือร่ม', 'pace_trigger', NULL, NULL, 3, 10),
  ('city', 'interval', 'สปรินต์ข้ามคนถือร่ม', 'ใช้คนถือร่มเป็นจุด Sprint Marker วิ่งเร็วจากคนถือร่มหนึ่งไปอีกคนถือร่ม สลับพัก ทำให้ครบ 4 รอบ', 'คนถือร่ม', 'sprint_marker', NULL, NULL, 4, 10),
  ('city', 'easy', 'ตามหาไรเดอร์ส่งอาหาร', 'ถ่ายรูปไรเดอร์ส่งอาหารที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 คน ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 คน) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ไรเดอร์ส่งอาหาร', 'collect_distance', 2, 3, NULL, 10),
  ('city', 'long_run', 'สะสมไรเดอร์ส่งอาหารระยะไกล', 'เก็บสะสมภาพไรเดอร์ส่งอาหารตลอดเส้นทาง Long Run (ถ่าย 1 คน ทุก 3 กม. สูงสุด 6 คน) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ไรเดอร์ส่งอาหาร', 'collect_distance', 3, 6, NULL, 10),
  ('city', 'tempo', 'เร่งจังหวะที่ไรเดอร์ส่งอาหาร', 'ทุกครั้งที่พบไรเดอร์ส่งอาหารระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ไรเดอร์ส่งอาหาร', 'pace_trigger', NULL, NULL, 3, 10),
  ('city', 'interval', 'สปรินต์ข้ามไรเดอร์ส่งอาหาร', 'ใช้ไรเดอร์ส่งอาหารเป็นจุด Sprint Marker วิ่งเร็วจากไรเดอร์ส่งอาหารหนึ่งไปอีกไรเดอร์ส่งอาหาร สลับพัก ทำให้ครบ 4 รอบ', 'ไรเดอร์ส่งอาหาร', 'sprint_marker', NULL, NULL, 4, 10),
  ('city', 'easy', 'ตามหารถแท็กซี่', 'ถ่ายรูปรถแท็กซี่ที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 คัน ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 คัน) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'รถแท็กซี่', 'collect_distance', 2, 3, NULL, 10),
  ('city', 'long_run', 'สะสมรถแท็กซี่ระยะไกล', 'เก็บสะสมภาพรถแท็กซี่ตลอดเส้นทาง Long Run (ถ่าย 1 คัน ทุก 3 กม. สูงสุด 6 คัน) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'รถแท็กซี่', 'collect_distance', 3, 6, NULL, 10),
  ('city', 'tempo', 'เร่งจังหวะที่รถแท็กซี่', 'ทุกครั้งที่พบรถแท็กซี่ระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'รถแท็กซี่', 'pace_trigger', NULL, NULL, 3, 10),
  ('city', 'interval', 'สปรินต์ข้ามรถแท็กซี่', 'ใช้รถแท็กซี่เป็นจุด Sprint Marker วิ่งเร็วจากรถแท็กซี่หนึ่งไปอีกรถแท็กซี่ สลับพัก ทำให้ครบ 4 รอบ', 'รถแท็กซี่', 'sprint_marker', NULL, NULL, 4, 10),
  ('city', 'easy', 'ตามหาน้ำพุ/ลานกว้าง', 'ถ่ายรูปน้ำพุ/ลานกว้างที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 แห่ง ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 แห่ง) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'น้ำพุ/ลานกว้าง', 'collect_distance', 2, 3, NULL, 10),
  ('city', 'long_run', 'สะสมน้ำพุ/ลานกว้างระยะไกล', 'เก็บสะสมภาพน้ำพุ/ลานกว้างตลอดเส้นทาง Long Run (ถ่าย 1 แห่ง ทุก 3 กม. สูงสุด 6 แห่ง) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'น้ำพุ/ลานกว้าง', 'collect_distance', 3, 6, NULL, 10),
  ('city', 'tempo', 'เร่งจังหวะที่น้ำพุ/ลานกว้าง', 'ทุกครั้งที่พบน้ำพุ/ลานกว้างระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'น้ำพุ/ลานกว้าง', 'pace_trigger', NULL, NULL, 3, 10),
  ('city', 'interval', 'สปรินต์ข้ามน้ำพุ/ลานกว้าง', 'ใช้น้ำพุ/ลานกว้างเป็นจุด Sprint Marker วิ่งเร็วจากน้ำพุ/ลานกว้างหนึ่งไปอีกน้ำพุ/ลานกว้าง สลับพัก ทำให้ครบ 4 รอบ', 'น้ำพุ/ลานกว้าง', 'sprint_marker', NULL, NULL, 4, 10),
  ('city', 'easy', 'ตามหาภาพ Street Art', 'ถ่ายรูปภาพ Street Artที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ภาพ ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ภาพ) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ภาพ Street Art', 'collect_distance', 2, 3, NULL, 10),
  ('city', 'long_run', 'สะสมภาพ Street Artระยะไกล', 'เก็บสะสมภาพภาพ Street Artตลอดเส้นทาง Long Run (ถ่าย 1 ภาพ ทุก 3 กม. สูงสุด 6 ภาพ) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ภาพ Street Art', 'collect_distance', 3, 6, NULL, 10),
  ('city', 'tempo', 'เร่งจังหวะที่ภาพ Street Art', 'ทุกครั้งที่พบภาพ Street Artระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ภาพ Street Art', 'pace_trigger', NULL, NULL, 3, 10),
  ('city', 'interval', 'สปรินต์ข้ามภาพ Street Art', 'ใช้ภาพ Street Artเป็นจุด Sprint Marker วิ่งเร็วจากภาพ Street Artหนึ่งไปอีกภาพ Street Art สลับพัก ทำให้ครบ 4 รอบ', 'ภาพ Street Art', 'sprint_marker', NULL, NULL, 4, 10),
  ('city', 'easy', 'ตามหาร้านดอกไม้', 'ถ่ายรูปร้านดอกไม้ที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ร้าน ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ร้าน) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ร้านดอกไม้', 'collect_distance', 2, 3, NULL, 10),
  ('city', 'long_run', 'สะสมร้านดอกไม้ระยะไกล', 'เก็บสะสมภาพร้านดอกไม้ตลอดเส้นทาง Long Run (ถ่าย 1 ร้าน ทุก 3 กม. สูงสุด 6 ร้าน) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ร้านดอกไม้', 'collect_distance', 3, 6, NULL, 10),
  ('city', 'tempo', 'เร่งจังหวะที่ร้านดอกไม้', 'ทุกครั้งที่พบร้านดอกไม้ระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ร้านดอกไม้', 'pace_trigger', NULL, NULL, 3, 10),
  ('city', 'interval', 'สปรินต์ข้ามร้านดอกไม้', 'ใช้ร้านดอกไม้เป็นจุด Sprint Marker วิ่งเร็วจากร้านดอกไม้หนึ่งไปอีกร้านดอกไม้ สลับพัก ทำให้ครบ 4 รอบ', 'ร้านดอกไม้', 'sprint_marker', NULL, NULL, 4, 10),
  ('city', 'easy', 'ตามหาวัดในเมือง', 'ถ่ายรูปวัดในเมืองที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 แห่ง ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 แห่ง) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'วัดในเมือง', 'collect_distance', 2, 3, NULL, 10),
  ('city', 'long_run', 'สะสมวัดในเมืองระยะไกล', 'เก็บสะสมภาพวัดในเมืองตลอดเส้นทาง Long Run (ถ่าย 1 แห่ง ทุก 3 กม. สูงสุด 6 แห่ง) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'วัดในเมือง', 'collect_distance', 3, 6, NULL, 10),
  ('city', 'tempo', 'เร่งจังหวะที่วัดในเมือง', 'ทุกครั้งที่พบวัดในเมืองระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'วัดในเมือง', 'pace_trigger', NULL, NULL, 3, 10),
  ('city', 'interval', 'สปรินต์ข้ามวัดในเมือง', 'ใช้วัดในเมืองเป็นจุด Sprint Marker วิ่งเร็วจากวัดในเมืองหนึ่งไปอีกวัดในเมือง สลับพัก ทำให้ครบ 4 รอบ', 'วัดในเมือง', 'sprint_marker', NULL, NULL, 4, 10),
  ('city', 'easy', 'ตามหาป้ายชื่อถนน', 'ถ่ายรูปป้ายชื่อถนนที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ป้าย ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ป้าย) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ป้ายชื่อถนน', 'collect_distance', 2, 3, NULL, 10),
  ('city', 'long_run', 'สะสมป้ายชื่อถนนระยะไกล', 'เก็บสะสมภาพป้ายชื่อถนนตลอดเส้นทาง Long Run (ถ่าย 1 ป้าย ทุก 3 กม. สูงสุด 6 ป้าย) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ป้ายชื่อถนน', 'collect_distance', 3, 6, NULL, 10),
  ('city', 'tempo', 'เร่งจังหวะที่ป้ายชื่อถนน', 'ทุกครั้งที่พบป้ายชื่อถนนระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ป้ายชื่อถนน', 'pace_trigger', NULL, NULL, 3, 10),
  ('city', 'interval', 'สปรินต์ข้ามป้ายชื่อถนน', 'ใช้ป้ายชื่อถนนเป็นจุด Sprint Marker วิ่งเร็วจากป้ายชื่อถนนหนึ่งไปอีกป้ายชื่อถนน สลับพัก ทำให้ครบ 4 รอบ', 'ป้ายชื่อถนน', 'sprint_marker', NULL, NULL, 4, 10),
  ('city', 'easy', 'ตามหาสวนเล็กกลางเมือง', 'ถ่ายรูปสวนเล็กกลางเมืองที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 แห่ง ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 แห่ง) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'สวนเล็กกลางเมือง', 'collect_distance', 2, 3, NULL, 10),
  ('city', 'long_run', 'สะสมสวนเล็กกลางเมืองระยะไกล', 'เก็บสะสมภาพสวนเล็กกลางเมืองตลอดเส้นทาง Long Run (ถ่าย 1 แห่ง ทุก 3 กม. สูงสุด 6 แห่ง) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'สวนเล็กกลางเมือง', 'collect_distance', 3, 6, NULL, 10),
  ('city', 'tempo', 'เร่งจังหวะที่สวนเล็กกลางเมือง', 'ทุกครั้งที่พบสวนเล็กกลางเมืองระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'สวนเล็กกลางเมือง', 'pace_trigger', NULL, NULL, 3, 10),
  ('city', 'interval', 'สปรินต์ข้ามสวนเล็กกลางเมือง', 'ใช้สวนเล็กกลางเมืองเป็นจุด Sprint Marker วิ่งเร็วจากสวนเล็กกลางเมืองหนึ่งไปอีกสวนเล็กกลางเมือง สลับพัก ทำให้ครบ 4 รอบ', 'สวนเล็กกลางเมือง', 'sprint_marker', NULL, NULL, 4, 10),
  ('city', 'easy', 'ตามหาร้านหนังสือ', 'ถ่ายรูปร้านหนังสือที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ร้าน ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ร้าน) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ร้านหนังสือ', 'collect_distance', 2, 3, NULL, 10),
  ('city', 'long_run', 'สะสมร้านหนังสือระยะไกล', 'เก็บสะสมภาพร้านหนังสือตลอดเส้นทาง Long Run (ถ่าย 1 ร้าน ทุก 3 กม. สูงสุด 6 ร้าน) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ร้านหนังสือ', 'collect_distance', 3, 6, NULL, 10),
  ('city', 'tempo', 'เร่งจังหวะที่ร้านหนังสือ', 'ทุกครั้งที่พบร้านหนังสือระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ร้านหนังสือ', 'pace_trigger', NULL, NULL, 3, 10),
  ('city', 'interval', 'สปรินต์ข้ามร้านหนังสือ', 'ใช้ร้านหนังสือเป็นจุด Sprint Marker วิ่งเร็วจากร้านหนังสือหนึ่งไปอีกร้านหนังสือ สลับพัก ทำให้ครบ 4 รอบ', 'ร้านหนังสือ', 'sprint_marker', NULL, NULL, 4, 10),
  ('city', 'easy', 'ตามหาคนออกกำลังกายกลางแจ้ง', 'ถ่ายรูปคนออกกำลังกายกลางแจ้งที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 คน ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 คน) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'คนออกกำลังกายกลางแจ้ง', 'collect_distance', 2, 3, NULL, 10),
  ('city', 'long_run', 'สะสมคนออกกำลังกายกลางแจ้งระยะไกล', 'เก็บสะสมภาพคนออกกำลังกายกลางแจ้งตลอดเส้นทาง Long Run (ถ่าย 1 คน ทุก 3 กม. สูงสุด 6 คน) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'คนออกกำลังกายกลางแจ้ง', 'collect_distance', 3, 6, NULL, 10),
  ('city', 'tempo', 'เร่งจังหวะที่คนออกกำลังกายกลางแจ้ง', 'ทุกครั้งที่พบคนออกกำลังกายกลางแจ้งระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'คนออกกำลังกายกลางแจ้ง', 'pace_trigger', NULL, NULL, 3, 10),
  ('city', 'interval', 'สปรินต์ข้ามคนออกกำลังกายกลางแจ้ง', 'ใช้คนออกกำลังกายกลางแจ้งเป็นจุด Sprint Marker วิ่งเร็วจากคนออกกำลังกายกลางแจ้งหนึ่งไปอีกคนออกกำลังกายกลางแจ้ง สลับพัก ทำให้ครบ 4 รอบ', 'คนออกกำลังกายกลางแจ้ง', 'sprint_marker', NULL, NULL, 4, 10),
  ('city', 'easy', 'ตามหาตึกสถาปัตยกรรมเก่า', 'ถ่ายรูปตึกสถาปัตยกรรมเก่าที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ตึก ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ตึก) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ตึกสถาปัตยกรรมเก่า', 'collect_distance', 2, 3, NULL, 10),
  ('city', 'long_run', 'สะสมตึกสถาปัตยกรรมเก่าระยะไกล', 'เก็บสะสมภาพตึกสถาปัตยกรรมเก่าตลอดเส้นทาง Long Run (ถ่าย 1 ตึก ทุก 3 กม. สูงสุด 6 ตึก) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ตึกสถาปัตยกรรมเก่า', 'collect_distance', 3, 6, NULL, 10),
  ('city', 'tempo', 'เร่งจังหวะที่ตึกสถาปัตยกรรมเก่า', 'ทุกครั้งที่พบตึกสถาปัตยกรรมเก่าระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ตึกสถาปัตยกรรมเก่า', 'pace_trigger', NULL, NULL, 3, 10),
  ('city', 'interval', 'สปรินต์ข้ามตึกสถาปัตยกรรมเก่า', 'ใช้ตึกสถาปัตยกรรมเก่าเป็นจุด Sprint Marker วิ่งเร็วจากตึกสถาปัตยกรรมเก่าหนึ่งไปอีกตึกสถาปัตยกรรมเก่า สลับพัก ทำให้ครบ 4 รอบ', 'ตึกสถาปัตยกรรมเก่า', 'sprint_marker', NULL, NULL, 4, 10),
  ('city', 'easy', 'ตามหาซุ้มไฟประดับ', 'ถ่ายรูปซุ้มไฟประดับที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 จุด ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 จุด) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ซุ้มไฟประดับ', 'collect_distance', 2, 3, NULL, 10),
  ('city', 'long_run', 'สะสมซุ้มไฟประดับระยะไกล', 'เก็บสะสมภาพซุ้มไฟประดับตลอดเส้นทาง Long Run (ถ่าย 1 จุด ทุก 3 กม. สูงสุด 6 จุด) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ซุ้มไฟประดับ', 'collect_distance', 3, 6, NULL, 10),
  ('city', 'tempo', 'เร่งจังหวะที่ซุ้มไฟประดับ', 'ทุกครั้งที่พบซุ้มไฟประดับระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ซุ้มไฟประดับ', 'pace_trigger', NULL, NULL, 3, 10),
  ('city', 'interval', 'สปรินต์ข้ามซุ้มไฟประดับ', 'ใช้ซุ้มไฟประดับเป็นจุด Sprint Marker วิ่งเร็วจากซุ้มไฟประดับหนึ่งไปอีกซุ้มไฟประดับ สลับพัก ทำให้ครบ 4 รอบ', 'ซุ้มไฟประดับ', 'sprint_marker', NULL, NULL, 4, 10),
  ('city', 'easy', 'ตามหานักดนตรีข้างถนน', 'ถ่ายรูปนักดนตรีข้างถนนที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 คน ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 คน) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'นักดนตรีข้างถนน', 'collect_distance', 2, 3, NULL, 10),
  ('city', 'long_run', 'สะสมนักดนตรีข้างถนนระยะไกล', 'เก็บสะสมภาพนักดนตรีข้างถนนตลอดเส้นทาง Long Run (ถ่าย 1 คน ทุก 3 กม. สูงสุด 6 คน) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'นักดนตรีข้างถนน', 'collect_distance', 3, 6, NULL, 10),
  ('city', 'tempo', 'เร่งจังหวะที่นักดนตรีข้างถนน', 'ทุกครั้งที่พบนักดนตรีข้างถนนระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'นักดนตรีข้างถนน', 'pace_trigger', NULL, NULL, 3, 10),
  ('city', 'interval', 'สปรินต์ข้ามนักดนตรีข้างถนน', 'ใช้นักดนตรีข้างถนนเป็นจุด Sprint Marker วิ่งเร็วจากนักดนตรีข้างถนนหนึ่งไปอีกนักดนตรีข้างถนน สลับพัก ทำให้ครบ 4 รอบ', 'นักดนตรีข้างถนน', 'sprint_marker', NULL, NULL, 4, 10),
  ('treadmill', 'easy', 'ตามหาหน้าจอลู่วิ่ง (สกรีนช็อต)', 'ถ่ายรูปหน้าจอลู่วิ่ง (สกรีนช็อต)ที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ภาพ ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ภาพ) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'หน้าจอลู่วิ่ง (สกรีนช็อต)', 'collect_distance', 2, 3, NULL, 10),
  ('treadmill', 'long_run', 'สะสมหน้าจอลู่วิ่ง (สกรีนช็อต)ระยะไกล', 'เก็บสะสมภาพหน้าจอลู่วิ่ง (สกรีนช็อต)ตลอดเส้นทาง Long Run (ถ่าย 1 ภาพ ทุก 3 กม. สูงสุด 6 ภาพ) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'หน้าจอลู่วิ่ง (สกรีนช็อต)', 'collect_distance', 3, 6, NULL, 10),
  ('treadmill', 'tempo', 'เร่งจังหวะที่หน้าจอลู่วิ่ง (สกรีนช็อต)', 'ทุกครั้งที่พบหน้าจอลู่วิ่ง (สกรีนช็อต)ระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'หน้าจอลู่วิ่ง (สกรีนช็อต)', 'pace_trigger', NULL, NULL, 3, 10),
  ('treadmill', 'interval', 'สปรินต์ข้ามหน้าจอลู่วิ่ง (สกรีนช็อต)', 'ใช้หน้าจอลู่วิ่ง (สกรีนช็อต)เป็นจุด Sprint Marker วิ่งเร็วจากหน้าจอลู่วิ่ง (สกรีนช็อต)หนึ่งไปอีกหน้าจอลู่วิ่ง (สกรีนช็อต) สลับพัก ทำให้ครบ 4 รอบ', 'หน้าจอลู่วิ่ง (สกรีนช็อต)', 'sprint_marker', NULL, NULL, 4, 10),
  ('treadmill', 'easy', 'ตามหาเพลงที่กำลังฟัง', 'ถ่ายรูปเพลงที่กำลังฟังที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 เพลง ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 เพลง) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'เพลงที่กำลังฟัง', 'collect_distance', 2, 3, NULL, 10),
  ('treadmill', 'long_run', 'สะสมเพลงที่กำลังฟังระยะไกล', 'เก็บสะสมภาพเพลงที่กำลังฟังตลอดเส้นทาง Long Run (ถ่าย 1 เพลง ทุก 3 กม. สูงสุด 6 เพลง) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'เพลงที่กำลังฟัง', 'collect_distance', 3, 6, NULL, 10),
  ('treadmill', 'tempo', 'เร่งจังหวะที่เพลงที่กำลังฟัง', 'ทุกครั้งที่พบเพลงที่กำลังฟังระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'เพลงที่กำลังฟัง', 'pace_trigger', NULL, NULL, 3, 10),
  ('treadmill', 'interval', 'สปรินต์ข้ามเพลงที่กำลังฟัง', 'ใช้เพลงที่กำลังฟังเป็นจุด Sprint Marker วิ่งเร็วจากเพลงที่กำลังฟังหนึ่งไปอีกเพลงที่กำลังฟัง สลับพัก ทำให้ครบ 4 รอบ', 'เพลงที่กำลังฟัง', 'sprint_marker', NULL, NULL, 4, 10),
  ('treadmill', 'easy', 'ตามหาขวดน้ำข้างลู่', 'ถ่ายรูปขวดน้ำข้างลู่ที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ขวด ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ขวด) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ขวดน้ำข้างลู่', 'collect_distance', 2, 3, NULL, 10),
  ('treadmill', 'long_run', 'สะสมขวดน้ำข้างลู่ระยะไกล', 'เก็บสะสมภาพขวดน้ำข้างลู่ตลอดเส้นทาง Long Run (ถ่าย 1 ขวด ทุก 3 กม. สูงสุด 6 ขวด) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ขวดน้ำข้างลู่', 'collect_distance', 3, 6, NULL, 10),
  ('treadmill', 'tempo', 'เร่งจังหวะที่ขวดน้ำข้างลู่', 'ทุกครั้งที่พบขวดน้ำข้างลู่ระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ขวดน้ำข้างลู่', 'pace_trigger', NULL, NULL, 3, 10),
  ('treadmill', 'interval', 'สปรินต์ข้ามขวดน้ำข้างลู่', 'ใช้ขวดน้ำข้างลู่เป็นจุด Sprint Marker วิ่งเร็วจากขวดน้ำข้างลู่หนึ่งไปอีกขวดน้ำข้างลู่ สลับพัก ทำให้ครบ 4 รอบ', 'ขวดน้ำข้างลู่', 'sprint_marker', NULL, NULL, 4, 10),
  ('treadmill', 'easy', 'ตามหากระจกในฟิตเนส', 'ถ่ายรูปกระจกในฟิตเนสที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 จุด ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 จุด) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'กระจกในฟิตเนส', 'collect_distance', 2, 3, NULL, 10),
  ('treadmill', 'long_run', 'สะสมกระจกในฟิตเนสระยะไกล', 'เก็บสะสมภาพกระจกในฟิตเนสตลอดเส้นทาง Long Run (ถ่าย 1 จุด ทุก 3 กม. สูงสุด 6 จุด) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'กระจกในฟิตเนส', 'collect_distance', 3, 6, NULL, 10),
  ('treadmill', 'tempo', 'เร่งจังหวะที่กระจกในฟิตเนส', 'ทุกครั้งที่พบกระจกในฟิตเนสระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'กระจกในฟิตเนส', 'pace_trigger', NULL, NULL, 3, 10),
  ('treadmill', 'interval', 'สปรินต์ข้ามกระจกในฟิตเนส', 'ใช้กระจกในฟิตเนสเป็นจุด Sprint Marker วิ่งเร็วจากกระจกในฟิตเนสหนึ่งไปอีกกระจกในฟิตเนส สลับพัก ทำให้ครบ 4 รอบ', 'กระจกในฟิตเนส', 'sprint_marker', NULL, NULL, 4, 10),
  ('treadmill', 'easy', 'ตามหานาฬิกา/สมาร์ทวอทช์', 'ถ่ายรูปนาฬิกา/สมาร์ทวอทช์ที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 เรือน ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 เรือน) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'นาฬิกา/สมาร์ทวอทช์', 'collect_distance', 2, 3, NULL, 10),
  ('treadmill', 'long_run', 'สะสมนาฬิกา/สมาร์ทวอทช์ระยะไกล', 'เก็บสะสมภาพนาฬิกา/สมาร์ทวอทช์ตลอดเส้นทาง Long Run (ถ่าย 1 เรือน ทุก 3 กม. สูงสุด 6 เรือน) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'นาฬิกา/สมาร์ทวอทช์', 'collect_distance', 3, 6, NULL, 10),
  ('treadmill', 'tempo', 'เร่งจังหวะที่นาฬิกา/สมาร์ทวอทช์', 'ทุกครั้งที่พบนาฬิกา/สมาร์ทวอทช์ระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'นาฬิกา/สมาร์ทวอทช์', 'pace_trigger', NULL, NULL, 3, 10),
  ('treadmill', 'interval', 'สปรินต์ข้ามนาฬิกา/สมาร์ทวอทช์', 'ใช้นาฬิกา/สมาร์ทวอทช์เป็นจุด Sprint Marker วิ่งเร็วจากนาฬิกา/สมาร์ทวอทช์หนึ่งไปอีกนาฬิกา/สมาร์ทวอทช์ สลับพัก ทำให้ครบ 4 รอบ', 'นาฬิกา/สมาร์ทวอทช์', 'sprint_marker', NULL, NULL, 4, 10),
  ('treadmill', 'easy', 'ตามหาพัดลมในฟิตเนส', 'ถ่ายรูปพัดลมในฟิตเนสที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ตัว ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ตัว) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'พัดลมในฟิตเนส', 'collect_distance', 2, 3, NULL, 10),
  ('treadmill', 'long_run', 'สะสมพัดลมในฟิตเนสระยะไกล', 'เก็บสะสมภาพพัดลมในฟิตเนสตลอดเส้นทาง Long Run (ถ่าย 1 ตัว ทุก 3 กม. สูงสุด 6 ตัว) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'พัดลมในฟิตเนส', 'collect_distance', 3, 6, NULL, 10),
  ('treadmill', 'tempo', 'เร่งจังหวะที่พัดลมในฟิตเนส', 'ทุกครั้งที่พบพัดลมในฟิตเนสระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'พัดลมในฟิตเนส', 'pace_trigger', NULL, NULL, 3, 10),
  ('treadmill', 'interval', 'สปรินต์ข้ามพัดลมในฟิตเนส', 'ใช้พัดลมในฟิตเนสเป็นจุด Sprint Marker วิ่งเร็วจากพัดลมในฟิตเนสหนึ่งไปอีกพัดลมในฟิตเนส สลับพัก ทำให้ครบ 4 รอบ', 'พัดลมในฟิตเนส', 'sprint_marker', NULL, NULL, 4, 10),
  ('treadmill', 'easy', 'ตามหาผ้าเช็ดเหงื่อ', 'ถ่ายรูปผ้าเช็ดเหงื่อที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ผืน ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ผืน) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ผ้าเช็ดเหงื่อ', 'collect_distance', 2, 3, NULL, 10),
  ('treadmill', 'long_run', 'สะสมผ้าเช็ดเหงื่อระยะไกล', 'เก็บสะสมภาพผ้าเช็ดเหงื่อตลอดเส้นทาง Long Run (ถ่าย 1 ผืน ทุก 3 กม. สูงสุด 6 ผืน) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ผ้าเช็ดเหงื่อ', 'collect_distance', 3, 6, NULL, 10),
  ('treadmill', 'tempo', 'เร่งจังหวะที่ผ้าเช็ดเหงื่อ', 'ทุกครั้งที่พบผ้าเช็ดเหงื่อระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ผ้าเช็ดเหงื่อ', 'pace_trigger', NULL, NULL, 3, 10),
  ('treadmill', 'interval', 'สปรินต์ข้ามผ้าเช็ดเหงื่อ', 'ใช้ผ้าเช็ดเหงื่อเป็นจุด Sprint Marker วิ่งเร็วจากผ้าเช็ดเหงื่อหนึ่งไปอีกผ้าเช็ดเหงื่อ สลับพัก ทำให้ครบ 4 รอบ', 'ผ้าเช็ดเหงื่อ', 'sprint_marker', NULL, NULL, 4, 10),
  ('treadmill', 'easy', 'ตามหาป้าย gym', 'ถ่ายรูปป้าย gymที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ป้าย ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ป้าย) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ป้าย gym', 'collect_distance', 2, 3, NULL, 10),
  ('treadmill', 'long_run', 'สะสมป้าย gymระยะไกล', 'เก็บสะสมภาพป้าย gymตลอดเส้นทาง Long Run (ถ่าย 1 ป้าย ทุก 3 กม. สูงสุด 6 ป้าย) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ป้าย gym', 'collect_distance', 3, 6, NULL, 10),
  ('treadmill', 'tempo', 'เร่งจังหวะที่ป้าย gym', 'ทุกครั้งที่พบป้าย gymระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ป้าย gym', 'pace_trigger', NULL, NULL, 3, 10),
  ('treadmill', 'interval', 'สปรินต์ข้ามป้าย gym', 'ใช้ป้าย gymเป็นจุด Sprint Marker วิ่งเร็วจากป้าย gymหนึ่งไปอีกป้าย gym สลับพัก ทำให้ครบ 4 รอบ', 'ป้าย gym', 'sprint_marker', NULL, NULL, 4, 10),
  ('treadmill', 'easy', 'ตามหาอุปกรณ์ออกกำลังกายข้างๆ', 'ถ่ายรูปอุปกรณ์ออกกำลังกายข้างๆที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ชิ้น ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ชิ้น) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'อุปกรณ์ออกกำลังกายข้างๆ', 'collect_distance', 2, 3, NULL, 10),
  ('treadmill', 'long_run', 'สะสมอุปกรณ์ออกกำลังกายข้างๆระยะไกล', 'เก็บสะสมภาพอุปกรณ์ออกกำลังกายข้างๆตลอดเส้นทาง Long Run (ถ่าย 1 ชิ้น ทุก 3 กม. สูงสุด 6 ชิ้น) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'อุปกรณ์ออกกำลังกายข้างๆ', 'collect_distance', 3, 6, NULL, 10),
  ('treadmill', 'tempo', 'เร่งจังหวะที่อุปกรณ์ออกกำลังกายข้างๆ', 'ทุกครั้งที่พบอุปกรณ์ออกกำลังกายข้างๆระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'อุปกรณ์ออกกำลังกายข้างๆ', 'pace_trigger', NULL, NULL, 3, 10),
  ('treadmill', 'interval', 'สปรินต์ข้ามอุปกรณ์ออกกำลังกายข้างๆ', 'ใช้อุปกรณ์ออกกำลังกายข้างๆเป็นจุด Sprint Marker วิ่งเร็วจากอุปกรณ์ออกกำลังกายข้างๆหนึ่งไปอีกอุปกรณ์ออกกำลังกายข้างๆ สลับพัก ทำให้ครบ 4 รอบ', 'อุปกรณ์ออกกำลังกายข้างๆ', 'sprint_marker', NULL, NULL, 4, 10),
  ('treadmill', 'easy', 'ตามหากระติกน้ำ', 'ถ่ายรูปกระติกน้ำที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ใบ ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ใบ) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'กระติกน้ำ', 'collect_distance', 2, 3, NULL, 10),
  ('treadmill', 'long_run', 'สะสมกระติกน้ำระยะไกล', 'เก็บสะสมภาพกระติกน้ำตลอดเส้นทาง Long Run (ถ่าย 1 ใบ ทุก 3 กม. สูงสุด 6 ใบ) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'กระติกน้ำ', 'collect_distance', 3, 6, NULL, 10),
  ('treadmill', 'tempo', 'เร่งจังหวะที่กระติกน้ำ', 'ทุกครั้งที่พบกระติกน้ำระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'กระติกน้ำ', 'pace_trigger', NULL, NULL, 3, 10),
  ('treadmill', 'interval', 'สปรินต์ข้ามกระติกน้ำ', 'ใช้กระติกน้ำเป็นจุด Sprint Marker วิ่งเร็วจากกระติกน้ำหนึ่งไปอีกกระติกน้ำ สลับพัก ทำให้ครบ 4 รอบ', 'กระติกน้ำ', 'sprint_marker', NULL, NULL, 4, 10),
  ('treadmill', 'easy', 'ตามหารองเท้าวิ่งคู่โปรด', 'ถ่ายรูปรองเท้าวิ่งคู่โปรดที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 คู่ ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 คู่) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'รองเท้าวิ่งคู่โปรด', 'collect_distance', 2, 3, NULL, 10),
  ('treadmill', 'long_run', 'สะสมรองเท้าวิ่งคู่โปรดระยะไกล', 'เก็บสะสมภาพรองเท้าวิ่งคู่โปรดตลอดเส้นทาง Long Run (ถ่าย 1 คู่ ทุก 3 กม. สูงสุด 6 คู่) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'รองเท้าวิ่งคู่โปรด', 'collect_distance', 3, 6, NULL, 10),
  ('treadmill', 'tempo', 'เร่งจังหวะที่รองเท้าวิ่งคู่โปรด', 'ทุกครั้งที่พบรองเท้าวิ่งคู่โปรดระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'รองเท้าวิ่งคู่โปรด', 'pace_trigger', NULL, NULL, 3, 10),
  ('treadmill', 'interval', 'สปรินต์ข้ามรองเท้าวิ่งคู่โปรด', 'ใช้รองเท้าวิ่งคู่โปรดเป็นจุด Sprint Marker วิ่งเร็วจากรองเท้าวิ่งคู่โปรดหนึ่งไปอีกรองเท้าวิ่งคู่โปรด สลับพัก ทำให้ครบ 4 รอบ', 'รองเท้าวิ่งคู่โปรด', 'sprint_marker', NULL, NULL, 4, 10),
  ('treadmill', 'easy', 'ตามหาจอทีวีในฟิตเนส', 'ถ่ายรูปจอทีวีในฟิตเนสที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 จอ ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 จอ) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'จอทีวีในฟิตเนส', 'collect_distance', 2, 3, NULL, 10),
  ('treadmill', 'long_run', 'สะสมจอทีวีในฟิตเนสระยะไกล', 'เก็บสะสมภาพจอทีวีในฟิตเนสตลอดเส้นทาง Long Run (ถ่าย 1 จอ ทุก 3 กม. สูงสุด 6 จอ) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'จอทีวีในฟิตเนส', 'collect_distance', 3, 6, NULL, 10),
  ('treadmill', 'tempo', 'เร่งจังหวะที่จอทีวีในฟิตเนส', 'ทุกครั้งที่พบจอทีวีในฟิตเนสระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'จอทีวีในฟิตเนส', 'pace_trigger', NULL, NULL, 3, 10),
  ('treadmill', 'interval', 'สปรินต์ข้ามจอทีวีในฟิตเนส', 'ใช้จอทีวีในฟิตเนสเป็นจุด Sprint Marker วิ่งเร็วจากจอทีวีในฟิตเนสหนึ่งไปอีกจอทีวีในฟิตเนส สลับพัก ทำให้ครบ 4 รอบ', 'จอทีวีในฟิตเนส', 'sprint_marker', NULL, NULL, 4, 10),
  ('treadmill', 'easy', 'ตามหาค่าอัตราการเต้นหัวใจบนจอ', 'ถ่ายรูปค่าอัตราการเต้นหัวใจบนจอที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ครั้ง ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ครั้ง) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ค่าอัตราการเต้นหัวใจบนจอ', 'collect_distance', 2, 3, NULL, 10),
  ('treadmill', 'long_run', 'สะสมค่าอัตราการเต้นหัวใจบนจอระยะไกล', 'เก็บสะสมภาพค่าอัตราการเต้นหัวใจบนจอตลอดเส้นทาง Long Run (ถ่าย 1 ครั้ง ทุก 3 กม. สูงสุด 6 ครั้ง) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ค่าอัตราการเต้นหัวใจบนจอ', 'collect_distance', 3, 6, NULL, 10),
  ('treadmill', 'tempo', 'เร่งจังหวะที่ค่าอัตราการเต้นหัวใจบนจอ', 'ทุกครั้งที่พบค่าอัตราการเต้นหัวใจบนจอระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ค่าอัตราการเต้นหัวใจบนจอ', 'pace_trigger', NULL, NULL, 3, 10),
  ('treadmill', 'interval', 'สปรินต์ข้ามค่าอัตราการเต้นหัวใจบนจอ', 'ใช้ค่าอัตราการเต้นหัวใจบนจอเป็นจุด Sprint Marker วิ่งเร็วจากค่าอัตราการเต้นหัวใจบนจอหนึ่งไปอีกค่าอัตราการเต้นหัวใจบนจอ สลับพัก ทำให้ครบ 4 รอบ', 'ค่าอัตราการเต้นหัวใจบนจอ', 'sprint_marker', NULL, NULL, 4, 10),
  ('treadmill', 'easy', 'ตามหาสติกเกอร์ให้กำลังใจ', 'ถ่ายรูปสติกเกอร์ให้กำลังใจที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ชิ้น ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ชิ้น) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'สติกเกอร์ให้กำลังใจ', 'collect_distance', 2, 3, NULL, 10),
  ('treadmill', 'long_run', 'สะสมสติกเกอร์ให้กำลังใจระยะไกล', 'เก็บสะสมภาพสติกเกอร์ให้กำลังใจตลอดเส้นทาง Long Run (ถ่าย 1 ชิ้น ทุก 3 กม. สูงสุด 6 ชิ้น) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'สติกเกอร์ให้กำลังใจ', 'collect_distance', 3, 6, NULL, 10),
  ('treadmill', 'tempo', 'เร่งจังหวะที่สติกเกอร์ให้กำลังใจ', 'ทุกครั้งที่พบสติกเกอร์ให้กำลังใจระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'สติกเกอร์ให้กำลังใจ', 'pace_trigger', NULL, NULL, 3, 10),
  ('treadmill', 'interval', 'สปรินต์ข้ามสติกเกอร์ให้กำลังใจ', 'ใช้สติกเกอร์ให้กำลังใจเป็นจุด Sprint Marker วิ่งเร็วจากสติกเกอร์ให้กำลังใจหนึ่งไปอีกสติกเกอร์ให้กำลังใจ สลับพัก ทำให้ครบ 4 รอบ', 'สติกเกอร์ให้กำลังใจ', 'sprint_marker', NULL, NULL, 4, 10),
  ('treadmill', 'easy', 'ตามหามุมฟิตเนสที่ชอบ', 'ถ่ายรูปมุมฟิตเนสที่ชอบที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 มุม ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 มุม) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'มุมฟิตเนสที่ชอบ', 'collect_distance', 2, 3, NULL, 10),
  ('treadmill', 'long_run', 'สะสมมุมฟิตเนสที่ชอบระยะไกล', 'เก็บสะสมภาพมุมฟิตเนสที่ชอบตลอดเส้นทาง Long Run (ถ่าย 1 มุม ทุก 3 กม. สูงสุด 6 มุม) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'มุมฟิตเนสที่ชอบ', 'collect_distance', 3, 6, NULL, 10),
  ('treadmill', 'tempo', 'เร่งจังหวะที่มุมฟิตเนสที่ชอบ', 'ทุกครั้งที่พบมุมฟิตเนสที่ชอบระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'มุมฟิตเนสที่ชอบ', 'pace_trigger', NULL, NULL, 3, 10),
  ('treadmill', 'interval', 'สปรินต์ข้ามมุมฟิตเนสที่ชอบ', 'ใช้มุมฟิตเนสที่ชอบเป็นจุด Sprint Marker วิ่งเร็วจากมุมฟิตเนสที่ชอบหนึ่งไปอีกมุมฟิตเนสที่ชอบ สลับพัก ทำให้ครบ 4 รอบ', 'มุมฟิตเนสที่ชอบ', 'sprint_marker', NULL, NULL, 4, 10),
  ('treadmill', 'easy', 'ตามหาสมุดจดบันทึกการซ้อม', 'ถ่ายรูปสมุดจดบันทึกการซ้อมที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 เล่ม ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 เล่ม) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'สมุดจดบันทึกการซ้อม', 'collect_distance', 2, 3, NULL, 10),
  ('treadmill', 'long_run', 'สะสมสมุดจดบันทึกการซ้อมระยะไกล', 'เก็บสะสมภาพสมุดจดบันทึกการซ้อมตลอดเส้นทาง Long Run (ถ่าย 1 เล่ม ทุก 3 กม. สูงสุด 6 เล่ม) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'สมุดจดบันทึกการซ้อม', 'collect_distance', 3, 6, NULL, 10),
  ('treadmill', 'tempo', 'เร่งจังหวะที่สมุดจดบันทึกการซ้อม', 'ทุกครั้งที่พบสมุดจดบันทึกการซ้อมระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'สมุดจดบันทึกการซ้อม', 'pace_trigger', NULL, NULL, 3, 10),
  ('treadmill', 'interval', 'สปรินต์ข้ามสมุดจดบันทึกการซ้อม', 'ใช้สมุดจดบันทึกการซ้อมเป็นจุด Sprint Marker วิ่งเร็วจากสมุดจดบันทึกการซ้อมหนึ่งไปอีกสมุดจดบันทึกการซ้อม สลับพัก ทำให้ครบ 4 รอบ', 'สมุดจดบันทึกการซ้อม', 'sprint_marker', NULL, NULL, 4, 10),
  ('treadmill', 'easy', 'ตามหากระเป๋าออกกำลังกาย', 'ถ่ายรูปกระเป๋าออกกำลังกายที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ใบ ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ใบ) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'กระเป๋าออกกำลังกาย', 'collect_distance', 2, 3, NULL, 10),
  ('treadmill', 'long_run', 'สะสมกระเป๋าออกกำลังกายระยะไกล', 'เก็บสะสมภาพกระเป๋าออกกำลังกายตลอดเส้นทาง Long Run (ถ่าย 1 ใบ ทุก 3 กม. สูงสุด 6 ใบ) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'กระเป๋าออกกำลังกาย', 'collect_distance', 3, 6, NULL, 10),
  ('treadmill', 'tempo', 'เร่งจังหวะที่กระเป๋าออกกำลังกาย', 'ทุกครั้งที่พบกระเป๋าออกกำลังกายระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'กระเป๋าออกกำลังกาย', 'pace_trigger', NULL, NULL, 3, 10),
  ('treadmill', 'interval', 'สปรินต์ข้ามกระเป๋าออกกำลังกาย', 'ใช้กระเป๋าออกกำลังกายเป็นจุด Sprint Marker วิ่งเร็วจากกระเป๋าออกกำลังกายหนึ่งไปอีกกระเป๋าออกกำลังกาย สลับพัก ทำให้ครบ 4 รอบ', 'กระเป๋าออกกำลังกาย', 'sprint_marker', NULL, NULL, 4, 10),
  ('treadmill', 'easy', 'ตามหาป้าย motivational quote', 'ถ่ายรูปป้าย motivational quoteที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ป้าย ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ป้าย) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ป้าย motivational quote', 'collect_distance', 2, 3, NULL, 10),
  ('treadmill', 'long_run', 'สะสมป้าย motivational quoteระยะไกล', 'เก็บสะสมภาพป้าย motivational quoteตลอดเส้นทาง Long Run (ถ่าย 1 ป้าย ทุก 3 กม. สูงสุด 6 ป้าย) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ป้าย motivational quote', 'collect_distance', 3, 6, NULL, 10),
  ('treadmill', 'tempo', 'เร่งจังหวะที่ป้าย motivational quote', 'ทุกครั้งที่พบป้าย motivational quoteระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ป้าย motivational quote', 'pace_trigger', NULL, NULL, 3, 10),
  ('treadmill', 'interval', 'สปรินต์ข้ามป้าย motivational quote', 'ใช้ป้าย motivational quoteเป็นจุด Sprint Marker วิ่งเร็วจากป้าย motivational quoteหนึ่งไปอีกป้าย motivational quote สลับพัก ทำให้ครบ 4 รอบ', 'ป้าย motivational quote', 'sprint_marker', NULL, NULL, 4, 10),
  ('treadmill', 'easy', 'ตามหาวิวจากหน้าต่างฟิตเนส', 'ถ่ายรูปวิวจากหน้าต่างฟิตเนสที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ภาพ ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ภาพ) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'วิวจากหน้าต่างฟิตเนส', 'collect_distance', 2, 3, NULL, 10),
  ('treadmill', 'long_run', 'สะสมวิวจากหน้าต่างฟิตเนสระยะไกล', 'เก็บสะสมภาพวิวจากหน้าต่างฟิตเนสตลอดเส้นทาง Long Run (ถ่าย 1 ภาพ ทุก 3 กม. สูงสุด 6 ภาพ) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'วิวจากหน้าต่างฟิตเนส', 'collect_distance', 3, 6, NULL, 10),
  ('treadmill', 'tempo', 'เร่งจังหวะที่วิวจากหน้าต่างฟิตเนส', 'ทุกครั้งที่พบวิวจากหน้าต่างฟิตเนสระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'วิวจากหน้าต่างฟิตเนส', 'pace_trigger', NULL, NULL, 3, 10),
  ('treadmill', 'interval', 'สปรินต์ข้ามวิวจากหน้าต่างฟิตเนส', 'ใช้วิวจากหน้าต่างฟิตเนสเป็นจุด Sprint Marker วิ่งเร็วจากวิวจากหน้าต่างฟิตเนสหนึ่งไปอีกวิวจากหน้าต่างฟิตเนส สลับพัก ทำให้ครบ 4 รอบ', 'วิวจากหน้าต่างฟิตเนส', 'sprint_marker', NULL, NULL, 4, 10),
  ('treadmill', 'easy', 'ตามหาเพื่อนร่วมฟิตเนส (ไม่ติดหน้า)', 'ถ่ายรูปเพื่อนร่วมฟิตเนส (ไม่ติดหน้า)ที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 คน ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 คน) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'เพื่อนร่วมฟิตเนส (ไม่ติดหน้า)', 'collect_distance', 2, 3, NULL, 10),
  ('treadmill', 'long_run', 'สะสมเพื่อนร่วมฟิตเนส (ไม่ติดหน้า)ระยะไกล', 'เก็บสะสมภาพเพื่อนร่วมฟิตเนส (ไม่ติดหน้า)ตลอดเส้นทาง Long Run (ถ่าย 1 คน ทุก 3 กม. สูงสุด 6 คน) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'เพื่อนร่วมฟิตเนส (ไม่ติดหน้า)', 'collect_distance', 3, 6, NULL, 10),
  ('treadmill', 'tempo', 'เร่งจังหวะที่เพื่อนร่วมฟิตเนส (ไม่ติดหน้า)', 'ทุกครั้งที่พบเพื่อนร่วมฟิตเนส (ไม่ติดหน้า)ระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'เพื่อนร่วมฟิตเนส (ไม่ติดหน้า)', 'pace_trigger', NULL, NULL, 3, 10),
  ('treadmill', 'interval', 'สปรินต์ข้ามเพื่อนร่วมฟิตเนส (ไม่ติดหน้า)', 'ใช้เพื่อนร่วมฟิตเนส (ไม่ติดหน้า)เป็นจุด Sprint Marker วิ่งเร็วจากเพื่อนร่วมฟิตเนส (ไม่ติดหน้า)หนึ่งไปอีกเพื่อนร่วมฟิตเนส (ไม่ติดหน้า) สลับพัก ทำให้ครบ 4 รอบ', 'เพื่อนร่วมฟิตเนส (ไม่ติดหน้า)', 'sprint_marker', NULL, NULL, 4, 10),
  ('trail', 'easy', 'ตามหาดอกไม้ป่า', 'ถ่ายรูปดอกไม้ป่าที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ดอก ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ดอก) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ดอกไม้ป่า', 'collect_distance', 2, 3, NULL, 10),
  ('trail', 'long_run', 'สะสมดอกไม้ป่าระยะไกล', 'เก็บสะสมภาพดอกไม้ป่าตลอดเส้นทาง Long Run (ถ่าย 1 ดอก ทุก 3 กม. สูงสุด 6 ดอก) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ดอกไม้ป่า', 'collect_distance', 3, 6, NULL, 10),
  ('trail', 'tempo', 'เร่งจังหวะที่ดอกไม้ป่า', 'ทุกครั้งที่พบดอกไม้ป่าระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ดอกไม้ป่า', 'pace_trigger', NULL, NULL, 3, 10),
  ('trail', 'interval', 'สปรินต์ข้ามดอกไม้ป่า', 'ใช้ดอกไม้ป่าเป็นจุด Sprint Marker วิ่งเร็วจากดอกไม้ป่าหนึ่งไปอีกดอกไม้ป่า สลับพัก ทำให้ครบ 4 รอบ', 'ดอกไม้ป่า', 'sprint_marker', NULL, NULL, 4, 10),
  ('trail', 'easy', 'ตามหาใบไม้รูปทรงแปลก', 'ถ่ายรูปใบไม้รูปทรงแปลกที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ใบ ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ใบ) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ใบไม้รูปทรงแปลก', 'collect_distance', 2, 3, NULL, 10),
  ('trail', 'long_run', 'สะสมใบไม้รูปทรงแปลกระยะไกล', 'เก็บสะสมภาพใบไม้รูปทรงแปลกตลอดเส้นทาง Long Run (ถ่าย 1 ใบ ทุก 3 กม. สูงสุด 6 ใบ) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ใบไม้รูปทรงแปลก', 'collect_distance', 3, 6, NULL, 10),
  ('trail', 'tempo', 'เร่งจังหวะที่ใบไม้รูปทรงแปลก', 'ทุกครั้งที่พบใบไม้รูปทรงแปลกระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ใบไม้รูปทรงแปลก', 'pace_trigger', NULL, NULL, 3, 10),
  ('trail', 'interval', 'สปรินต์ข้ามใบไม้รูปทรงแปลก', 'ใช้ใบไม้รูปทรงแปลกเป็นจุด Sprint Marker วิ่งเร็วจากใบไม้รูปทรงแปลกหนึ่งไปอีกใบไม้รูปทรงแปลก สลับพัก ทำให้ครบ 4 รอบ', 'ใบไม้รูปทรงแปลก', 'sprint_marker', NULL, NULL, 4, 10),
  ('trail', 'easy', 'ตามหาก้อนหินรูปทรงแปลก', 'ถ่ายรูปก้อนหินรูปทรงแปลกที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ก้อน ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ก้อน) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ก้อนหินรูปทรงแปลก', 'collect_distance', 2, 3, NULL, 10),
  ('trail', 'long_run', 'สะสมก้อนหินรูปทรงแปลกระยะไกล', 'เก็บสะสมภาพก้อนหินรูปทรงแปลกตลอดเส้นทาง Long Run (ถ่าย 1 ก้อน ทุก 3 กม. สูงสุด 6 ก้อน) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ก้อนหินรูปทรงแปลก', 'collect_distance', 3, 6, NULL, 10),
  ('trail', 'tempo', 'เร่งจังหวะที่ก้อนหินรูปทรงแปลก', 'ทุกครั้งที่พบก้อนหินรูปทรงแปลกระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ก้อนหินรูปทรงแปลก', 'pace_trigger', NULL, NULL, 3, 10),
  ('trail', 'interval', 'สปรินต์ข้ามก้อนหินรูปทรงแปลก', 'ใช้ก้อนหินรูปทรงแปลกเป็นจุด Sprint Marker วิ่งเร็วจากก้อนหินรูปทรงแปลกหนึ่งไปอีกก้อนหินรูปทรงแปลก สลับพัก ทำให้ครบ 4 รอบ', 'ก้อนหินรูปทรงแปลก', 'sprint_marker', NULL, NULL, 4, 10),
  ('trail', 'easy', 'ตามหาลำธาร/น้ำตก', 'ถ่ายรูปลำธาร/น้ำตกที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 แห่ง ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 แห่ง) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ลำธาร/น้ำตก', 'collect_distance', 2, 3, NULL, 10),
  ('trail', 'long_run', 'สะสมลำธาร/น้ำตกระยะไกล', 'เก็บสะสมภาพลำธาร/น้ำตกตลอดเส้นทาง Long Run (ถ่าย 1 แห่ง ทุก 3 กม. สูงสุด 6 แห่ง) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ลำธาร/น้ำตก', 'collect_distance', 3, 6, NULL, 10),
  ('trail', 'tempo', 'เร่งจังหวะที่ลำธาร/น้ำตก', 'ทุกครั้งที่พบลำธาร/น้ำตกระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ลำธาร/น้ำตก', 'pace_trigger', NULL, NULL, 3, 10),
  ('trail', 'interval', 'สปรินต์ข้ามลำธาร/น้ำตก', 'ใช้ลำธาร/น้ำตกเป็นจุด Sprint Marker วิ่งเร็วจากลำธาร/น้ำตกหนึ่งไปอีกลำธาร/น้ำตก สลับพัก ทำให้ครบ 4 รอบ', 'ลำธาร/น้ำตก', 'sprint_marker', NULL, NULL, 4, 10),
  ('trail', 'easy', 'ตามหาจุดชมวิว', 'ถ่ายรูปจุดชมวิวที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 จุด ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 จุด) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'จุดชมวิว', 'collect_distance', 2, 3, NULL, 10),
  ('trail', 'long_run', 'สะสมจุดชมวิวระยะไกล', 'เก็บสะสมภาพจุดชมวิวตลอดเส้นทาง Long Run (ถ่าย 1 จุด ทุก 3 กม. สูงสุด 6 จุด) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'จุดชมวิว', 'collect_distance', 3, 6, NULL, 10),
  ('trail', 'tempo', 'เร่งจังหวะที่จุดชมวิว', 'ทุกครั้งที่พบจุดชมวิวระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'จุดชมวิว', 'pace_trigger', NULL, NULL, 3, 10),
  ('trail', 'interval', 'สปรินต์ข้ามจุดชมวิว', 'ใช้จุดชมวิวเป็นจุด Sprint Marker วิ่งเร็วจากจุดชมวิวหนึ่งไปอีกจุดชมวิว สลับพัก ทำให้ครบ 4 รอบ', 'จุดชมวิว', 'sprint_marker', NULL, NULL, 4, 10),
  ('trail', 'easy', 'ตามหาต้นไม้ใหญ่พิเศษ', 'ถ่ายรูปต้นไม้ใหญ่พิเศษที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ต้น ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ต้น) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ต้นไม้ใหญ่พิเศษ', 'collect_distance', 2, 3, NULL, 10),
  ('trail', 'long_run', 'สะสมต้นไม้ใหญ่พิเศษระยะไกล', 'เก็บสะสมภาพต้นไม้ใหญ่พิเศษตลอดเส้นทาง Long Run (ถ่าย 1 ต้น ทุก 3 กม. สูงสุด 6 ต้น) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ต้นไม้ใหญ่พิเศษ', 'collect_distance', 3, 6, NULL, 10),
  ('trail', 'tempo', 'เร่งจังหวะที่ต้นไม้ใหญ่พิเศษ', 'ทุกครั้งที่พบต้นไม้ใหญ่พิเศษระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ต้นไม้ใหญ่พิเศษ', 'pace_trigger', NULL, NULL, 3, 10),
  ('trail', 'interval', 'สปรินต์ข้ามต้นไม้ใหญ่พิเศษ', 'ใช้ต้นไม้ใหญ่พิเศษเป็นจุด Sprint Marker วิ่งเร็วจากต้นไม้ใหญ่พิเศษหนึ่งไปอีกต้นไม้ใหญ่พิเศษ สลับพัก ทำให้ครบ 4 รอบ', 'ต้นไม้ใหญ่พิเศษ', 'sprint_marker', NULL, NULL, 4, 10),
  ('trail', 'easy', 'ตามหารอยเท้าสัตว์', 'ถ่ายรูปรอยเท้าสัตว์ที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 รอย ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 รอย) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'รอยเท้าสัตว์', 'collect_distance', 2, 3, NULL, 10),
  ('trail', 'long_run', 'สะสมรอยเท้าสัตว์ระยะไกล', 'เก็บสะสมภาพรอยเท้าสัตว์ตลอดเส้นทาง Long Run (ถ่าย 1 รอย ทุก 3 กม. สูงสุด 6 รอย) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'รอยเท้าสัตว์', 'collect_distance', 3, 6, NULL, 10),
  ('trail', 'tempo', 'เร่งจังหวะที่รอยเท้าสัตว์', 'ทุกครั้งที่พบรอยเท้าสัตว์ระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'รอยเท้าสัตว์', 'pace_trigger', NULL, NULL, 3, 10),
  ('trail', 'interval', 'สปรินต์ข้ามรอยเท้าสัตว์', 'ใช้รอยเท้าสัตว์เป็นจุด Sprint Marker วิ่งเร็วจากรอยเท้าสัตว์หนึ่งไปอีกรอยเท้าสัตว์ สลับพัก ทำให้ครบ 4 รอบ', 'รอยเท้าสัตว์', 'sprint_marker', NULL, NULL, 4, 10),
  ('trail', 'easy', 'ตามหาผีเสื้อ/แมลง', 'ถ่ายรูปผีเสื้อ/แมลงที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ตัว ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ตัว) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ผีเสื้อ/แมลง', 'collect_distance', 2, 3, NULL, 10),
  ('trail', 'long_run', 'สะสมผีเสื้อ/แมลงระยะไกล', 'เก็บสะสมภาพผีเสื้อ/แมลงตลอดเส้นทาง Long Run (ถ่าย 1 ตัว ทุก 3 กม. สูงสุด 6 ตัว) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ผีเสื้อ/แมลง', 'collect_distance', 3, 6, NULL, 10),
  ('trail', 'tempo', 'เร่งจังหวะที่ผีเสื้อ/แมลง', 'ทุกครั้งที่พบผีเสื้อ/แมลงระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ผีเสื้อ/แมลง', 'pace_trigger', NULL, NULL, 3, 10),
  ('trail', 'interval', 'สปรินต์ข้ามผีเสื้อ/แมลง', 'ใช้ผีเสื้อ/แมลงเป็นจุด Sprint Marker วิ่งเร็วจากผีเสื้อ/แมลงหนึ่งไปอีกผีเสื้อ/แมลง สลับพัก ทำให้ครบ 4 รอบ', 'ผีเสื้อ/แมลง', 'sprint_marker', NULL, NULL, 4, 10),
  ('trail', 'easy', 'ตามหาสะพานไม้เทรล', 'ถ่ายรูปสะพานไม้เทรลที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 สะพาน ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 สะพาน) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'สะพานไม้เทรล', 'collect_distance', 2, 3, NULL, 10),
  ('trail', 'long_run', 'สะสมสะพานไม้เทรลระยะไกล', 'เก็บสะสมภาพสะพานไม้เทรลตลอดเส้นทาง Long Run (ถ่าย 1 สะพาน ทุก 3 กม. สูงสุด 6 สะพาน) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'สะพานไม้เทรล', 'collect_distance', 3, 6, NULL, 10),
  ('trail', 'tempo', 'เร่งจังหวะที่สะพานไม้เทรล', 'ทุกครั้งที่พบสะพานไม้เทรลระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'สะพานไม้เทรล', 'pace_trigger', NULL, NULL, 3, 10),
  ('trail', 'interval', 'สปรินต์ข้ามสะพานไม้เทรล', 'ใช้สะพานไม้เทรลเป็นจุด Sprint Marker วิ่งเร็วจากสะพานไม้เทรลหนึ่งไปอีกสะพานไม้เทรล สลับพัก ทำให้ครบ 4 รอบ', 'สะพานไม้เทรล', 'sprint_marker', NULL, NULL, 4, 10),
  ('trail', 'easy', 'ตามหาป้ายบอกระยะเทรล', 'ถ่ายรูปป้ายบอกระยะเทรลที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ป้าย ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ป้าย) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'ป้ายบอกระยะเทรล', 'collect_distance', 2, 3, NULL, 10),
  ('trail', 'long_run', 'สะสมป้ายบอกระยะเทรลระยะไกล', 'เก็บสะสมภาพป้ายบอกระยะเทรลตลอดเส้นทาง Long Run (ถ่าย 1 ป้าย ทุก 3 กม. สูงสุด 6 ป้าย) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'ป้ายบอกระยะเทรล', 'collect_distance', 3, 6, NULL, 10),
  ('trail', 'tempo', 'เร่งจังหวะที่ป้ายบอกระยะเทรล', 'ทุกครั้งที่พบป้ายบอกระยะเทรลระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'ป้ายบอกระยะเทรล', 'pace_trigger', NULL, NULL, 3, 10),
  ('trail', 'interval', 'สปรินต์ข้ามป้ายบอกระยะเทรล', 'ใช้ป้ายบอกระยะเทรลเป็นจุด Sprint Marker วิ่งเร็วจากป้ายบอกระยะเทรลหนึ่งไปอีกป้ายบอกระยะเทรล สลับพัก ทำให้ครบ 4 รอบ', 'ป้ายบอกระยะเทรล', 'sprint_marker', NULL, NULL, 4, 10),
  ('trail', 'easy', 'ตามหาหมุดบอกกิโลเมตร', 'ถ่ายรูปหมุดบอกกิโลเมตรที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 หมุด ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 หมุด) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'หมุดบอกกิโลเมตร', 'collect_distance', 2, 3, NULL, 10),
  ('trail', 'long_run', 'สะสมหมุดบอกกิโลเมตรระยะไกล', 'เก็บสะสมภาพหมุดบอกกิโลเมตรตลอดเส้นทาง Long Run (ถ่าย 1 หมุด ทุก 3 กม. สูงสุด 6 หมุด) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'หมุดบอกกิโลเมตร', 'collect_distance', 3, 6, NULL, 10),
  ('trail', 'tempo', 'เร่งจังหวะที่หมุดบอกกิโลเมตร', 'ทุกครั้งที่พบหมุดบอกกิโลเมตรระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'หมุดบอกกิโลเมตร', 'pace_trigger', NULL, NULL, 3, 10),
  ('trail', 'interval', 'สปรินต์ข้ามหมุดบอกกิโลเมตร', 'ใช้หมุดบอกกิโลเมตรเป็นจุด Sprint Marker วิ่งเร็วจากหมุดบอกกิโลเมตรหนึ่งไปอีกหมุดบอกกิโลเมตร สลับพัก ทำให้ครบ 4 รอบ', 'หมุดบอกกิโลเมตร', 'sprint_marker', NULL, NULL, 4, 10),
  ('trail', 'easy', 'ตามหากองหินวางซ้อน (cairn)', 'ถ่ายรูปกองหินวางซ้อน (cairn)ที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 กอง ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 กอง) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'กองหินวางซ้อน (cairn)', 'collect_distance', 2, 3, NULL, 10),
  ('trail', 'long_run', 'สะสมกองหินวางซ้อน (cairn)ระยะไกล', 'เก็บสะสมภาพกองหินวางซ้อน (cairn)ตลอดเส้นทาง Long Run (ถ่าย 1 กอง ทุก 3 กม. สูงสุด 6 กอง) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'กองหินวางซ้อน (cairn)', 'collect_distance', 3, 6, NULL, 10),
  ('trail', 'tempo', 'เร่งจังหวะที่กองหินวางซ้อน (cairn)', 'ทุกครั้งที่พบกองหินวางซ้อน (cairn)ระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'กองหินวางซ้อน (cairn)', 'pace_trigger', NULL, NULL, 3, 10),
  ('trail', 'interval', 'สปรินต์ข้ามกองหินวางซ้อน (cairn)', 'ใช้กองหินวางซ้อน (cairn)เป็นจุด Sprint Marker วิ่งเร็วจากกองหินวางซ้อน (cairn)หนึ่งไปอีกกองหินวางซ้อน (cairn) สลับพัก ทำให้ครบ 4 รอบ', 'กองหินวางซ้อน (cairn)', 'sprint_marker', NULL, NULL, 4, 10),
  ('trail', 'easy', 'ตามหารากไม้ใหญ่ขวางทาง', 'ถ่ายรูปรากไม้ใหญ่ขวางทางที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ราก ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ราก) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'รากไม้ใหญ่ขวางทาง', 'collect_distance', 2, 3, NULL, 10),
  ('trail', 'long_run', 'สะสมรากไม้ใหญ่ขวางทางระยะไกล', 'เก็บสะสมภาพรากไม้ใหญ่ขวางทางตลอดเส้นทาง Long Run (ถ่าย 1 ราก ทุก 3 กม. สูงสุด 6 ราก) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'รากไม้ใหญ่ขวางทาง', 'collect_distance', 3, 6, NULL, 10),
  ('trail', 'tempo', 'เร่งจังหวะที่รากไม้ใหญ่ขวางทาง', 'ทุกครั้งที่พบรากไม้ใหญ่ขวางทางระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'รากไม้ใหญ่ขวางทาง', 'pace_trigger', NULL, NULL, 3, 10),
  ('trail', 'interval', 'สปรินต์ข้ามรากไม้ใหญ่ขวางทาง', 'ใช้รากไม้ใหญ่ขวางทางเป็นจุด Sprint Marker วิ่งเร็วจากรากไม้ใหญ่ขวางทางหนึ่งไปอีกรากไม้ใหญ่ขวางทาง สลับพัก ทำให้ครบ 4 รอบ', 'รากไม้ใหญ่ขวางทาง', 'sprint_marker', NULL, NULL, 4, 10),
  ('trail', 'easy', 'ตามหาหน้าผา/โขดหิน', 'ถ่ายรูปหน้าผา/โขดหินที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 จุด ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 จุด) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'หน้าผา/โขดหิน', 'collect_distance', 2, 3, NULL, 10),
  ('trail', 'long_run', 'สะสมหน้าผา/โขดหินระยะไกล', 'เก็บสะสมภาพหน้าผา/โขดหินตลอดเส้นทาง Long Run (ถ่าย 1 จุด ทุก 3 กม. สูงสุด 6 จุด) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'หน้าผา/โขดหิน', 'collect_distance', 3, 6, NULL, 10),
  ('trail', 'tempo', 'เร่งจังหวะที่หน้าผา/โขดหิน', 'ทุกครั้งที่พบหน้าผา/โขดหินระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'หน้าผา/โขดหิน', 'pace_trigger', NULL, NULL, 3, 10),
  ('trail', 'interval', 'สปรินต์ข้ามหน้าผา/โขดหิน', 'ใช้หน้าผา/โขดหินเป็นจุด Sprint Marker วิ่งเร็วจากหน้าผา/โขดหินหนึ่งไปอีกหน้าผา/โขดหิน สลับพัก ทำให้ครบ 4 รอบ', 'หน้าผา/โขดหิน', 'sprint_marker', NULL, NULL, 4, 10),
  ('trail', 'easy', 'ตามหากลุ่มเมฆสวยๆ', 'ถ่ายรูปกลุ่มเมฆสวยๆที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ภาพ ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ภาพ) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'กลุ่มเมฆสวยๆ', 'collect_distance', 2, 3, NULL, 10),
  ('trail', 'long_run', 'สะสมกลุ่มเมฆสวยๆระยะไกล', 'เก็บสะสมภาพกลุ่มเมฆสวยๆตลอดเส้นทาง Long Run (ถ่าย 1 ภาพ ทุก 3 กม. สูงสุด 6 ภาพ) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'กลุ่มเมฆสวยๆ', 'collect_distance', 3, 6, NULL, 10),
  ('trail', 'tempo', 'เร่งจังหวะที่กลุ่มเมฆสวยๆ', 'ทุกครั้งที่พบกลุ่มเมฆสวยๆระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'กลุ่มเมฆสวยๆ', 'pace_trigger', NULL, NULL, 3, 10),
  ('trail', 'interval', 'สปรินต์ข้ามกลุ่มเมฆสวยๆ', 'ใช้กลุ่มเมฆสวยๆเป็นจุด Sprint Marker วิ่งเร็วจากกลุ่มเมฆสวยๆหนึ่งไปอีกกลุ่มเมฆสวยๆ สลับพัก ทำให้ครบ 4 รอบ', 'กลุ่มเมฆสวยๆ', 'sprint_marker', NULL, NULL, 4, 10),
  ('trail', 'easy', 'ตามหาพระอาทิตย์ขึ้น/ตก', 'ถ่ายรูปพระอาทิตย์ขึ้น/ตกที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ภาพ ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ภาพ) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'พระอาทิตย์ขึ้น/ตก', 'collect_distance', 2, 3, NULL, 10),
  ('trail', 'long_run', 'สะสมพระอาทิตย์ขึ้น/ตกระยะไกล', 'เก็บสะสมภาพพระอาทิตย์ขึ้น/ตกตลอดเส้นทาง Long Run (ถ่าย 1 ภาพ ทุก 3 กม. สูงสุด 6 ภาพ) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'พระอาทิตย์ขึ้น/ตก', 'collect_distance', 3, 6, NULL, 10),
  ('trail', 'tempo', 'เร่งจังหวะที่พระอาทิตย์ขึ้น/ตก', 'ทุกครั้งที่พบพระอาทิตย์ขึ้น/ตกระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'พระอาทิตย์ขึ้น/ตก', 'pace_trigger', NULL, NULL, 3, 10),
  ('trail', 'interval', 'สปรินต์ข้ามพระอาทิตย์ขึ้น/ตก', 'ใช้พระอาทิตย์ขึ้น/ตกเป็นจุด Sprint Marker วิ่งเร็วจากพระอาทิตย์ขึ้น/ตกหนึ่งไปอีกพระอาทิตย์ขึ้น/ตก สลับพัก ทำให้ครบ 4 รอบ', 'พระอาทิตย์ขึ้น/ตก', 'sprint_marker', NULL, NULL, 4, 10),
  ('trail', 'easy', 'ตามหาสัตว์ป่าตัวเล็ก', 'ถ่ายรูปสัตว์ป่าตัวเล็กที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 ตัว ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 ตัว) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'สัตว์ป่าตัวเล็ก', 'collect_distance', 2, 3, NULL, 10),
  ('trail', 'long_run', 'สะสมสัตว์ป่าตัวเล็กระยะไกล', 'เก็บสะสมภาพสัตว์ป่าตัวเล็กตลอดเส้นทาง Long Run (ถ่าย 1 ตัว ทุก 3 กม. สูงสุด 6 ตัว) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'สัตว์ป่าตัวเล็ก', 'collect_distance', 3, 6, NULL, 10),
  ('trail', 'tempo', 'เร่งจังหวะที่สัตว์ป่าตัวเล็ก', 'ทุกครั้งที่พบสัตว์ป่าตัวเล็กระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'สัตว์ป่าตัวเล็ก', 'pace_trigger', NULL, NULL, 3, 10),
  ('trail', 'interval', 'สปรินต์ข้ามสัตว์ป่าตัวเล็ก', 'ใช้สัตว์ป่าตัวเล็กเป็นจุด Sprint Marker วิ่งเร็วจากสัตว์ป่าตัวเล็กหนึ่งไปอีกสัตว์ป่าตัวเล็ก สลับพัก ทำให้ครบ 4 รอบ', 'สัตว์ป่าตัวเล็ก', 'sprint_marker', NULL, NULL, 4, 10),
  ('trail', 'easy', 'ตามหาบึง/หนองน้ำ', 'ถ่ายรูปบึง/หนองน้ำที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 แห่ง ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 แห่ง) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'บึง/หนองน้ำ', 'collect_distance', 2, 3, NULL, 10),
  ('trail', 'long_run', 'สะสมบึง/หนองน้ำระยะไกล', 'เก็บสะสมภาพบึง/หนองน้ำตลอดเส้นทาง Long Run (ถ่าย 1 แห่ง ทุก 3 กม. สูงสุด 6 แห่ง) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'บึง/หนองน้ำ', 'collect_distance', 3, 6, NULL, 10),
  ('trail', 'tempo', 'เร่งจังหวะที่บึง/หนองน้ำ', 'ทุกครั้งที่พบบึง/หนองน้ำระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'บึง/หนองน้ำ', 'pace_trigger', NULL, NULL, 3, 10),
  ('trail', 'interval', 'สปรินต์ข้ามบึง/หนองน้ำ', 'ใช้บึง/หนองน้ำเป็นจุด Sprint Marker วิ่งเร็วจากบึง/หนองน้ำหนึ่งไปอีกบึง/หนองน้ำ สลับพัก ทำให้ครบ 4 รอบ', 'บึง/หนองน้ำ', 'sprint_marker', NULL, NULL, 4, 10),
  ('trail', 'easy', 'ตามหาจุดพักเทรล (shelter)', 'ถ่ายรูปจุดพักเทรล (shelter)ที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 แห่ง ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 แห่ง) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'จุดพักเทรล (shelter)', 'collect_distance', 2, 3, NULL, 10),
  ('trail', 'long_run', 'สะสมจุดพักเทรล (shelter)ระยะไกล', 'เก็บสะสมภาพจุดพักเทรล (shelter)ตลอดเส้นทาง Long Run (ถ่าย 1 แห่ง ทุก 3 กม. สูงสุด 6 แห่ง) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'จุดพักเทรล (shelter)', 'collect_distance', 3, 6, NULL, 10),
  ('trail', 'tempo', 'เร่งจังหวะที่จุดพักเทรล (shelter)', 'ทุกครั้งที่พบจุดพักเทรล (shelter)ระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'จุดพักเทรล (shelter)', 'pace_trigger', NULL, NULL, 3, 10),
  ('trail', 'interval', 'สปรินต์ข้ามจุดพักเทรล (shelter)', 'ใช้จุดพักเทรล (shelter)เป็นจุด Sprint Marker วิ่งเร็วจากจุดพักเทรล (shelter)หนึ่งไปอีกจุดพักเทรล (shelter) สลับพัก ทำให้ครบ 4 รอบ', 'จุดพักเทรล (shelter)', 'sprint_marker', NULL, NULL, 4, 10),
  ('trail', 'easy', 'ตามหาเถาวัลย์ห้อยลงมา', 'ถ่ายรูปเถาวัลย์ห้อยลงมาที่พบระหว่างวิ่ง Easy ให้ครบตามจำนวน (นับ 1 จุด ทุก 2 กม. ที่วิ่งได้ สูงสุด 3 จุด) — ไม่ต้องรีบ ค่อยๆ วิ่งไปหาไปเพลินๆ', 'เถาวัลย์ห้อยลงมา', 'collect_distance', 2, 3, NULL, 10),
  ('trail', 'long_run', 'สะสมเถาวัลย์ห้อยลงมาระยะไกล', 'เก็บสะสมภาพเถาวัลย์ห้อยลงมาตลอดเส้นทาง Long Run (ถ่าย 1 จุด ทุก 3 กม. สูงสุด 6 จุด) รวมเป็น Quest Album ท้าย Session ดูย้อนหลังได้ใน Post-Run Summary', 'เถาวัลย์ห้อยลงมา', 'collect_distance', 3, 6, NULL, 10),
  ('trail', 'tempo', 'เร่งจังหวะที่เถาวัลย์ห้อยลงมา', 'ทุกครั้งที่พบเถาวัลย์ห้อยลงมาระหว่างวิ่ง Tempo ให้เร่ง pace ขึ้นเล็กน้อยแล้วถ่ายรูปเก็บไว้ ทำให้ครบ 3 ครั้ง', 'เถาวัลย์ห้อยลงมา', 'pace_trigger', NULL, NULL, 3, 10),
  ('trail', 'interval', 'สปรินต์ข้ามเถาวัลย์ห้อยลงมา', 'ใช้เถาวัลย์ห้อยลงมาเป็นจุด Sprint Marker วิ่งเร็วจากเถาวัลย์ห้อยลงมาหนึ่งไปอีกเถาวัลย์ห้อยลงมา สลับพัก ทำให้ครบ 4 รอบ', 'เถาวัลย์ห้อยลงมา', 'sprint_marker', NULL, NULL, 4, 10);
-- ============================================================================
-- Pacegasus — Migration Addendum: Manual Day-by-Day Scheduling Support
-- ============================================================================
-- แก้ 3 ช่องว่างที่พบตอนคุยเรื่อง Prototype (auto-assign) vs แอพจริง (user
-- ลงวันเองทีละวัน แทรกเพิ่มทีหลังได้):
--   Gap 1: weekly_cap ต้องเช็ค real-time ตอน insert แต่ละแถว
--   Gap 2: program_sequencing_rules ต้องเช็คจาก scheduled_date ข้างเคียงจริง
--          ไม่ใช่ลำดับการ insert
--   Gap 3: program_phases ไม่มีช่วงวันที่ (duration_weeks) ทำให้ resolve
--          phase + specs จากวันที่ที่ user เลือกเองไม่ได้
-- รันไฟล์นี้ต่อจาก pacegasus_quests_migration.sql
-- ============================================================================


-- ============================================================================
-- SECTION A: แยกโหมด Prototype (auto) vs แอพจริง (manual)
-- ============================================================================

CREATE TYPE schedule_mode_enum AS ENUM ('auto', 'manual');

ALTER TABLE user_programs
  ADD COLUMN schedule_mode schedule_mode_enum NOT NULL DEFAULT 'manual';

COMMENT ON COLUMN user_programs.schedule_mode IS
  'auto = prototype (ระบบ generate ตารางทั้งสัปดาห์ให้ทันทีตอนสมัคร), '
  'manual = แอพจริง (ผู้ใช้ลงวันที่เอง ทีละวัน แทรกเพิ่มทีหลังได้)';


-- ============================================================================
-- SECTION B: Gap 3 — program_phases เพิ่มช่วงเวลา (duration_weeks)
-- ============================================================================

ALTER TABLE program_phases
  ADD COLUMN duration_weeks SMALLINT NOT NULL DEFAULT 1;

-- อัปเดต duration_weeks ตามที่ seed ไว้ก่อนหน้า (รวมแล้วตรงกับ
-- duration_weeks_min/max ของแต่ละ template ใน mainquest_progreession.txt)

-- Lower Intermediate (รวม 8-10 สัปดาห์): base=3, build=3, peak=2, taper=1, race=1
UPDATE program_phases SET duration_weeks = 3
WHERE phase_code = 'base' AND program_template_id =
  (SELECT id FROM program_templates WHERE level = 'lower_intermediate');
UPDATE program_phases SET duration_weeks = 3
WHERE phase_code = 'build' AND program_template_id =
  (SELECT id FROM program_templates WHERE level = 'lower_intermediate');
UPDATE program_phases SET duration_weeks = 2
WHERE phase_code = 'peak' AND program_template_id =
  (SELECT id FROM program_templates WHERE level = 'lower_intermediate');
UPDATE program_phases SET duration_weeks = 1
WHERE phase_code = 'taper_easy' AND program_template_id =
  (SELECT id FROM program_templates WHERE level = 'lower_intermediate');
UPDATE program_phases SET duration_weeks = 1
WHERE phase_code = 'race' AND program_template_id =
  (SELECT id FROM program_templates WHERE level = 'lower_intermediate');

-- Upper Intermediate (รวม 10-12 สัปดาห์): base=4, build=4, peak=2, taper=1, race=1
UPDATE program_phases SET duration_weeks = 4
WHERE phase_code = 'base' AND program_template_id =
  (SELECT id FROM program_templates WHERE level = 'upper_intermediate');
UPDATE program_phases SET duration_weeks = 4
WHERE phase_code = 'build' AND program_template_id =
  (SELECT id FROM program_templates WHERE level = 'upper_intermediate');
UPDATE program_phases SET duration_weeks = 2
WHERE phase_code = 'peak' AND program_template_id =
  (SELECT id FROM program_templates WHERE level = 'upper_intermediate');
UPDATE program_phases SET duration_weeks = 1
WHERE phase_code = 'taper_easy' AND program_template_id =
  (SELECT id FROM program_templates WHERE level = 'upper_intermediate');
UPDATE program_phases SET duration_weeks = 1
WHERE phase_code = 'race' AND program_template_id =
  (SELECT id FROM program_templates WHERE level = 'upper_intermediate');

-- NOTE: ตัวเลขข้างบนเป็นค่าประมาณของผม (เอกสารต้นฉบับบอกแค่ยอดรวม 8-10 / 10-12
-- สัปดาห์ ไม่ได้ระบุว่าแต่ละ phase กินกี่สัปดาห์) — ควร confirm/ปรับให้ตรงใจ

-- ---- ฟังก์ชัน resolve phase จากวันที่ ----
-- คืน phase_id ที่ scheduled_date ตกอยู่ใน range ของ phase นั้น
-- (Beginner ไม่มี phase เลย -> คืน NULL เสมอ)
CREATE OR REPLACE FUNCTION fn_resolve_phase_id(
  p_user_program_id UUID,
  p_scheduled_date DATE
) RETURNS UUID AS $$
DECLARE
  v_start_date DATE;
  v_week_number INT;
  v_phase_id UUID;
  v_cum_weeks INT := 0;
  r RECORD;
BEGIN
  SELECT start_date INTO v_start_date FROM user_programs WHERE id = p_user_program_id;
  IF v_start_date IS NULL THEN
    RETURN NULL;
  END IF;

  v_week_number := FLOOR((p_scheduled_date - v_start_date) / 7) + 1;  -- 1-indexed

  FOR r IN
    SELECT id, duration_weeks
    FROM program_phases
    WHERE program_template_id = (
      SELECT program_template_id FROM user_programs WHERE id = p_user_program_id
    )
    ORDER BY phase_order ASC
  LOOP
    v_cum_weeks := v_cum_weeks + r.duration_weeks;
    IF v_week_number <= v_cum_weeks THEN
      v_phase_id := r.id;
      EXIT;
    END IF;
  END LOOP;

  -- ถ้าไม่มี phase เลย (Beginner) หรือ week_number เกินทุก phase (โปรแกรมเกินกำหนด)
  -- คืน NULL หรือ phase สุดท้ายที่เจอ (เกินไปแล้วให้ค้างที่ race phase)
  IF v_phase_id IS NULL THEN
    SELECT id INTO v_phase_id FROM program_phases
    WHERE program_template_id = (
      SELECT program_template_id FROM user_programs WHERE id = p_user_program_id
    )
    ORDER BY phase_order DESC LIMIT 1;
  END IF;

  RETURN v_phase_id;  -- ยังคง NULL ได้ถ้า template ไม่มี phase เลย (Beginner)
END;
$$ LANGUAGE plpgsql;


-- ============================================================================
-- SECTION C: Trigger กลาง — auto-fill phase_id + planned_value ก่อน validate
-- ============================================================================
-- ใช้ทั้งโหมด auto (prototype generator เรียก insert ตรงๆ) และ manual
-- (user เลือกแค่ scheduled_date + session_type เอง ไม่ต้องรู้เรื่อง phase/multiplier)

CREATE OR REPLACE FUNCTION fn_main_quest_before_insert()
RETURNS TRIGGER AS $$
DECLARE
  v_program_template_id UUID;
  v_base_value NUMERIC(6,2);
  v_multiplier NUMERIC(5,2);
  v_unit session_unit_enum;
  v_is_bonus BOOLEAN;
BEGIN
  -- Gap 3: auto-resolve phase_id ถ้าไม่ได้ระบุมา
  IF NEW.phase_id IS NULL THEN
    NEW.phase_id := fn_resolve_phase_id(NEW.user_program_id, NEW.scheduled_date);
  END IF;

  SELECT program_template_id INTO v_program_template_id
  FROM user_programs WHERE id = NEW.user_program_id;

  -- auto-calc planned_value ถ้าไม่ได้ระบุมา (base_value x multiplier)
  IF NEW.planned_value IS NULL THEN
    SELECT s.multiplier, s.unit, s.is_bonus INTO v_multiplier, v_unit, v_is_bonus
    FROM session_type_specs s
    WHERE s.program_template_id = v_program_template_id
      AND s.session_type = NEW.session_type
      AND s.phase_id IS NOT DISTINCT FROM NEW.phase_id
    LIMIT 1;

    SELECT base_value INTO v_base_value
    FROM user_program_baselines
    WHERE user_program_id = NEW.user_program_id AND session_type = NEW.session_type;

    IF v_base_value IS NULL OR v_multiplier IS NULL THEN
      RAISE EXCEPTION 'ไม่พบ baseline หรือ spec สำหรับ session_type=% ของโปรแกรมนี้ (เช็ค user_program_baselines / session_type_specs)', NEW.session_type;
    END IF;

    NEW.planned_value := v_base_value * v_multiplier;
    NEW.unit := v_unit;
    NEW.is_bonus := COALESCE(v_is_bonus, false);
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_main_quest_before_insert
  BEFORE INSERT ON main_quest_instances
  FOR EACH ROW EXECUTE FUNCTION fn_main_quest_before_insert();


-- ============================================================================
-- SECTION D: Gap 1 — Weekly Cap Validation (real-time ต่อแถว)
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_check_weekly_cap()
RETURNS TRIGGER AS $$
DECLARE
  v_start_date DATE;
  v_program_template_id UUID;
  v_week_number INT;
  v_week_start DATE;
  v_week_end DATE;
  v_cap SMALLINT;
  v_existing_count INT;
BEGIN
  SELECT start_date, program_template_id INTO v_start_date, v_program_template_id
  FROM user_programs WHERE id = NEW.user_program_id;

  v_week_number := FLOOR((NEW.scheduled_date - v_start_date) / 7);
  v_week_start := v_start_date + (v_week_number * 7);
  v_week_end   := v_week_start + 6;

  SELECT weekly_cap INTO v_cap
  FROM session_type_specs
  WHERE program_template_id = v_program_template_id
    AND session_type = NEW.session_type
    AND phase_id IS NOT DISTINCT FROM NEW.phase_id
  LIMIT 1;

  IF v_cap IS NOT NULL THEN
    SELECT COUNT(*) INTO v_existing_count
    FROM main_quest_instances
    WHERE user_program_id = NEW.user_program_id
      AND session_type = NEW.session_type
      AND scheduled_date BETWEEN v_week_start AND v_week_end
      AND status <> 'skipped'
      AND id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::UUID);

    IF v_existing_count + 1 > v_cap THEN
      RAISE EXCEPTION 'เกิน weekly_cap: % ลงได้สูงสุด % ครั้ง/สัปดาห์ (สัปดาห์ % ถึง %) — ตอนนี้ลงไปแล้ว % ครั้ง',
        NEW.session_type, v_cap, v_week_start, v_week_end, v_existing_count;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_weekly_cap
  BEFORE INSERT OR UPDATE ON main_quest_instances
  FOR EACH ROW EXECUTE FUNCTION fn_check_weekly_cap();


-- ============================================================================
-- SECTION E: Gap 2 — Sequencing Rule Validation (เทียบวันข้างเคียงจริง)
-- ============================================================================
-- เช็คจาก scheduled_date -1 / +1 ที่มีอยู่จริงในตาราง ไม่ใช่ลำดับการ insert
-- รองรับ user แทรกวันที่ย้อนหลัง/ล่วงหน้าได้อย่างถูกต้อง

CREATE OR REPLACE FUNCTION fn_check_sequencing_rules()
RETURNS TRIGGER AS $$
DECLARE
  v_program_template_id UUID;
  r RECORD;
  v_prev_type session_type_enum;
  v_next_type session_type_enum;
BEGIN
  SELECT program_template_id INTO v_program_template_id
  FROM user_programs WHERE id = NEW.user_program_id;

  SELECT session_type INTO v_prev_type FROM main_quest_instances
  WHERE user_program_id = NEW.user_program_id
    AND scheduled_date = NEW.scheduled_date - 1
    AND status <> 'skipped'
    AND id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::UUID)
  LIMIT 1;

  SELECT session_type INTO v_next_type FROM main_quest_instances
  WHERE user_program_id = NEW.user_program_id
    AND scheduled_date = NEW.scheduled_date + 1
    AND status <> 'skipped'
    AND id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::UUID)
  LIMIT 1;

  FOR r IN
    SELECT * FROM program_sequencing_rules
    WHERE program_template_id = v_program_template_id
      AND (applies_to_phase_id IS NULL OR applies_to_phase_id = NEW.phase_id)
  LOOP
    IF r.rule_type = 'must_precede' THEN
      -- session_type_a ต้องอยู่วันก่อนหน้า session_type_b
      -- เช่น must_precede(easy, long_run): ถ้า NEW คือ long_run วันก่อนหน้าต้องเป็น easy
      IF NEW.session_type = r.session_type_b AND v_prev_type IS DISTINCT FROM r.session_type_a THEN
        RAISE EXCEPTION 'ผิดกฎ sequencing: % ต้องมี % ในวันก่อนหน้าเสมอ (วันก่อนหน้าตอนนี้คือ %)',
          r.session_type_b, r.session_type_a, COALESCE(v_prev_type::TEXT, 'ว่าง/ไม่มี');
      END IF;

    ELSIF r.rule_type = 'cannot_adjacent' THEN
      -- a และ b ห้ามอยู่ติดกัน (ทั้งก่อนหน้าและถัดไป) ไม่ว่า NEW จะเป็น a หรือ b
      IF (NEW.session_type = r.session_type_a AND
          (v_prev_type = r.session_type_b OR v_next_type = r.session_type_b))
      OR (NEW.session_type = r.session_type_b AND
          (v_prev_type = r.session_type_a OR v_next_type = r.session_type_a))
      THEN
        RAISE EXCEPTION 'ผิดกฎ sequencing: % และ % ห้ามลงติดกัน (ต้องมีวันพัก/ประเภทอื่นคั่น)',
          r.session_type_a, r.session_type_b;
      END IF;

    ELSIF r.rule_type = 'rest_after' THEN
      -- วันถัดไปจาก session_type_a ต้องว่าง (ไม่มี main_quest_instances ใดๆ)
      IF NEW.session_type = r.session_type_a AND v_next_type IS NOT NULL THEN
        RAISE EXCEPTION 'ผิดกฎ sequencing: หลัง % ต้องพัก 1 วัน (วันถัดไปมี % ลงอยู่แล้ว)',
          r.session_type_a, v_next_type;
      END IF;
      -- กรณี insert วันถัดไปหลังจากมี rest_after type อยู่ก่อนแล้ว
      IF v_prev_type = r.session_type_a THEN
        RAISE EXCEPTION 'ผิดกฎ sequencing: วันก่อนหน้าเป็น % ต้องเป็นวันพัก ห้ามลงเควสใดๆ ในวันนี้', r.session_type_a;
      END IF;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_sequencing_rules
  AFTER INSERT OR UPDATE ON main_quest_instances
  FOR EACH ROW EXECUTE FUNCTION fn_check_sequencing_rules();

-- NOTE: trigger นี้เป็น AFTER (ไม่ใช่ BEFORE) เพราะต้อง query main_quest_instances
-- ของแถวอื่นรวมถึงแถวที่เพิ่ง insert ไปแล้ว — ถ้า violate จะ RAISE EXCEPTION
-- ซึ่งจะ rollback การ insert นั้นทั้งหมดโดยอัตโนมัติ (ปลอดภัย ไม่ทิ้งข้อมูลผิดค้างไว้)


-- ============================================================================
-- ลำดับการทำงานของ trigger บน main_quest_instances (สำคัญ ต้องเรียงตามนี้)
-- ============================================================================
-- BEFORE INSERT:
--   1. trg_main_quest_before_insert   -> resolve phase_id, คำนวณ planned_value
--   2. trg_check_weekly_cap           -> เช็ค cap ต่อสัปดาห์
--   3. trg_main_quest_updated_at      -> (เดิม) set updated_at
-- AFTER INSERT/UPDATE:
--   4. trg_check_sequencing_rules     -> เช็คกฎลำดับจากวันข้างเคียงจริง
--   5. trg_program_completion_check   -> (เดิม) นับความคืบหน้าโปรแกรม
--
-- PostgreSQL รัน trigger ตามลำดับชื่อ (alphabetical) ภายใน timing เดียวกัน
-- ชื่อ trigger ด้านบนถูกตั้งให้เรียงตามตัวอักษรตรงกับลำดับที่ต้องการอยู่แล้ว
-- (before_insert < check_weekly_cap < updated_at) แต่ควรทดสอบจริงเพื่อยืนยัน
-- ============================================================================