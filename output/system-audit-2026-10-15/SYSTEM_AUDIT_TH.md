# รายงานตรวจระบบ Pacegasus — 15 ตุลาคม 2026

ตรวจจากโค้ดใน workspace ปัจจุบัน ซึ่งไม่มีการแก้ไขค้างอยู่ก่อนเริ่มตรวจ ครอบคลุม Flutter frontend, Express backend, API contracts, migrations, authentication, onboarding, wellness, training, running/GPS, feedback, rewards, profile, friends, clubs, avatar, shop และ leaderboard

**ผลประเมิน:** ยังมีปัญหาที่ขัดขวาง Flow ใช้งานจริง โดยเฉพาะแก้ไขตารางซ้อม, วิ่งจบ → ปิดภารกิจหลัก, การให้รางวัล, การกู้คืนเมื่อเน็ตหลุด และรูปคลับ ควรแก้กลุ่ม P1 ก่อนทดสอบรับรองกับผู้ใช้

การตรวจนี้ไม่ได้ยืนยันว่าหน้าจอทุกหน้าทำงานบนมือถือจริงแล้ว: ใช้การอ่านโค้ด ชุดทดสอบเดิม การจำลองข้อผิดพลาดแบบเจาะจง การเรียก router จริงในเครื่อง และ integration test ฐานข้อมูลที่ใช้ temporary tables พร้อม rollback ไม่ได้ใช้บัญชีจริงส่ง OTP ซื้อสินค้า หรือเปลี่ยนข้อมูลผู้ใช้จริง ไม่ได้ทดสอบ GPS ระหว่างเดิน/วิ่งจริง, background execution หรือ Google account picker บนอุปกรณ์

## ผลทดสอบที่รันจริง

| การตรวจ | ผล | ความหมาย |
| --- | --- | --- |
| Backend `node --test tests/*.test.js` | ผ่าน 75, ไม่ผ่าน 5, ข้าม 1 จาก 81 | หลังให้ test server เชื่อมต่อ loopback ได้แล้ว เหลือปัญหาชุดทดสอบโปรแกรม 5 รายการ |
| Leaderboard database integration แยกรัน | ผ่าน 1/1 | temporary tables + rollback: top 50, อันดับเสมอ, ขอบเขตสัปดาห์, contribution คลับ |
| Frontend `flutter test --no-pub --reporter expanded` | ผ่าน 94, ไม่ผ่าน 2 | สองรายการเกี่ยวกับ UID บนหน้า Profile ติด WebView platform setup ในชุดทดสอบ |
| `flutter analyze --no-pub` | พบ 58 ประเด็น | ไม่มี compile error ที่รายงาน; มี warnings และข้อมูลเรื่อง deprecated API/lint จึง exit 1 |
| `flutter build web --no-pub` | build JavaScript web สำเร็จ | มีคำเตือน Wasm incompatibility ของ secure storage และ font family; ไม่ใช่หลักฐานว่า run screen ทำงานใน browser ได้ |
| Backend audit probes เพิ่มเติม | ยืนยันข้อสังเกต 7/7 | mock ฐานข้อมูลทั้งหมด; ใช้ router จริงตรวจ API ที่ขาด |
| Frontend audit probes เพิ่มเติม | ยืนยันข้อสังเกต 4/4 | offline login, offline finish, สลับบัญชี, response ของสถานที่ย้อนลำดับ |

หมายเหตุ: backend ครั้งแรกมี EACCES ในการเชื่อมต่อ test server ภายในเครื่อง เมื่อรันด้วยสิทธิ์เข้าถึง loopback แล้วส่วนนี้ผ่าน จึงไม่ถือ EACCES เป็นบั๊กผลิตภัณฑ์

### สาเหตุชุดทดสอบเดิมไม่ผ่าน

- `backend/tests/programWorkflow.test.js`: 4 รายการยังไม่เตรียมข้อมูลสำหรับ wellness gate ที่เพิ่มใน `startProgram`; อีก 1 รายการยังคาดลำดับ query เก่า ก่อนเพิ่ม backfill baselines ผลนี้หมายถึง mock ไม่ตรงกับโค้ดปัจจุบัน ยังใช้รับรอง happy path/rollback ของการเริ่มโปรแกรมไม่ได้ ไม่ควรสรุปว่าผู้ใช้จริงเริ่มโปรแกรมไม่ได้จาก failures เหล่านี้อย่างเดียว
- บาง assertion ที่คาด 400 ผ่านได้เพราะติด wellness gate ก่อนเข้าถึงเงื่อนไขที่ชื่อเทสบอกว่าจะทดสอบ จึงควรตรวจว่าถึง branch ที่ต้องการจริง
- `frontend/test/widget_test.dart`: `profile displays and copies public UID, not database id` และ `missing UID has no fabricated value or copy action` ยังใช้ ModelViewer/WebView จริงโดยไม่มี platform implementation สำหรับ test ต้อง inject renderer หรือ fake WebView ให้ครบ timeout เป็นผลต่อเนื่องจากปัญหานี้ ไม่ใช่หลักฐานว่า UID ของจริงหาย

