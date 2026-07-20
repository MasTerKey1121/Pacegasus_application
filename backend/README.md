# Pacegasus Backend

Express.js REST API สำหรับ Pacegasus — ครอบคลุมวันนี้:

1. **Auth**: Login/Register ด้วย Email + OTP 6 หลัก, และ Login/Register ด้วย Google
2. **Onboarding**: 4 ขั้นตอน (ข้อมูลพื้นฐาน, ประวัติบาดเจ็บ, เป้าหมาย, ประวัติการวิ่ง)

Database schema ถูกออกแบบใหม่ทั้งหมด (fresh install) อยู่ที่ `src/db/schema.sql`
ระบบนี้**ผ่านการทดสอบจริง** (boot server, run migration, call ทุก endpoint) แล้วในสภาพแวดล้อมพัฒนา

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

สร้าง database เปล่าไว้ก่อน (เช่น `createdb pacegasus`) จากนั้นรัน migration:

```bash
npm run migrate
```

คำสั่งนี้จะรัน `src/db/schema.sql` เพื่อสร้างตารางทั้งหมด (ปลอดภัยที่จะรันซ้ำ)

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
| `user_basic_info` | Onboarding ขั้นตอนที่ 1 (อายุ, เพศ, ส่วนสูง, น้ำหนัก, ระดับประสบการณ์, ระยะทาง/สัปดาห์) |
| `user_injury_summary` + `user_injuries` | Onboarding ขั้นตอนที่ 2 (มีประวัติบาดเจ็บหรือไม่ + รายละเอียดแต่ละจุด) |
| `user_goals` | Onboarding ขั้นตอนที่ 3 (เป้าหมาย เช่น run_5k, marathon, lose_weight) |
| `user_running_history` | Onboarding ขั้นตอนที่ 4 (ประวัติการวิ่ง, best time, สภาพแวดล้อมที่ชอบ) |

> หมายเหตุ: ตาราง Gamification (Side Quests, Coin, Badge) และ Adaptive Training Engine ยังไม่รวมใน schema นี้ — จะเพิ่มเป็น migration ถัดไปเมื่อถึงคิวพัฒนา

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
| PUT | `/onboarding/step1` | บันทึกข้อมูลพื้นฐาน |
| PUT | `/onboarding/step2` | บันทึกประวัติบาดเจ็บ |
| PUT | `/onboarding/step3` | บันทึกเป้าหมาย |
| PUT | `/onboarding/step4` | บันทึกประวัติการวิ่ง → ตั้ง `onboarding_completed = true` |

ตัวอย่าง body ของแต่ละ step อยู่ใน `src/utils/validators.js` (Joi schema เป็น source of truth ของ field ที่รับ)

### Users

| Method | Path | คำอธิบาย |
|---|---|---|
| GET | `/users/me/full` | รวมข้อมูลผู้ใช้ + basic info + injury + goals + running history ในครั้งเดียว (เหมาะกับหน้า Home/Profile) |

---

## หมายเหตุด้านความปลอดภัย

- OTP และ refresh token ไม่เคยถูกเก็บเป็น plaintext — เก็บเป็น bcrypt hash (OTP) และ sha256 hash (refresh token)
- `otp_ref` ไม่ใช่ secret (ไม่ hash) — ใช้เพื่อระบุ "คำขอรอบไหน" เท่านั้น ความปลอดภัยของ OTP ยังขึ้นอยู่กับตัวรหัส OTP 6 หลักที่ hash ไว้เป็นหลัก
- Rate limit บน endpoint ขอ/ยืนยัน OTP กันการยิงสแปม
- Access token อายุสั้น (`15m` default) + refresh token หมุนทุกครั้งที่ใช้ (rotation) เพื่อลดความเสี่ยงจาก token รั่วไหล
- Onboarding routes ทุกตัวถูกป้องกันด้วย JWT middleware (`requireAuth`)