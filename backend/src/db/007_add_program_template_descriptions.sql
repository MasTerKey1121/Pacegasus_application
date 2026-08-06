-- Add descriptions for the Main Quest program selection screen.
ALTER TABLE program_templates
  ADD COLUMN IF NOT EXISTS description TEXT;

UPDATE program_templates
SET description = CASE level
  WHEN 'beginner' THEN 'โปรแกรมเริ่มต้นเพื่อสร้างความสม่ำเสมอในการวิ่งและพัฒนาความอึดพื้นฐาน'
  WHEN 'lower_intermediate' THEN 'โปรแกรมพัฒนาความเร็วและความอึดสำหรับเป้าหมายวิ่ง 10 กิโลเมตร'
  WHEN 'upper_intermediate' THEN 'โปรแกรมยกระดับความทนทานและการคุมเพซสำหรับเป้าหมายฮาล์ฟมาราธอน'
END
WHERE description IS NULL OR description = '';