## รายการปัญหา

P1 = ควรแก้ก่อนให้ผู้ใช้ทดสอบ Flow หลัก / P2 = มีผลต่อความถูกต้องหรือประสบการณ์ใช้งาน ควรแก้ก่อนรับรอง release

### 01 — P1: แก้ไขตารางซ้อมที่บันทึกแล้วไม่ได้

- หลักฐาน: `frontend/lib/services/program_api.dart:35` เรียก `PUT /api/programs/quests/week` แต่ `backend/src/routes/programRoutes.js` ไม่มี route นี้
- ยืนยัน: เรียก router ของแอปจริงพร้อม access token จำลอง ได้ HTTP 404
- ทำซ้ำ: บันทึกสัปดาห์ → เปิดแก้ไข → เปลี่ยนวัน → บันทึกการแก้ไข
- ผล: UI เปิดให้แก้ แต่ไม่สามารถบันทึกได้
- แนวแก้: เพิ่มการ replace แบบ transaction พร้อมกติกา ownership/current-future week/pending-only หรือปรับ frontend ให้ตรงกับ contract ที่มีจริง

### 02 — P1: วิ่งจบแล้วภารกิจหลักยังไม่สำเร็จ

- หลักฐาน: `frontend/lib/screens/run/run_summary_screen.dart:325` ส่งเพียง feedback และเปลี่ยน `missionProvider` ในเครื่อง; `frontend/lib/services/program_api.dart` ไม่มีคำสั่ง complete main quest ส่วน `backend/src/services/runningService.js` อัปเดตเฉพาะ running session
- `backend/src/services/programService.js:604` มี complete endpoint แยกอยู่ แต่ไม่มี caller ใน frontend
- ทำซ้ำ: ลงตารางวันนี้ → วิ่ง → จบ → ส่งความรู้สึก → กลับ Home / เปิดแอปใหม่
- ผลที่อนุมานจากเส้นทางโค้ด: main quest ในฐานข้อมูลยัง pending, progress โปรแกรมไม่เพิ่ม และเริ่มภารกิจเดิมซ้ำได้; ไม่มีการผูกผลจริงเข้ากับ `running_session_id`, `actual_value`, `rpe_reported`
- แนวแก้: ผูก session กับ main quest ตั้งแต่เริ่ม แล้ว complete พร้อมผลจริงแบบ transaction และป้องกันซ้ำ

### 03 — P1: คำแนะนำปรับโหลดฝึกไม่ได้ถูกนำไปใช้ในแอป

- หลักฐาน: backend ส่ง `quest.adjustment` จาก `programService.js:29` และมี `force_rest`, `reduce_load`, `downgrade_to_easy` ใน `adaptiveEngineService.js` แต่ frontend ไม่มีการอ่าน adjustment
- Home อ่าน `planned_value` เดิมที่ `home_screen.dart:645`; หน้าเลือกวิ่งใช้ `session_type` เดิมที่ `run_select_screen.dart:100`; เป้าระยะหน้า Run ตายตัว 5 กม. ที่ `run_provider.dart:23`
- ทำซ้ำ: เตรียมข้อมูลให้ adjustment เป็น force_rest หรือลด 40% แล้วเปิด Home/เริ่มวิ่ง
- ผล: คำแนะนำพัก/ลดโหลดไม่ปรากฏและไม่เปลี่ยน Flow; เป้าระยะหน้า Run ไม่ตรงแผนที่ไม่ใช่ 5 กม.
- แนวแก้: กำหนดความหมายของแต่ละ action ใน UI และกติกาฝั่ง server ให้สอดคล้อง พร้อมแสดงเหตุผลและเป้าปรับแล้ว

### 04 — P1: เน็ตหลุดตอนกดจบวิ่ง ทำให้หยุดวิ่งและกดบันทึกซ้ำไม่ได้

- หลักฐาน: `run_provider.dart:88` ตั้ง `isRunning=false` และยกเลิก timer ก่อนเรียก API; catch คืน null โดยไม่กู้สถานะ ส่วน `run_session_screen.dart:382` ไม่ให้ finish ถ้าไม่ running และปุ่มจบถูก disable เช่นกัน
- ยืนยัน: จำลอง complete API ล้มเหลว ได้ผล null, `isRunning=false`, `isStopping=false`
- ทำซ้ำ: วิ่ง → ปิดอินเทอร์เน็ต → จบวิ่งและยืนยัน
- ผล: ไม่ไปหน้าสรุป ไม่มีข้อความผิดพลาดชัดเจน และไม่มีปุ่ม retry ที่ใช้ได้ในหน้าเดิม
- แนวแก้: เก็บ pending completion และแสดง retry; จัดการกรณี server commit แล้วแต่ response หายด้วย idempotency

