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
| `otp_codes` | OTP ที่ hash แล้ว, มี expiry / max attempts / resend cooldown |
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
| POST | `/auth/otp/request` | `{ email, purpose: "register"\|"login" }` | ส่ง OTP 6 หลักไปที่อีเมล |
| POST | `/auth/otp/verify` | `{ email, otp, displayName? }` | ยืนยัน OTP → คืน `accessToken` + `refreshToken` + `user` |
| POST | `/auth/google` | `{ idToken }` | Login/Register ด้วย Google ID Token (ฝั่ง frontend ทำ Google Sign-In แล้วส่ง idToken มา) |
| POST | `/auth/refresh` | `{ refreshToken }` | ขอ accessToken ใหม่ (หมุน refreshToken ด้วย) |
| POST | `/auth/logout` | `{ refreshToken }` | เพิกถอน refreshToken |
| GET | `/auth/me` | – (ต้องมี `Authorization: Bearer <accessToken>`) | ข้อมูลผู้ใช้ปัจจุบัน |

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
- Rate limit บน endpoint ขอ/ยืนยัน OTP กันการยิงสแปม
- Access token อายุสั้น (`15m` default) + refresh token หมุนทุกครั้งที่ใช้ (rotation) เพื่อลดความเสี่ยงจาก token รั่วไหล
- Onboarding routes ทุกตัวถูกป้องกันด้วย JWT middleware (`requireAuth`)
