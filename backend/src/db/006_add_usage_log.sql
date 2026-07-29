-- Migration: create_usage_log
-- วัตถุประสงค์: บันทึก request/response ของทุก API call ผ่าน middleware
-- ใช้กับ: Supabase PostgreSQL (Pacegasus)

-- ============================================================
-- UP
-- ============================================================

CREATE TABLE IF NOT EXISTS usage_log (
    id                  BIGSERIAL PRIMARY KEY,

    -- ผู้ใช้ (nullable เพราะ guest หรือ endpoint public ก็เรียกได้)
    user_id             UUID REFERENCES users(id) ON DELETE SET NULL,

    -- ข้อมูล Request
    method              VARCHAR(10)     NOT NULL,
    api_url             TEXT            NOT NULL,
    endpoint_name       VARCHAR(150),
    request_headers     JSONB,
    request_body        JSONB,
    request_ip          INET,
    user_agent          TEXT,

    -- ข้อมูล Response
    response_status     SMALLINT        NOT NULL,
    response_headers    JSONB,
    response_body       JSONB,
    response_time_ms    INTEGER,

    -- Metadata
    error_message       TEXT,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT now()
);

COMMENT ON TABLE usage_log IS 'บันทึก log ของทุก API request/response ผ่าน middleware กลาง';
COMMENT ON COLUMN usage_log.request_body IS 'ผ่านการ sanitize field อ่อนไหว (password, token) ก่อน insert แล้ว';
COMMENT ON COLUMN usage_log.response_body IS 'ผ่านการ sanitize field อ่อนไหวก่อน insert แล้ว';

-- Index สำหรับ query ที่จะใช้บ่อย (filter ตามผู้ใช้, ช่วงเวลา, สถานะ, endpoint)
CREATE INDEX IF NOT EXISTS idx_usage_log_user_id    ON usage_log(user_id);
CREATE INDEX IF NOT EXISTS idx_usage_log_created_at ON usage_log(created_at);
CREATE INDEX IF NOT EXISTS idx_usage_log_status     ON usage_log(response_status);
CREATE INDEX IF NOT EXISTS idx_usage_log_endpoint   ON usage_log(endpoint_name);

-- ============================================================
-- DOWN (rollback) — รันแยกเองถ้าต้องการย้อนกลับ
-- ============================================================
-- DROP INDEX IF EXISTS idx_usage_log_endpoint;
-- DROP INDEX IF EXISTS idx_usage_log_status;
-- DROP INDEX IF EXISTS idx_usage_log_created_at;
-- DROP INDEX IF EXISTS idx_usage_log_user_id;
-- DROP TABLE IF EXISTS usage_log;