### 05 — P1: เปิดแอปขณะเน็ตหลุดทำให้ login ที่บันทึกไว้ถูกลบทิ้ง

- หลักฐาน: `frontend/lib/providers/auth_provider.dart:122` catch ทุกข้อผิดพลาดจาก refresh แล้วลบ refresh token
- ยืนยัน: เริ่มด้วย token ที่เก็บไว้ จำลองเพียง connection failure หลัง init token หายและสถานะเป็น unauthenticated
- ผล: ผู้ใช้ต้อง OTP/Google login ใหม่แม้ token อาจยังใช้ได้ ความผิดพลาดชั่วคราวถูกปฏิบัติเป็น session หมดอายุ
- แนวแก้: แยก invalid/revoked token ออกจาก timeout/offline/5xx; เก็บ token และให้ลองเชื่อมต่อใหม่ในกรณีชั่วคราว

### 06 — P1: หน้ารางวัลไม่ตรงกับยอดจริงที่ server ให้

- หลักฐาน: `run_summary_screen.dart:346` แสดง 20 coin / 50 EXP ตายตัว; `reward_screen.dart:24` เพิ่มให้ state ในเครื่อง ขณะที่ `backend/src/services/rpeService.js:37` ให้ 5 coin / 5 EXP ต่อ feedback และ running completion ไม่ให้รางวัลนี้
- ทำซ้ำ: จด coin/EXP → วิ่งจบ → ส่ง feedback → เทียบหน้ารางวัลกับ `/api/users/me/progress`
- ผล: ผู้ใช้เห็นว่ารับรางวัลแล้วแต่ยอดใช้จริงไม่ตรง การปิด main quest ยังขาดตามข้อ 02
- แนวแก้: แสดงและอัปเดตจาก reward/progress response ของ server เท่านั้น และแยกแหล่งรางวัลให้ชัด

### 07 — P1: ส่ง feedback ซ้ำได้ทั้งรางวัลซ้ำและ training load ซ้ำ

- หลักฐาน: `rpeService.js:27` insert แถวใหม่ทุกครั้ง; reward ใช้ RPE row id ใหม่เป็น source id; `008_create_rpe_logs.sql` ไม่มี unique constraint สำหรับหนึ่ง feedback ต่อ session
- ยืนยัน: ส่ง payload เดิมสองครั้งใน service mock เกิดสอง RPE inserts และสอง reward attempts
- ผล: response หายแล้ว retry หรือเรียก API ซ้ำ ทำให้ coin/EXP และ ACWR ผิดได้
- แนวแก้: ตัดสิน contract หนึ่ง feedback ต่อ run หรือ feedback revision แล้วบังคับ unique/idempotency และปรับโหลดแบบไม่ซ้ำ

### 08 — P1: อัปโหลดรูปคลับได้ แต่ URL ที่คืนเปิดรูปไม่ได้

- หลักฐาน: `backend/src/routes/clubRoutes.js:11` คืน `/api/club-images/<file>` แต่ app เปิด static ที่ `/uploads` เท่านั้น ไม่มี route ของ prefix ที่คืน
- ยืนยัน: prefix ดังกล่าวได้ 401 เมื่อไม่ส่ง token และ 404 เมื่อส่ง token; ไม่มี handler เสิร์ฟรูปที่ path นี้ แม้ไฟล์จริงถูกบันทึกใน `uploads/club-images`
- ทำซ้ำ: สร้าง/แก้รูปคลับ → บันทึก → ออกจากหน้าแล้วกลับเข้ามา
- ผล: preview ในเครื่องอาจทำให้ดูเหมือนสำเร็จ แต่ภาพที่โหลดผ่าน URL ไม่แสดง
- แนวแก้: คืน public URL ที่เสิร์ฟได้จริง ใช้ public origin ของ deployment และจัดเก็บรูปให้คงอยู่เมื่อ restart/deploy

### 09 — P1: API วิ่งไม่บังคับสถานะและข้อมูลตัวเลข

- หลักฐาน: `runningRoutes.js`/controller ไม่ validate start/complete/abandon; service update ด้วย id+owner อย่างเดียว ไม่มีเงื่อนไขสถานะก่อนหน้า และ schema เดิมไม่มี nonnegative check ของ distance/duration
- ยืนยัน: completed → abandoned → completed ทำได้ใน service probe และค่าระยะติดลบถูกส่งถึง SQL
- ผล: ประวัติที่จบแล้วเปลี่ยนย้อนหลัง/กลับสถานะได้ และค่าผิดอาจเข้าการจัดอันดับ/สถิติ หรือทำให้เกิด DB error แทน 400
- แนวแก้: request schema, allowed state transitions, numeric bounds และ constraint ฐานข้อมูล; ตรวจ race ระหว่าง complete กับ abandon

### 10 — P1: ข้อมูลบางส่วนของบัญชีก่อนหน้าค้างเมื่อสลับบัญชี

