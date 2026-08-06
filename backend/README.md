# Pacegasus Backend

Express.js REST API สำหรับ Pacegasus — ครอบคลุมวันนี้:

1. **Auth**: Login/Register ด้วย Email + OTP 6 หลัก, และ Login/Register ด้วย Google
2. **Onboarding**: 4 ขั้นตอน (ข้อมูลพื้นฐาน, ประวัติบาดเจ็บ/โรคประจำตัว, เป้าหมาย, ประวัติการวิ่ง)
3. **Daily Wellness Check-in**: บันทึกความพร้อมร่างกายรายวัน (Slider 5 มิติ) — เป็น informational เท่านั้น ไม่ gate flow อื่นในระบบ
4. **Main Quest (Program)**: สมัคร/ดูตารางฝึกซ้อมรายสัปดาห์ (auto หรือ manual schedule) และจัดการเควสรายวัน
5. **Side Quest**: ดึงเควสเสริมประจำวันตามสภาพแวดล้อมและประเภทการฝึก, ผูกเควสเข้ากับ running session (รองรับ batch), อัปเดต progress, ปิดเควส, และดึงอัลบั้มภาพ

Database schema ถูกออกแบบใหม่ทั้งหมด (fresh install) อยู่ที่ `src/db/schema.sql`
ระบบ Auth + Onboarding **ผ่านการทดสอบจริง** (boot server, run migration, call ทุก endpoint) แล้วในสภาพแวดล้อมพัฒนา
ระบบ Daily Wellness Check-in **ยังไม่ได้ทดสอบจริง** — โค้ด service/controller/route/migration พร้อมแล้ว รอ verify กับโครงสร้างโปรเจกต์จริงและรันทดสอบ
ระบบ Main Quest (Program) และ Side Quest มี endpoint ให้เรียกแล้วตาม Postman collection — โปรดรัน migration/ตรวจ schema ที่เกี่ยวข้อง (ตาราง program/quest) ให้ครบก่อน boot จริง เอกสารด้านล่างอ้างอิงจากสเปกใน collection เป็นหลัก

---

## 1) ติดตั้ง

```bash
npm install
cp .env.example .env
```

แก้ไขค่าใน `.env`:

| ตัวแปร | คำอธิบาย |
|---|---|
| `DATABASE_URL` | connection string ของ PostgreSQL (local หรือ Supabase) |
| `JWT_ACCESS_SECRET` / `JWT_REFRESH_SECRET` | สุ่มสตริงยาวๆ ที่ไม่ซ้ำกัน (ใช้ `openssl rand -hex 32`) |
| `SMTP_HOST/PORT/USER/PASS` | สำหรับส่งอีเมล OTP — ถ้าใช้ Gmail ต้องสร้าง [App Password](https://myaccount.google.com/apppasswords) |
| `GOOGLE_CLIENT_ID` | OAuth 2.0 Client ID (ประเภท Web) จาก Google Cloud Console — ใช้ตรวจสอบ idToken ที่ frontend ส่งมา |

## 2) สร้างฐานข้อมูล

สร้าง database เปล่าไว้ก่อน (เช่น `createdb pacegasus`) จากนั้นรัน migration หลัก:

```bash
npm run migrate
```

คำสั่งนี้จะรัน `src/db/schema.sql` เพื่อสร้างตารางทั้งหมด (ปลอดภัยที่จะรันซ้ำ)

จากนั้นรัน migration เพิ่มเติมสำหรับ Daily Wellness Check-in (additive, แยกจาก schema.sql):

```bash
node src/db/migrate.js 003_create_daily_wellness_checkins.sql
```

## 3) รันเซิร์ฟเวอร์

```bash
npm run dev     # development (auto-reload)
npm start       # production
```

Default: `http://localhost:4000` — frontend (React Native/Expo) ที่รันบนเครื่องเดียวกันเชื่อมต่อผ่าน URL นี้ได้ทันที (ตั้งค่า `CLIENT_URL` ใน `.env` ให้ตรงกับ origin ของ frontend เพื่อให้ CORS ผ่าน)

---

## Database Schema สรุป

| ตาราง | หน้าที่ |
|---|---|
| `users` | บัญชีผู้ใช้หลัก, สถานะ onboarding |
| `user_auth_providers` | เชื่อมวิธี login (email / google) กับผู้ใช้ 1 คน |
| `otp_codes` | OTP ที่ hash แล้ว, มี `otp_ref` (รหัสอ้างอิง 6 หลักคู่กับแต่ละ OTP), expiry / max attempts / resend cooldown |
| `refresh_tokens` | เก็บ hash ของ refresh token สำหรับหมุนเวียน session |
| `user_basic_info` | Onboarding ขั้นตอนที่ 1 (วันเกิด, เพศ, ส่วนสูง, น้ำหนัก, จำนวนวันวิ่ง/สัปดาห์) — คอลัมน์ `running_experience_level` อยู่ในตารางนี้แต่ถูกคำนวณและเขียนที่ **ขั้นตอนที่ 4** เท่านั้น |
| `user_injury_summary` + `user_injuries` | Onboarding ขั้นตอนที่ 2 (มีประวัติบาดเจ็บ/โรคประจำตัวหรือไม่ + รายละเอียดแต่ละรายการ แยกด้วย `category`: `injury` หรือ `chronic_condition`) |
| `user_goals` | Onboarding ขั้นตอนที่ 3 (เป้าหมาย เช่น run_5k, marathon, lose_weight) |
| `user_running_history` | Onboarding ขั้นตอนที่ 4 (เคยวิ่งมาก่อนไหม, กำลังวิ่งอยู่ตอนนี้ไหม, วิ่งมากี่สัปดาห์, ระยะไกลที่สุดที่เคยวิ่ง) — ใช้เป็นฐานคำนวณ `running_experience_level` |
| `daily_wellness_checkins` | Check-in รายวัน 5 มิติ (sleep_quality, energy_level, muscle_soreness, stress_level, motivation) + wellness_score คำนวณอัตโนมัติ, 1 record/user/วัน, แก้ไขได้ — เพิ่มจาก migration `003_create_daily_wellness_checkins.sql` |
| `user_side_quest_instances` | Instance ของ side quest ต่อผู้ใช้ 1 รายการ (ผูกกับ `running_session_id` เมื่อเริ่มจริง), เก็บ `target_count` / `found_count` / `status` (`pending` → `in_progress` → `completed`) / `coin_awarded` / `started_at` / `completed_at` |
| `side_quest_templates` | แม่แบบ side quest แยกตาม `environment` x `training_type`, กำหนด `mechanic_type` (`collect_distance` / `pace_trigger` / `sprint_marker`), `km_per`, `cap_count`, `fixed_count`, `coin_reward_base` |
| `quest_album_photos` | รูปที่ผู้ใช้แนบระหว่าง/ตอนจบ side quest แต่ละ instance (พร้อมพิกัด GPS ถ้ามี) |

> หมายเหตุ: ตารางฝั่ง Main Quest (Program) และ Adaptive Training Engine ยังไม่ระบุรายละเอียดในเอกสารนี้ (ยังไม่มี migration file อ้างอิงชัดเจนในสรุปนี้) — โปรดตรวจสอบ `src/db/schema.sql` และ migration ล่าสุดในโปรเจกต์จริงประกอบ ก่อนเชื่อมกับ endpoint ในหมวด Main Quest ด้านล่าง
> ตาราง Gamification (Coin, Badge) ยังไม่รวมใน schema นี้ — จะเพิ่มเป็น migration ถัดไปเมื่อถึงคิวพัฒนา

---

## API Reference

Base URL: `http://localhost:4000/api`

### Auth

| Method | Path | Body | คำอธิบาย |
|---|---|---|---|
| POST | `/auth/otp/request` | `{ email, purpose: "register"\|"login" }` | ส่ง OTP 6 หลักไปที่อีเมล พร้อม `otp_ref` (ดูสเปกด้านล่าง) |
| POST | `/auth/otp/verify` | `{ email, otp, otpRef, displayName? }` | ยืนยัน OTP คู่กับ `otpRef` → คืน `accessToken` + `refreshToken` + `user` |
| POST | `/auth/google` | `{ idToken }` | Login/Register ด้วย Google ID Token (ฝั่ง frontend ทำ Google Sign-In แล้วส่ง idToken มา) |
| POST | `/auth/refresh` | `{ refreshToken }` | ขอ accessToken ใหม่ (หมุน refreshToken ด้วย) |
| POST | `/auth/logout` | `{ refreshToken }` | เพิกถอน refreshToken |
| GET | `/auth/me` | – (ต้องมี `Authorization: Bearer <accessToken>`) | ข้อมูลผู้ใช้ปัจจุบัน |

#### POST `/auth/otp/request`

ขอรหัส OTP ใหม่ ระบบจะสร้างรหัสอ้างอิง (`otpRef`) คู่กับ OTP ทุกครั้งที่ขอ เพื่อให้ frontend ใช้แยกแยะว่ากำลังยืนยันคำขอรอบไหน (กรณีขอ OTP ซ้ำหลายครั้งติดกัน)

**Request body**

| Field | Type | Required | คำอธิบาย |
|---|---|---|---|
| `email` | string | ✅ | อีเมลผู้ใช้ |
| `purpose` | `"login"` \| `"register"` | ไม่ (default `"login"`) | บริบทของการขอ OTP |

**Response `200`**

```json
{
  "success": true,
  "message": "ส่งรหัส OTP ไปยังอีเมลของคุณแล้ว",
  "data": {
    "email": "user@example.com",
    "expiresInMinutes": 5,
    "otpRef": "A1B2C3"
  }
}
```

Frontend ต้องเก็บ `otpRef` นี้ไว้ (เช่น ใน state) เพื่อส่งกลับไปพร้อมกับ OTP ตอนเรียก `/auth/otp/verify` — และอาจแสดง `otpRef` ให้ผู้ใช้เห็นบนหน้ากรอก OTP เพื่อให้เทียบกับรหัสอ้างอิงในอีเมลได้

**Error responses**

| Status | เงื่อนไข |
|---|---|
| `400` | `email` ไม่ถูกต้อง หรือ `purpose` ไม่ใช่ `login`/`register` |
| `404` | `purpose = "login"` แต่ไม่พบบัญชีผู้ใช้สำหรับอีเมลนี้ |
| `409` | `purpose = "register"` แต่อีเมลนี้ verified แล้ว |
| `429` | ขอ OTP ซ้ำเร็วเกินไป (ยังไม่พ้น resend cooldown) — message จะบอกจำนวนวินาทีที่ต้องรอ |

---

#### POST `/auth/otp/verify`

ยืนยัน OTP ต้องส่งทั้ง `otp` และ `otpRef` (ที่ได้จากการเรียก `/auth/otp/request` ล่าสุด) คู่กัน ระบบจะตรวจว่า `otpRef` ตรงกับ record ที่ยังไม่หมดอายุ/ยังไม่ถูกใช้ ก่อนเช็ครหัส OTP

**Request body**

| Field | Type | Required | คำอธิบาย |
|---|---|---|---|
| `email` | string | ✅ | อีเมลเดียวกับตอนขอ OTP |
| `otp` | string (6 หลัก) | ✅ | รหัส OTP ที่ได้รับทางอีเมล |
| `otpRef` | string (6 ตัวอักษร) | ✅ | รหัสอ้างอิงที่ได้จาก response ของ `/auth/otp/request` |
| `displayName` | string | ไม่ | ใช้ตั้งชื่อผู้ใช้ครั้งแรก (เช่น ตอน register) |

**Response `200`**

```json
{
  "success": true,
  "message": "เข้าสู่ระบบสำเร็จ",
  "data": {
    "user": { "...": "..." },
    "accessToken": "...",
    "refreshToken": "..."
  }
}
```

**Error responses**

| Status | เงื่อนไข |
|---|---|
| `400` | `email`/`otp`/`otpRef` รูปแบบไม่ถูกต้อง, ไม่พบคำขอ OTP ที่ตรงกับ `email` + `otpRef`, OTP หมดอายุ, หรือรหัสไม่ถูกต้อง |
| `429` | กรอกรหัสผิดเกินจำนวนครั้งที่กำหนด (`max_attempts`) |

---

### Onboarding (ต้อง Login ก่อน — แนบ `Authorization: Bearer <accessToken>` ทุก request)

| Method | Path | คำอธิบาย |
|---|---|---|
| GET | `/onboarding/status` | ขั้นตอนปัจจุบันและสถานะ completed |
| PUT | `/onboarding/step1` | บันทึกข้อมูลพื้นฐาน (วันเกิด, เพศ, ส่วนสูง, น้ำหนัก, วันวิ่ง/สัปดาห์) |
| PUT | `/onboarding/step2` | บันทึกประวัติบาดเจ็บและโรคประจำตัว (แยกกันคนละชุด) |
| PUT | `/onboarding/step3` | บันทึกเป้าหมาย |
| PUT | `/onboarding/step4` | บันทึกประวัติการวิ่ง → คำนวณ `running_experience_level` และเขียนเข้า `user_basic_info` → ตั้ง `onboarding_completed = true` |

> **หมายเหตุ:** `running_experience_level` **ไม่ได้** ถูกตั้งค่าใน step1 แม้จะเก็บอยู่ในตาราง `user_basic_info` — ระบบจะคำนวณค่านี้จากข้อมูล step4 (`hasRunBefore`, `isCurrentlyRunning`, `weeksRunning`, `longestDistanceKm`) แล้วเขียนกลับเข้าตาราง `user_basic_info` ตอนจบ step4 เท่านั้น

ตัวอย่าง body ของแต่ละ step อยู่ใน `src/utils/validators.js` (Joi schema เป็น source of truth ของ field ที่รับ)

### Users

| Method | Path | คำอธิบาย |
|---|---|---|
| GET | `/users/me/full` | รวมข้อมูลผู้ใช้ + basic info + injury/chronic condition + goals + running history ในครั้งเดียว (เหมาะกับหน้า Home/Profile) |
| Delete | `/users/me` | ลบบัญชีผู้ใช้โดยผู้ใช้เอง |
---

### Daily Wellness Check-in (ต้อง Login ก่อน — แนบ `Authorization: Bearer <accessToken>` ทุก request)

> **สถานะ:** ยังไม่ได้ boot/ทดสอบจริงเหมือนโซน Auth/Onboarding — โค้ดพร้อมตาม spec ในเอกสารโปรเจกต์ แต่ยังไม่ผ่านการรันทดสอบ end-to-end
> **หลักการ:** informational only, ไม่ gate onboarding/training flow ใดๆ — ทำได้วันละ 1 record, แก้ไขทับของวันเดิมได้ (ไม่สร้างซ้ำ)

| Method | Path | Body | คำอธิบาย |
|---|---|---|---|
| GET | `/wellness-checkin/today` | – | เช็คสถานะว่าวันนี้ทำ check-in แล้วหรือยัง (`status: "done" \| "not_done"`) |
| POST | `/wellness-checkin` | ดูด้านล่าง | สร้าง record ของวันนี้ (ทำได้ 1 ครั้ง/วัน) |
| PUT | `/wellness-checkin` | ดูด้านล่าง | แก้ไข record ของวันนี้ |
| GET | `/wellness-checkin/history?days=30` | – | ดึงประวัติย้อนหลัง N วัน (default 30) สำหรับกราฟ/แนวโน้ม |

**Request body (POST / PUT)**

| Field | Type | Required | คำอธิบาย |
|---|---|---|---|
| `sleepQuality` | integer 1-5 | ✅ | คุณภาพการนอน (1=แย่ที่สุด, 5=ดีที่สุด) |
| `energyLevel` | integer 1-5 | ✅ | ระดับพลังงาน |
| `muscleSoreness` | integer 1-5 | ✅ | อาการปวดกล้ามเนื้อ/DOMS (1=ไม่ปวดเลย, 5=ปวดมาก) |
| `stressLevel` | integer 1-5 | ✅ | ระดับความเครียด (1=ผ่อนคลาย, 5=เครียดมาก) |
| `motivation` | integer 1-5 | ✅ | แรงจูงใจในการซ้อมวันนี้ |
| `note` | string ≤500 ตัวอักษร | ไม่ | บันทึกเพิ่มเติม |

**Response `201` (POST) / `200` (PUT)**

```json
{
  "success": true,
  "data": {
    "status": "done",
    "record": {
      "checkin_id": "...",
      "checkin_date": "2026-07-21",
      "sleep_quality": 4,
      "energy_level": 3,
      "muscle_soreness": 2,
      "stress_level": 2,
      "motivation": 4,
      "wellness_score": 3.4,
      "note": null,
      "created_at": "...",
      "updated_at": "..."
    }
  }
}
```

**Error responses**

| Status | เงื่อนไข |
|---|---|
| `400` | field ใดฟิลด์หนึ่งไม่อยู่ในช่วง 1-5 หรือขาดฟิลด์ที่จำเป็น |
| `409` (เฉพาะ POST) | ทำ check-in ของวันนี้ไปแล้ว — ให้เรียก PUT แทน |
| `404` (เฉพาะ PUT) | ยังไม่มี check-in ของวันนี้ให้แก้ไข — ให้เรียก POST ก่อน |

---

### Main Quest (Program) (ต้อง Login ก่อน — แนบ `Authorization: Bearer <accessToken>` ทุก request)

> **สถานะ:** เอกสารส่วนนี้อ้างอิงจาก Postman collection ที่ให้มา ยังไม่มีข้อมูลยืนยันว่าผ่านการทดสอบ end-to-end แล้วหรือยัง — โปรดตรวจสอบกับ service/controller จริงก่อนใช้งาน production
> **หลักการ:** ผู้ใช้สมัครโปรแกรมฝึกซ้อม (`level` + `scheduleMode`) หนึ่งครั้ง จากนั้นดูตาราง/จัดการเควสรายวันได้ผ่าน endpoint ด้านล่าง Base path คือ `/api/v1/programs` (คนละ prefix กับ endpoint อื่นที่เป็น `/api`)

| Method | Path | Body / Query | คำอธิบาย |
|---|---|---|---|
| GET | `/programs/templates` | – | ดึง Main Quest program template พร้อม description, phases, session specs และ sequencing rules สำหรับหน้าเลือกโปรแกรม |
| POST | `/v1/programs/start` | `{ level, scheduleMode }` | สมัครโปรแกรมฝึกซ้อมให้ผู้ใช้ (ทำครั้งเดียว) |
| GET | `/v1/programs/current/week` | – | ดึงตารางฝึกของสัปดาห์ปัจจุบัน (ต้องสมัครโปรแกรมก่อน) |
| POST | `/v1/programs/quests` | `{ scheduledDate, sessionType }` | เพิ่มเควสวันเดียวเอง — ใช้ได้เฉพาะโปรแกรมที่ `scheduleMode = "manual"` |
| POST | `/programs/quests/batch` | `{ quests: [{ scheduledDate, sessionType }] }` | เพิ่มเควสแบบหลายรายการ (1-7 รายการ) ใน transaction เดียว สำหรับโปรแกรม manual |
| DELETE | `/v1/programs/quests/:questId` | – (path param `questId`) | ลบเควสที่ยังอยู่สถานะ pending |
| GET | `/v1/programs/quests?from=&to=` | query `from`, `to` (ไม่บังคับ) | ดูเควสตามช่วงวันที่ ถ้าไม่ส่งจะ fallback เป็นสัปดาห์ปัจจุบัน |

#### POST `/v1/programs/start`

สมัครโปรแกรมฝึกซ้อม (Main Quest) ให้ผู้ใช้ที่ login อยู่

**Request body**

| Field | Type | Required | คำอธิบาย |
|---|---|---|---|
| `level` | `"beginner"` \| `"lower_intermediate"` \| `"upper_intermediate"` | ✅ | ระดับความสามารถของผู้ใช้ |
| `scheduleMode` | `"auto"` \| `"manual"` | ✅ | `auto` = ระบบสร้างตารางฝึกทั้งโปรแกรมให้อัตโนมัติ, `manual` = ผู้ใช้ลงตารางฝึกรายวันเอง |

**Response `201`**

```json
{
  "success": true,
  "message": "สมัครโปรแกรมสำเร็จ — สร้างตารางฝึกทั้งโปรแกรมให้อัตโนมัติแล้ว",
  "data": { "...": "..." }
}
```

**Error responses**

| Status | เงื่อนไข |
|---|---|
| `400` | `level`/`scheduleMode` ไม่อยู่ใน enum ที่กำหนด |
| `401` | ไม่ได้ login |

---

#### GET `/v1/programs/current/week`

ดึงตารางฝึกของสัปดาห์ปัจจุบันของผู้ใช้ที่ login อยู่ (ต้อง `POST /v1/programs/start` มาก่อนแล้ว)

**Response `200`**

```json
{ "success": true, "data": { "...": "..." } }
```

**Error responses**

| Status | เงื่อนไข |
|---|---|
| `401` | ไม่ได้ login |
| `404` | ผู้ใช้ยังไม่ได้สมัครโปรแกรม |

---

#### POST `/v1/programs/quests`

ลงเควสวันเดียวเอง — ใช้ได้เฉพาะโปรแกรมที่ `scheduleMode = "manual"` เท่านั้น

**Request body**

| Field | Type | Required | คำอธิบาย |
|---|---|---|---|
| `scheduledDate` | string (ISO date) | ✅ | วันที่จะลงเควส เช่น `"2026-07-25"` |
| `sessionType` | `"easy"` \| `"tempo"` \| `"vo2max"` \| `"long_run"` | ✅ | ต้องตรงกับ `AUTO_TEMPLATES` ใน `programService.js` — คนละ enum กับ `trainingType` ของ Side Quest |

**Response `201`**

```json
{ "success": true, "message": "เพิ่มเควสสำเร็จ", "data": { "...": "..." } }
```

**Error responses**

| Status | เงื่อนไข |
|---|---|
| `400` | `scheduledDate` ไม่ใช่ ISO date หรือ `sessionType` ไม่อยู่ใน enum |
| `401` | ไม่ได้ login |

---

#### DELETE `/v1/programs/quests/:questId`

ลบเควสที่ยัง pending (ยังไม่เริ่ม/ยังไม่เสร็จ)

**Path params**

| Key | Type | Required | คำอธิบาย |
|---|---|---|---|
| `questId` | string (UUID) | ✅ | id ของเควสที่จะลบ ต้องเป็น UUID ที่ถูกต้อง |

**Response `200`**

```json
{ "success": true, "message": "ลบเควสสำเร็จ", "data": { "...": "..." } }
```

**Error responses**

| Status | เงื่อนไข |
|---|---|
| `400` | `questId` ไม่ใช่ UUID ที่ถูกต้อง |
| `401` | ไม่ได้ login |
| `404` | ไม่พบเควส หรือเควสไม่ใช่ของผู้ใช้นี้ |
| `409` | เควสไม่ได้อยู่ในสถานะ pending แล้ว ลบไม่ได้ |

---

#### GET `/v1/programs/quests?from=&to=`

ดูเควสตามช่วงวันที่ ถ้าไม่ส่ง `from`/`to` เลยจะ fallback เป็นสัปดาห์ปัจจุบัน

⚠️ **ข้อจำกัดสำคัญ**: ถ้าจะส่ง query มาต้องส่งทั้งคู่พร้อมกัน (`from` กับ `to`) — ส่งแค่ตัวใดตัวหนึ่งอย่างเดียวไม่ได้ (validation error) และ `to` ต้องเป็นวันที่ **หลัง** `from` เท่านั้น

**Query params**

| Key | Type | Required | คำอธิบาย |
|---|---|---|---|
| `from` | string (ISO date) | ไม่ (ถ้าส่งต้องส่งคู่กับ `to`) | วันเริ่มต้นของช่วง |
| `to` | string (ISO date) | ไม่ (ถ้าส่งต้องส่งคู่กับ `from`, ต้องมากกว่า `from`) | วันสิ้นสุดของช่วง |

**Response `200`**

```json
{ "success": true, "data": { "...": "..." } }
```

**Error responses**

| Status | เงื่อนไข |
|---|---|
| `400` | ส่งแค่ `from` หรือ `to` อย่างเดียว, รูปแบบไม่ใช่ ISO date, หรือ `to` ไม่มากกว่า `from` |
| `401` | ไม่ได้ login |

---

### Side Quest (ต้อง Login ก่อน — แนบ `Authorization: Bearer <accessToken>` ทุก request)

> **สถานะ:** เอกสารส่วนนี้อ้างอิงจาก Postman collection ที่ให้มา ยังไม่มีข้อมูลยืนยันว่าผ่านการทดสอบ end-to-end แล้วหรือยัง — โปรดตรวจสอบกับ service/controller จริงก่อนใช้งาน production
> **หลักการ:** ผู้ใช้ดึง side quest ของวันนี้ (สุ่มจาก template ตาม environment/trainingType, สร้าง instance ผูก user ทันทีแบบยังไม่ผูก session) → เลือกเควสที่ต้องการเริ่มแล้วผูกเข้ากับ running session (**รองรับส่งพร้อมกันหลายรายการในคำขอเดียว — สูงสุด 3 รายการ, ทำงานเป็น transaction เดียวแบบ all-or-nothing**) → อัปเดต progress ระหว่างวิ่ง → ปิดเควสเมื่อสำเร็จ

| Method | Path | Body / Query | คำอธิบาย |
|---|---|---|---|
| GET | `/quests/side?environment=&trainingType=` | query `environment`, `trainingType` (บังคับทั้งคู่) | ดึงรายการ Side Quest ของวันนี้ตามสภาพแวดล้อมและประเภทการฝึกที่เลือก |
| POST | `/quests/running-sessions/:id/side-quests` | `{ instances: [...] }` | เริ่ม/ผูก side quest instance เข้ากับ running session — **แบบ batch สูงสุด 3 รายการต่อคำขอ** |
| PATCH | `/side-quests/:id/progress` | `{ increment? , foundCount?, photoUrl?, gpsLat?, gpsLng? }` | อัปเดต progress ของ side quest ที่เริ่มไปแล้ว |
| PATCH | `/side-quests/:id/finish` | – | ปิด side quest ด้วยสถานะ `completed` (เติม `found_count` ให้เต็ม `target_count` อัตโนมัติถ้ายังไม่ครบ) |
| GET | `/side-quests/:id/album` | – | ดึงอัลบั้มภาพที่แนบไว้ระหว่าง/ตอนจบ side quest instance นี้ |

#### GET `/quests/side?environment=&trainingType=`

**Query params**

| Key | Type | Required | คำอธิบาย |
|---|---|---|---|
| `environment` | `"park"` \| `"road"` \| `"city"` \| `"treadmill"` \| `"trail"` | ✅ | สภาพแวดล้อมที่จะวิ่ง |
| `trainingType` | `"easy"` \| `"long_run"` \| `"tempo"` \| `"interval"` | ✅ | ประเภทการฝึกวันนี้ — คนละ enum กับ `sessionType` ของ Main Quest (ตรงนี้ไม่มี `"vo2max"` แต่มี `"interval"` แทน) |

**Response `200`**

```json
{
  "success": true,
  "data": {
    "environment": "park",
    "trainingType": "easy",
    "plannedDistanceKm": 5,
    "quests": [
      {
        "instanceId": "...",
        "title": "...",
        "description": "...",
        "targetObject": "...",
        "mechanicType": "collect_distance",
        "targetCount": 3,
        "foundCount": 0,
        "status": "pending",
        "coinRewardBase": 10
      }
    ]
  }
}
```

**Error responses**

| Status | เงื่อนไข |
|---|---|
| `400` | `environment`/`trainingType` ไม่อยู่ใน enum ที่กำหนด |
| `401` | ไม่ได้ login |
| `404` | ไม่พบ side quest template ที่ตรงกับ `environment` x `trainingType` |

> หมายเหตุ: `sessionType` (Main Quest) และ `trainingType` (Side Quest) เป็นคนละ enum กัน — ระวังอย่าใช้ค่าสลับกันตอนเรียก 2 endpoint นี้คู่กัน (เช่น `"vo2max"` มีเฉพาะฝั่ง Main Quest, `"interval"` มีเฉพาะฝั่ง Side Quest)

---

#### POST `/quests/running-sessions/:id/side-quests`

ผูก side quest instance ที่เลือกไว้ (จาก `GET /quests/side`) เข้ากับ running session ที่สร้างไว้แล้ว **แบบ batch** — ส่งได้หลายรายการพร้อมกันในคำขอเดียว ทำงานเป็น transaction เดียว (all-or-nothing) ถ้ารายการใดรายการหนึ่งใน batch ผิดพลาด จะ rollback ทั้งหมด

**Path params**

| Key | Type | Required | คำอธิบาย |
|---|---|---|---|
| `id` | string (UUID) | ✅ | id ของ running session ที่จะผูกเควสเข้าไป |

**Request body**

| Field | Type | Required | คำอธิบาย |
|---|---|---|---|
| `instances` | array | ✅ | รายการ side quest ที่ต้องการเริ่ม 1-3 รายการ |
| `instances[].instanceId` | string (UUID) | ✅ (xor กับ `sideQuestTemplateId`) | instanceId ที่ได้จาก `GET /quests/side` |
| `instances[].sideQuestTemplateId` | string (UUID) | ✅ (xor กับ `instanceId`) | สร้าง instance ใหม่ตรงจาก template แทนการใช้ instance ที่มีอยู่ |

แต่ละ item ต้องระบุ `instanceId` หรือ `sideQuestTemplateId` อย่างใดอย่างหนึ่งเท่านั้น (ห้ามส่งทั้งคู่หรือไม่ส่งเลย)

**Response `201`**

```json
{
  "success": true,
  "data": [
    {
      "id": "...",
      "runningSessionId": "...",
      "userId": "...",
      "sideQuestTemplateId": "...",
      "targetCount": 3,
      "foundCount": 0,
      "status": "in_progress",
      "coinAwarded": false,
      "startedAt": "...",
      "completedAt": null
    }
  ]
}
```

`data` เป็น **array** ตามจำนวน instance ที่ส่งมาใน `instances`

**Error responses**

| Status | เงื่อนไข |
|---|---|
| `400` | body ไม่ผ่าน validation (เช่น `instances` ว่าง/เกิน 3 รายการ, item ใดไม่ระบุหรือระบุทั้ง `instanceId` และ `sideQuestTemplateId` พร้อมกัน) |
| `400` | จำนวน quest ที่ active อยู่แล้วใน session รวมกับที่ส่งมาใหม่เกิน limit (3 ต่อ session) |
| `401` | ไม่ได้ login |
| `404` | ไม่พบ `instanceId`/`sideQuestTemplateId` ที่ระบุ (ของรายการใดรายการหนึ่งใน batch จะทำให้ทั้ง batch fail) |
| `409` | instance นั้น `completed` ไปแล้ว, ผูกกับ running session อื่นอยู่แล้ว, หรือ template นั้นถูกเริ่มไปแล้วใน session นี้ |

---

#### PATCH `/side-quests/:id/progress`

อัปเดต progress ของ side quest ที่เริ่มไปแล้ว สามารถแนบ `photoUrl` พร้อมพิกัด GPS เพิ่มเติมได้ (จะถูกบันทึกลงอัลบั้มของ instance นั้น)

**Path params**

| Key | Type | Required | คำอธิบาย |
|---|---|---|---|
| `id` | string (UUID) | ✅ | id ของ side quest instance |

**Request body**

| Field | Type | Required | คำอธิบาย |
|---|---|---|---|
| `increment` | integer 1-100 | ไม่ (xor กับ `foundCount`) | เพิ่ม `found_count` ทีละเท่านี้ |
| `foundCount` | integer ≥0 | ไม่ (xor กับ `increment`) | ตั้งค่า `found_count` ตรงๆ |
| `photoUrl` | string (URI) | ไม่ | URL รูปที่แนบ — จะถูกบันทึกเข้า `quest_album_photos` |
| `gpsLat` | number -90 ถึง 90 | ไม่ | พิกัด latitude ตอนถ่ายรูป |
| `gpsLng` | number -180 ถึง 180 | ไม่ | พิกัด longitude ตอนถ่ายรูป |

เมื่อ `found_count` ถึง `target_count` แล้ว ระบบจะตั้ง `status = "completed"` และ `completed_at` ให้อัตโนมัติ

**Response `200`**

```json
{
  "success": true,
  "data": {
    "id": "...",
    "runningSessionId": "...",
    "targetCount": 3,
    "foundCount": 2,
    "status": "in_progress",
    "coinAwarded": false,
    "startedAt": "...",
    "completedAt": null
  }
}
```

**Error responses**

| Status | เงื่อนไข |
|---|---|
| `400` | body ไม่ผ่าน validation (เช่น `increment`/`foundCount` นอกช่วงที่กำหนด, `photoUrl` ไม่ใช่ URI ที่ถูกต้อง) |
| `401` | ไม่ได้ login |
| `404` | ไม่พบ side quest instance นี้ หรือไม่ใช่ของผู้ใช้ปัจจุบัน |

---

#### PATCH `/side-quests/:id/finish`

ปิด side quest ด้วยสถานะ `completed` — ถ้า `found_count` ยังไม่ถึง `target_count` ระบบจะเติมให้เต็มอัตโนมัติ (`GREATEST(found_count, target_count)`)

**Path params**

| Key | Type | Required | คำอธิบาย |
|---|---|---|---|
| `id` | string (UUID) | ✅ | id ของ side quest instance |

**Response `200`**

```json
{
  "success": true,
  "data": {
    "id": "...",
    "targetCount": 3,
    "foundCount": 3,
    "status": "completed",
    "completedAt": "..."
  }
}
```

**Error responses**

| Status | เงื่อนไข |
|---|---|
| `401` | ไม่ได้ login |
| `404` | ไม่พบ side quest instance นี้ หรือไม่ใช่ของผู้ใช้ปัจจุบัน |

---

#### GET `/side-quests/:id/album`

ดึงรายการรูปที่แนบไว้ระหว่าง/ตอนจบ side quest instance นี้ (เรียงจากล่าสุดไปเก่าสุด)

**Path params**

| Key | Type | Required | คำอธิบาย |
|---|---|---|---|
| `id` | string (UUID) | ✅ | id ของ side quest instance |

**Response `200`**

```json
{
  "success": true,
  "data": [
    {
      "id": "...",
      "user_side_quest_instance_id": "...",
      "photo_url": "...",
      "gps_lat": 13.7563,
      "gps_lng": 100.5018,
      "captured_at": "..."
    }
  ]
}
```

**Error responses**

| Status | เงื่อนไข |
|---|---|
| `401` | ไม่ได้ login |
| `404` | ไม่พบ side quest instance นี้ หรือไม่ใช่ของผู้ใช้ปัจจุบัน |

---

## หมายเหตุด้านความปลอดภัย

- OTP และ refresh token ไม่เคยถูกเก็บเป็น plaintext — เก็บเป็น bcrypt hash (OTP) และ sha256 hash (refresh token)
- `otp_ref` ไม่ใช่ secret (ไม่ hash) — ใช้เพื่อระบุ "คำขอรอบไหน" เท่านั้น ความปลอดภัยของ OTP ยังขึ้นอยู่กับตัวรหัส OTP 6 หลักที่ hash ไว้เป็นหลัก
- Rate limit บน endpoint ขอ/ยืนยัน OTP กันการยิงสแปม
- Access token อายุสั้น (`15m` default) + refresh token หมุนทุกครั้งที่ใช้ (rotation) เพื่อลดความเสี่ยงจาก token รั่วไหล
- Onboarding, Wellness Check-in, Main Quest (Program) และ Side Quest routes ทุกตัวถูกป้องกันด้วย JWT middleware (`requireAuth`)
- POST `/quests/running-sessions/:id/side-quests` ครอบทั้ง batch ด้วย DB transaction พร้อม row-level lock (`FOR UPDATE`) เพื่อกัน race condition เวลามีคำขอพร้อมกันหลายอันมาแข่งกันผูกเควสเข้า session เดียวกัน
