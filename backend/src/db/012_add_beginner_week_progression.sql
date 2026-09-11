-- ============================================================================
-- Migration: 012_add_beginner_week_progression.sql
-- ต่อจาก 011_add_phase_progression_multiplier.sql ที่ทำ progressive overload
-- ให้ Lower/Upper Intermediate ผ่าน phase multiplier (base/build/peak) แล้ว
--
-- ปัญหา: Beginner ไม่มี program_phases เลย (phase_id เป็น NULL เสมอ) จึงผูก
-- multiplier กับ phase_id แบบ Intermediate ไม่ได้ — ทำให้ Beginner วิ่งปริมาณ
-- เท่าเดิมทุกสัปดาห์ตลอด 6-10 สัปดาห์ ไม่มี progression เลย
--
-- แก้โดย: คำนวณ multiplier แบบ dynamic จาก "สัดส่วนสัปดาห์ที่ผ่านไปของโปรแกรม"
-- แทนการอ่านจาก session_type_specs.multiplier ตรงๆ (เฉพาะ level = 'beginner'
-- เท่านั้น — Intermediate levels ยังใช้ multiplier จาก phase ตามเดิมจาก 011)
--
--   week_number    = สัปดาห์ปัจจุบันของ scheduled_date เทียบกับ start_date (1-indexed)
--   duration_weeks = program_templates.duration_weeks_min ของ Beginner (=6)
--   progress_ratio = (week_number - 1) / (duration_weeks - 1)   clamp [0,1]
--   multiplier     = 1.00 + progress_ratio * 0.30                -- ไต่ 1.00 -> 1.30
--
-- cap 1.30 (แทน 1.20 ของ Intermediate) เพราะ Beginner เป็น single-phase ยาว
-- 6-10 สัปดาห์ ไม่มี taper/race ให้ลดโหลดคืนทีหลัง ตรวจแล้วว่า x1.30 ไม่ทะลุ
-- value_high ของทุก session_type (easy 20->26 นาที, long_run 3->3.9 กม.)
-- ยังคงมี clamp ที่ value_high เป็น safety net เช่นเดิมจาก 011
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_main_quest_before_insert()
RETURNS TRIGGER AS $$
DECLARE
  v_program_template_id UUID;
  v_program_level program_level_enum;
  v_start_date DATE;
  v_duration_weeks_min SMALLINT;
  v_base_value NUMERIC(6,2);
  v_multiplier NUMERIC(5,2);
  v_value_high NUMERIC(6,2);
  v_unit session_unit_enum;
  v_is_bonus BOOLEAN;
  v_week_number INT;
  v_progress_ratio NUMERIC;
BEGIN
  -- Gap 3: auto-resolve phase_id ถ้าไม่ได้ระบุมา
  IF NEW.phase_id IS NULL THEN
    NEW.phase_id := fn_resolve_phase_id(NEW.user_program_id, NEW.scheduled_date);
  END IF;

  SELECT up.program_template_id, pt.level, up.start_date, pt.duration_weeks_min
  INTO v_program_template_id, v_program_level, v_start_date, v_duration_weeks_min
  FROM user_programs up
  JOIN program_templates pt ON pt.id = up.program_template_id
  WHERE up.id = NEW.user_program_id;

  -- auto-calc planned_value ถ้าไม่ได้ระบุมา (base_value x multiplier, clamp ที่ value_high)
  IF NEW.planned_value IS NULL THEN
    SELECT s.multiplier, s.unit, s.is_bonus, s.value_high
    INTO v_multiplier, v_unit, v_is_bonus, v_value_high
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

    -- Beginner: แทนที่ multiplier คงที่ (1.00) ด้วย week-based ramp เพราะไม่มี phase ให้ใช้
    IF v_program_level = 'beginner' THEN
      v_week_number := FLOOR((NEW.scheduled_date - v_start_date) / 7) + 1;

      IF v_duration_weeks_min IS NULL OR v_duration_weeks_min <= 1 THEN
        v_progress_ratio := 0;
      ELSE
        v_progress_ratio := LEAST(
          GREATEST((v_week_number - 1)::numeric / (v_duration_weeks_min - 1), 0),
          1
        );
      END IF;

      v_multiplier := 1.00 + v_progress_ratio * 0.30;
    END IF;

    NEW.planned_value := v_base_value * v_multiplier;
    IF v_value_high IS NOT NULL AND NEW.planned_value > v_value_high THEN
      NEW.planned_value := v_value_high;
    END IF;

    NEW.unit := v_unit;
    NEW.is_bonus := COALESCE(v_is_bonus, false);
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- trg_main_quest_before_insert มีอยู่แล้วและชี้ไปที่ฟังก์ชันนี้ (CREATE OR REPLACE
-- FUNCTION ด้านบนพอ ไม่ต้อง DROP/CREATE TRIGGER ใหม่)