- หลักฐาน: `onboarding_provider.dart:44`, `mission_provider.dart:39`, `user_provider.dart:40` ไม่ฟังการเปลี่ยน account แบบที่ wellness/run/program ทำ
- ยืนยัน: เปลี่ยน auth user A → B ใน provider container แล้ว weight answer กับ daily run done ของ A ยังอยู่
- ผล: แบบสอบถามสุขภาพ/เป้าหมายและสถานะภารกิจอาจแสดงหรือถูกส่งเป็นของอีกบัญชี
- แนวแก้: กำหนด account scope/reset ให้ครบ และป้องกัน response เก่าของบัญชี A เขียน state หลังเปลี่ยนเป็น B

### 11 — P2: เลือกสถานที่เร็ว ๆ ได้ภารกิจของสถานที่เก่า

- หลักฐาน: `run_setup_provider.dart:60` ไม่มี request generation/cancellation; response ที่กลับทีหลังเขียน `sideQuests` ได้เสมอ
- ยืนยัน: เลือก road → park ให้ park ตอบก่อน road ผลสุดท้าย environment=park แต่รายการเป็น road
- แนวแก้: รับผลเฉพาะ request ล่าสุดที่ยังตรง account/environment/training type

### 12 — P1: กู้คืนการวิ่งไม่กู้เส้นทางเดิม และข้อมูลหลังวิ่งกู้คืนไม่ได้

- หลักฐาน: `main_shell.dart:77` restore เฉพาะเวลา/ระยะ/paused และ setup จาก draft จากนั้นเปิด RunSessionScreen ซึ่ง `_routePoints` เริ่มว่างที่ `run_session_screen.dart:75`; ไม่มีการโหลด route เดิมกลับในกรณีเลือกวิ่งต่อ
- ทำซ้ำ: วิ่งมี route → ปิดแอป → เปิดแล้วเลือกวิ่งต่อ → จบวิ่ง เส้นทางที่ส่งจะมาจากหน้าที่เปิดใหม่ ไม่รวมส่วนเดิม
- อีกจุด: `run_session_screen.dart:452` ลบ draft ทันทีที่ complete session สำเร็จก่อนส่ง RPE หากปิดแอปในหน้าสรุป ไม่มี pending feedback ให้กลับมาทำต่อ และหน้า Stats เป็นการอ่านข้อมูล
- แนวแก้: กู้ route และสถานะ session จาก server/draft; เก็บ completed-awaiting-feedback จนจบ Flow และให้กลับไปกรอก feedback ได้

### 13 — P2: เปิดแอปค้างข้ามวันแล้ว Wellness/ภารกิจไม่รีเซ็ต

- หลักฐาน: `completedToday` เป็น boolean ไม่มีวันที่กำกับหรือ midnight/resume handler; MainShell โหลดเมื่อสร้างหน้า; missionProvider ไม่มี daily reset
- ทำซ้ำ: check-in ก่อนเที่ยงคืน → อยู่ Home ข้ามวัน → กดเริ่มวิ่งหรือแก้ wellness
- ผลที่คาดจากโค้ด: UI ยังถือว่าทำวันนี้แล้ว; การ submit อาจเลือก PUT ทั้งที่ server ไม่มี check-in ของวันใหม่; quest/current week อาจยังเป็นข้อมูลก่อนข้ามวัน
- แนวแก้: ผูก state กับวันที่ไทย โหลดใหม่เมื่อ resume/วันเปลี่ยน และรีเซ็ตสถานะรายวัน

### 14 — P1: การนับวัน backend ใช้ UTC/host/DB timezone ปนกัน

- หลักฐาน: `programService.js:293` วันเริ่มมาจาก UTC `toISOString`; annotate today ใช้ host local time ที่บรรทัด 23; wellness และ current week ใช้ DB `CURRENT_DATE`; Flutter ใช้ Bangkok date โดยชัดเจน
- กรณีแน่นอนของ UTC startDate: สมัครตอน 00:30 ไทย = 17:30 UTC ของวันก่อนหน้า จึงบันทึก startDate เป็นวันก่อนหน้า
- ผลด้าน wellness/current week ขึ้นกับ timezone ของฐานข้อมูล/host ซึ่งยังไม่ได้ยืนยันค่าของ production ในรอบนี้
- แนวแก้: ใช้ business date Asia/Bangkok เดียวกันในคำสั่งสร้างโปรแกรม/ตรวจวัน/คำนวณสัปดาห์ พร้อม boundary tests ก่อน-หลังเที่ยงคืน

### 15 — P2: Coin บน Home ไม่รีเฟรชหลังได้รางวัล

