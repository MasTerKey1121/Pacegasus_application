-- ============================================================================
-- Migration: 011_add_phase_progression_multiplier.sql
-- ปัญหาเดิม: session_type_specs.multiplier ทุกแถวเป็น 1.00 (placeholder) มาตั้งแต่
-- schema.sql (ดู comment บรรทัด 526-528 ของไฟล์นั้น) ทำให้ base/build/peak ของ
-- Lower/Upper Intermediate ใช้ planned_value เท่ากันทุก phase (ไม่มี progressive
-- overload จริง) เพราะ base_value ถูก fix ไว้ตั้งแต่ start program (= value_low)
-- และไม่เคยถูกอัปเดตอีกเลย (ดู createBaselines() ใน programService.js)
--
-- Migration นี้:
-- 1) ตั้ง multiplier ตาม phase_code สำหรับ Lower/Upper Intermediate:
--    base=1.00, build=1.10 (+10%), peak=1.20 (+20%) ตามหลัก "ไม่เพิ่มปริมาณเกิน
--    ~10%/ขั้น" (แนวทางเดียวกับที่ ACWR ใช้เตือนเรื่องเพิ่มโหลดเร็วเกินไป — Qin,
--    Li และ Chen ที่รายงานอ้างไว้ในบทที่ 2.3.3) — ตัวเลข 10%/20% นี้เป็นค่าที่ทีม
--    ออกแบบเอง ไม่ได้ derive ตรงจากงานวิจัยที่อ้างอิง ต้อง validate หลัง Beta Test
-- 2) taper_easy / race ปล่อย multiplier = 1.00 เดิม เพราะ spec ของสอง phase นี้
--    เป็นแถวแยกที่มี value_low/high ลดไว้แล้วในตัวเอง (ดู schema.sql บรรทัด 467-475,
--    508-514) คูณซ้ำอีกชั้นจะลดผิดซ้ำสอง
-- 3) เพิ่ม clamp ใน fn_main_quest_before_insert() กัน planned_value ทะลุ value_high
--    ของ spec แถวนั้น เผื่อกรณีในอนาคตมีคนแก้ value_low/high หรือ multiplier แล้ว
--    ลืมเช็คช่วงให้สอดคล้องกัน (ตอนนี้ตรวจมือแล้วว่า ×1.20 ไม่ทะลุ value_high ของ
--    ทุก session_type ที่มีอยู่ แต่ clamp ไว้เป็น safety net ระยะยาว)
-- ============================================================================


-- ----------------------------------------------------------------------------
-- SECTION 1: ตั้ง multiplier ตาม phase_code (เฉพาะ Lower/Upper Intermediate)
-- ----------------------------------------------------------------------------

UPDATE session_type_specs s
SET multiplier = CASE p.phase_code
  WHEN 'base' THEN 1.00
  WHEN 'build' THEN 1.10
  WHEN 'peak' THEN 1.20
  ELSE s.multiplier  -- taper_easy / race: ไม่แตะ ปล่อยเดิม (1.00)
END
FROM program_phases p
WHERE s.phase_id = p.id
  AND p.phase_code IN ('base', 'build', 'peak');

-- Beginner ไม่มี phase (phase_id ทุกแถวเป็น NULL) ไม่ต้องแก้ — คง multiplier = 1.00
-- ตลอดโปรแกรมตามที่ออกแบบไว้ (เป้าหมายคือความสม่ำเสมอ ไม่ใช่เพิ่มโหลด)


-- ----------------------------------------------------------------------------
-- SECTION 2: Clamp planned_value ไม่ให้เกิน value_high ของ spec แถวนั้น
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_main_quest_before_insert()
RETURNS TRIGGER AS $$
DECLARE
  v_program_template_id UUID;
  v_base_value NUMERIC(6,2);
  v_multiplier NUMERIC(5,2);
  v_value_high NUMERIC(6,2);
  v_unit session_unit_enum;
  v_is_bonus BOOLEAN;
BEGIN
  -- Gap 3: auto-resolve phase_id ถ้าไม่ได้ระบุมา
  IF NEW.phase_id IS NULL THEN
    NEW.phase_id := fn_resolve_phase_id(NEW.user_program_id, NEW.scheduled_date);
  END IF;

  SELECT program_template_id INTO v_program_template_id
  FROM user_programs WHERE id = NEW.user_program_id;

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