- หลักฐาน: `wallet_provider.dart:6` cache ตาม user id; หน้า wellness เพิ่ม `userProvider` แต่ไม่ invalidate wallet; หน้า run/side quest เช่นกัน มี invalidate wallet หลังซื้อของใน Shop เท่านั้น
- ผล: ได้รางวัลจริงแล้วกลับ Home ยอดอาจค้างจนมีการ refresh จากเหตุอื่น แม้หน้ารางวัลบอกสำเร็จ
- แนวแก้: อัปเดต wallet จาก server progress response หรือ invalidate หลังทุก transaction ที่เปลี่ยนยอด

### 16 — P2: ภารกิจประจำวันยังเป็นข้อมูลจำลองและกดรับสำเร็จได้ทันที

- หลักฐาน: `mission_provider.dart` hardcode Easy run 5 km / Stretching / Wellness; `daily_missions_screen.dart:54` กดรายการที่ไม่ใช่ wellness แล้ว setDone และเพิ่ม coin เฉพาะเครื่อง ไม่มี API
- ผล: แตะรายการวิ่งก็แสดงสำเร็จโดยไม่วิ่ง, ไม่ตรงโปรแกรมจริง, coin ส่วนนี้ใช้ซื้อสินค้าไม่ได้ และสถานะไม่คงอยู่หลังเปิดแอปใหม่
- แนวแก้: ใช้ภารกิจจริงและ completion/reward จาก server; แยกกิจกรรม self-report หากต้องการให้ผู้ใช้ยืนยันเอง

### 17 — P2: เมนู Settings สี่รายการกดแล้วไม่มีอะไรเกิดขึ้น

- หลักฐาน: `settings_screen.dart:102`, `125`, `130`, `135` เป็น callback ว่าง
- รายการ: แก้ไขโปรไฟล์, ประวัติการวิ่ง, เป้าหมายการวิ่ง, เชื่อมต่อ API ภายนอก
- หน้า Profile และ Stats บางส่วนมีการทำงานจริงอยู่แล้ว แต่ทางเข้าจาก Settings ยังไม่เชื่อม
- แนวแก้: ต่อไปยังหน้าที่มีอยู่ หรือ disable พร้อมคำอธิบายที่เห็นชัด

### 18 — P1: รับรางวัลเควสโดยยังไม่ทำกิจกรรมได้

- หลักฐาน: `sideQuestService.js:308` finish ตั้ง found_count เท่ากับ target โดยไม่ตรวจ pending/in_progress/session จริง; `programService.js:613` complete main quest ตรวจเจ้าของ แต่ไม่ตรวจวันที่, active program, session หรือผลวิ่งจริง
- ยืนยันเพิ่มเติม: pending side quest ที่ไม่มี running session ถูก finish และเรียก award ได้ใน mock probe
- Flow ทำให้สร้าง side quest instances ใหม่ได้ทุกครั้งที่ GET รายการ แล้วเรียก finish ได้ จึงมีช่องให้สร้างรางวัลใหม่ต่อเนื่อง แม้ award จะกันซ้ำของ instance เดิม
- แนวแก้: ระบุหลักฐาน/กติกาของกิจกรรมที่ถือว่าสำเร็จ ตรวจ session owner+status และวัน/โปรแกรม; ไม่ใช้แค่ id ของแถวใหม่เป็นการป้องกันรางวัลซ้ำ

### 19 — P1: Refresh token rotation ไม่เป็น atomic และ client ไม่รวม refresh พร้อมกัน

- หลักฐาน: `tokenService.js:37` SELECT → UPDATE revoke → INSERT token ใหม่อยู่นอก transaction/conditional consume; `auth_provider.dart:95` ไม่มี in-flight refresh future ร่วมกัน
- ยืนยัน: request พร้อมกันสองรายการอ่าน token เดียวที่ยังไม่ revoked แล้วออก successor ได้ทั้งสองรายการใน controlled mock
- ผล: token ใช้ซ้ำได้ระหว่าง race; เมื่อหลาย API ได้ 401 พร้อมกัน client อาจแย่ง refresh และบาง request ล้าง session ที่เพิ่ง refresh สำเร็จ
- แนวแก้: consume token แบบ atomic ใน transaction พร้อม row lock/เงื่อนไข revoked=false และ single-flight refresh ฝั่งแอป

### 20 — P1: ลบบัญชียังไม่สอดคล้องกับสิทธิ์และสถานะคลับ

- หลักฐาน: `backend/src/controllers/userController.js` เปลี่ยน user เป็น deleted + เปลี่ยน email + revoke refresh tokens แต่ไม่จัดการ club leadership/membership; `middleware/auth.js` ตรวจเพียง JWT signature/expiry ไม่มี active-user check
- ผลจากโค้ด: access token เดิมยังเรียกหลาย service ที่ไม่ตรวจ active user ได้จนหมดอายุ; หากเป็นหัวหน้าคลับ ไม่มีการโอน/ยุบตามขั้นตอนลบ ทำให้คลับอาจมีหัวหน้าที่หายไปแล้ว
- ข้อความใน Settings ระบุว่าลบข้อมูลทั้งหมดถาวร แต่ backend เก็บข้อมูลเดิมแบบ soft delete ควรให้ข้อความสอดคล้องนโยบายจริง
- แนวแก้: บังคับการถอนสิทธิ์ตามสถานะบัญชี และกำหนดการจัดการคลับก่อน/ระหว่างลบบัญชีใน transaction

### 21 — P2: เริ่ม session แล้วเริ่ม side quest ล้มเหลว ทิ้ง session ค้าง

- หลักฐาน: `run_setup_provider.dart:110` เรียก start session ก่อน start side quests; catch คืน false โดยไม่ abandon/reuse session เดิม หากกดเริ่มใหม่จะสร้าง session ใหม่อีก
- server ยังไม่มีข้อจำกัดหนึ่ง in-progress session ต่อผู้ใช้
- ทำซ้ำ: ให้ POST session สำเร็จ แต่คำขอถัดไป timeout/500 → กดเริ่มใหม่
- ผล: มี session ที่ยังไม่เริ่มใช้งานค้างในฐานข้อมูล และ idempotency ของ Flow ไม่ครบ
- แนวแก้: เริ่ม session+quests แบบ transaction เดียว หรือมี pending setup recovery และ compensation/reuse ที่แน่นอน

## ข้อจำกัดตามแพลตฟอร์ม/ส่วนที่ยังไม่พร้อม

- Windows: avatar renderer แสดงข้อความว่า 3D ใช้ได้บนมือถือและเว็บ; run screen แสดง panel แทนแผนที่ เป็นข้อจำกัดที่โค้ดระบุไว้ ไม่ใช่โหลดผิดโดยบังเอิญ
- Web: build สำเร็จ แต่ run screen เรียก `Platform.isWindows` โดยไม่มี kIsWeb guard (`run_session_screen.dart:208`, `530`) ซึ่งใช้ไม่ได้บน browser ต้องมี browser runtime smoke test และเปลี่ยน platform detection ก่อนรับรองเว็บ
- Google login ถูกปฏิเสธบนเว็บ/Windows ตามโค้ดปัจจุบัน แม้มีปุ่มให้เห็น ควรแสดง availability ก่อนกดให้ตรงแพลตฟอร์ม
- เพิ่มเพื่อนด้วย QR และหมวดอันดับเพิ่มเติมระบุว่าเร็ว ๆ นี้; Shop มีบางหมวดแสดงว่ายังไม่พร้อม ต้องแยกจาก catalog ว่างหรือโหลด API ผิดพลาด
- ไม่ได้ยืนยัน Google OAuth configuration/SMTP/GISTDA API key ของ production; ต้องทดสอบบน environment ที่จะส่งให้ผู้ใช้โดยไม่เปิดเผย secret
- README frontend ยังระบุ mock-only/no backend/no GPS ซึ่งไม่ตรงระบบปัจจุบัน ควรแก้เอกสารและวิธีตั้งระบบ/คำสั่งทดสอบ

## แผนทดสอบที่ควรมี

แต่ละกรณีให้ตรวจทั้งสิ่งที่ผู้ใช้เห็น, HTTP result, ข้อมูลฐานข้อมูล, ยอดรางวัล และผลหลังปิดเปิดแอป ไม่ตรวจแค่ข้อความบนหน้าจอ

| กลุ่ม | กรณีที่ต้องทดสอบ | ผลที่ต้องได้ |
| --- | --- | --- |
| E2E หลัก | สมัคร → policy → onboarding 4 ขั้น → wellness → สมัครแผน → จัดตาราง → วิ่ง → RPE → รางวัล → เปิดแอปใหม่ | account, plan, session, main quest, RPE, coin/EXP ตรงกันและคงอยู่ |
| E2E เดิม | login ผู้ใช้เก่า มีแผน/ไม่มีแผน/แผนยกเลิก/แผนจบ | ไปหน้าถูกต้องและไม่สร้างโปรแกรมซ้ำ |
| Auth | OTP ถูก/ผิด/หมดอายุ/ครบ attempts/resend cooldown/OTP รอบเก่า | validate ตรง server ไม่ค้างและไม่ข้าม policy |
| Auth | Google ยกเลิก/invalid token/บัญชีใหม่/บัญชีเดิม/account disabled | ไม่สร้างบัญชีหรือ session ซ้ำ; destination ถูกต้อง |
| Auth | offline ตอนเปิดแอป, refresh 500, token revoked จริง | เก็บ session เมื่อผิดพลาดชั่วคราว; logout เมื่อถูกถอนสิทธิ์จริง |
| Auth | หลาย API 401 พร้อมกัน/refresh token สอง request พร้อมกัน | refresh หนึ่งครั้งต่อ client; consume token ครั้งเดียว |
| Auth | logout แล้ว back, สลับ A/B, response A กลับหลัง B login | ไม่มีข้อมูล A/route เก่ารั่วเข้าบัญชี B |
| Policy/onboarding | ปฏิเสธเงื่อนไข, ย้อนขั้น, ปิดแอปในแต่ละขั้น | resume ถูกขั้นและไม่ใช้คำตอบจากอีกบัญชี |
| Onboarding | birthdate bounds/leap day, height/weight bounds, ไม่มีอาการ/มีหลายอาการ, ไม่เคยวิ่ง | validation และ level คำนวณถูก ข้อมูล optional ไม่ขัดกัน |
| Wellness | ทุกคะแนน 1/5, กรอกไม่ครบ, create/update, สองอุปกรณ์ create พร้อมกัน | 1 record ต่อวัน, reward ครั้งเดียว, retry ไม่เกิดยอดซ้ำ |
| Wellness | 23:59 → 00:01 ไทย และ background/resume ข้ามวัน | reset วันใหม่และเลือก POST/PUT ถูกต้อง |
| Program | ทุก level/prerequisite, มี active อยู่แล้ว, เริ่มพร้อมกัน | ปฏิเสธถูกเงื่อนไข ไม่มี active program ซ้ำ |
| Program | สมัครช่วง 00:00–06:59 ไทย, UTC host, timezone ต่างกัน | start date/today/week เดียวกับไทย |
| Schedule | save batch, server trigger fail แถวกลาง, response หายหลัง commit | rollback ทั้งชุด หรือ retry คืนรายการเดิม ไม่เกิดชุดซ้ำ |
| Schedule | แก้สัปดาห์ปัจจุบัน/อนาคต/อดีต, completed quest, เปลี่ยนความยาวแผน | API มีจริง pending-only, ประวัติไม่หาย, grid ตรง server |
| Schedule | sequencing ข้ามสัปดาห์, weekly cap, phase boundary, race/rest locked | กติกา frontend/backend ตรงกัน |
| Adaptive | cold start <14 วัน, วัน 14, ACWR 1.29/1.30/1.49/1.50, wellness 2/3 | action, คำอธิบาย, เป้าฝึกและสิทธิ์เริ่มวิ่งตรงกัน |
| Run setup | เปลี่ยน road/park/trail รัว ๆ, response กลับสลับลำดับ | quests ตรง environment ล่าสุดเสมอ |
| Run setup | GPS denied/deniedForever/service off/no fix/map timeout | ออกจากหน้าหรือ retry ได้ ไม่ทิ้ง run ค้างโดยไม่ตั้งใจ |
| Run setup | start สำเร็จแต่ quest start ล้มเหลว, กดเริ่มซ้ำ | กู้ session เดิมหรือ rollback ไม่สร้าง orphan |
| Run | แต่ละประเภทและระยะ 2/5/10/21 กม. รวม session ที่หน่วยนาที | เป้าหมาย/หน่วย/ข้อมูลที่บันทึกตรงแผน |
| Run GPS | stationary, inaccurate GPS, jumps, pause+เดิน+resume | ระยะและเส้นทางไม่เพิ่มจากช่วงพัก/สัญญาณผิด |
| Run GPS จริง | Android/iOS เดินเส้นทางทราบระยะ, lock screen, switch app 10–20 นาที | เวลา/ระยะ/background tracking ยังถูกต้องตามเกณฑ์ที่กำหนด |
| Run recovery | kill app → resume, paused recovery, เลือกจบจาก draft | รวมเส้นทางเดิมกับใหม่ ไม่มีเส้นตรงเชื่อมจุดผิด |
| Run finish | cancel confirmation, double tap, offline, timeout หลัง commit | จบครั้งเดียว มี retry และข้อมูลไม่หาย |
| Run API | negative/NaN/huge metrics, invalid UUID, other's session, complete↔abandon race | 400/403/404/409 ที่เหมาะสม ไม่รับข้อมูลผิดหรือแก้ประวัติผิดสิทธิ์ |
| Feedback | ครบ/ไม่ครบ, pain note, run <1 นาที/>1 ชั่วโมง, ปิดแอปก่อน submit | validation ตรง, แสดง duration ไม่วนกลับศูนย์, กลับมากรอกต่อได้ |
| Feedback | retry payload เดิม/submit พร้อมกัน/feedback ของ run คนอื่น | หนึ่งผลต่อ session ตาม contract และไม่มี reward/load ซ้ำ |
| Rewards | main/side/wellness/RPE ซ้ำและพร้อมกัน | reward event ครั้งเดียวต่อกิจกรรมจริงและ balance ทุกหน้าตรง server |
| Rewards | pending/future/cancelled quests, ไม่มี session, เรียก finish ตรง | ไม่ได้รางวัลที่ยังไม่มีสิทธิ์ตามกติกา |
| Profile | เปลี่ยนชื่อ/รูป, cancel, oversized/invalid image, restart | ทุกหน้าที่อ้างผู้ใช้เดียวกันแสดงค่าล่าสุด |
| Account deletion | token เก่า, หัวหน้าคลับ/สมาชิก/ไม่มีคลับ, ยืนยันซ้ำ | ถอนสิทธิ์จริงและจัดการคลับไม่ค้าง |
| Friends | A ขอ B/B ขอ A พร้อมกัน, accept/decline/cancel/remove, UID ผิด/บัญชี deleted | คู่เดียว, สิทธิ์ถูก และรายการรีเฟรชทั้งสองด้าน |
| Club | create/join/invite/approve, ข้ามคลับ, 19→20 คนพร้อมกัน | ไม่เกิน 20 และหนึ่งคนอยู่ได้คลับเดียว |
| Club | ทุก role/permission, kick ยศเท่า/สูง, transfer, leader leave/disband | UI กับ server ให้สิทธิ์ตรงกัน |
| Club images | upload → GET URL ที่คืน → reload app → deploy restart | รูปโหลดได้จริง ไม่พึ่ง preview หรือ filesystem ชั่วคราว |
| Shop | ทุก filter/sort/page, ราคาเปลี่ยน/หมดช่วงขาย, coin ไม่พอ, ซื้อซ้ำ/พร้อมกัน | ราคา server เป็นหลัก หักครั้งเดียว และ ownership ตรง |
| Wardrobe | try-on/cancel/save/fail/restart, inventory owned-only | ของที่ใส่ตรงของที่เป็นเจ้าของและแสดงเหมือนกันทุกหน้า |
| Stats | ไม่มีข้อมูล/ย้อนหลัง/วันเดือนปี/เที่ยงคืน/invalid metrics/detail offline | รวมระยะ เวลา pace และ RPE ถูก ไม่ซ่อน error เป็นศูนย์ |
| Leaderboard | ขอบเขตสัปดาห์/อันดับเสมอ/top50/outside50/ไม่มีคลับ/ย้ายคลับ | rank และ contribution ถูกและอธิบายช่วงเวลาชัด |
| UI | Android/iOS/Windows/Web, 320px/390px/tablet, text 150–200%, keyboard, landscape | ไม่มี overflow/ปุ่มหลุดจอ และระบุข้อจำกัดแพลตฟอร์มก่อนกด |
| Navigation | ทุกปุ่ม/menu, back ทุกขั้น, กลับ Home จาก reward, retry API | ไม่มี dead button, stuck overlay หรือกลับไป submit ซ้ำ |
| Logging | OTP/token/password/imageBase64/location/health payload | ไม่บันทึกรหัสใช้ครั้งเดียวและข้อมูลเกินจำเป็น; token ยังคงถูก mask |

### ลำดับการทำงานที่แนะนำ

1. แก้ contract ที่ขาด (#01, #08), เชื่อม run/main quest (#02), และทำ rewards/idempotency (#06, #07, #18) ให้เป็น Flow เดียวที่ตรวจสอบได้
2. แก้ offline/recovery/auth/account scope (#04, #05, #10, #12, #19, #21) แล้วทดสอบ network failure ระหว่างแต่ละขั้น
3. ทำ adaptive plan/date/state rules ให้ตรงทั้งสองฝั่ง (#03, #09, #13, #14, #20)
4. ต่อเมนูจริง/ยกเลิก mock state/รีเฟรชยอด (#15–#17) และแก้ race ของ environment (#11)
5. ปรับชุดทดสอบเก่าให้เขียนตาม contract ปัจจุบัน เพิ่ม E2E หลัก และทดสอบบน Android/iOS จริงก่อนรับรอง release

## หลักฐานที่เพิ่มไว้

- `output/system-audit-2026-10-15/backend-probes.cjs`: รันจาก backend ด้วย `node ../output/system-audit-2026-10-15/backend-probes.cjs`
- `frontend/audit/system_audit_probes_test.dart`: รันจาก frontend ด้วย `flutter test --no-pub --reporter expanded audit/system_audit_probes_test.dart`
- Probes เป็นการยืนยันพฤติกรรมที่บกพร่องในปัจจุบัน จึงคาดผลที่ไม่พึงประสงค์ไว้โดยตั้งใจ **ไม่ใช่ acceptance tests และไม่ควรใช้ผลผ่านเป็นเกณฑ์ release** เมื่อแก้ปัญหาแล้วให้เปลี่ยนเป็น regression tests ที่ตรวจผลถูกต้องและย้ายเข้าชุดปกติ
- ไม่มีการแก้ source ระบบหลัก, schema หรือข้อมูลผู้ใช้จริงในงานตรวจนี้

พบเพิ่มเติมจาก probe: `usageLog.js` ไม่ mask field `otp` และบันทึกรหัสลง request body ตรง ๆ; access/refresh token ถูก mask ด้วยการจับคำว่า token อยู่แล้ว ควรเพิ่ม OTP ในรายการปกปิดและตรวจข้อมูลสุขภาพ/GPS/image payload ตามความจำเป็นในการเก็บ log
