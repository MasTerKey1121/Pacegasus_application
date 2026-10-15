# Profile management — UAT

รวมรายงาน ผลทดสอบ และภาพหลักฐานจากสองรอบไว้ในโฟลเดอร์เดียว

| รอบเดิม | รายงาน | ผลทดสอบ |
| --- | --- | --- |
| 2026-10-15_195748 — ข้อมูลโปรไฟล์และชื่อ | [รายงาน](UAT-REPORT-profile.md) | [JSON](results-profile.json) |
| 2026-10-15_200854 — ภาพโปรไฟล์ | [รายงาน](UAT-REPORT-profile-image.md) | [JSON](results-profile-image.json) |

- [สรุปผลเปลี่ยนภาพโปรไฟล์](SUMMARY.md)
- ภาพหลักฐานทั้งหมดอยู่ใน `screenshots/` โดยแยกชื่อภาพ identity ของแต่ละรอบเพื่อไม่ให้ทับกัน

ย้ายเฉพาะไฟล์ที่มีอยู่เดิม ไม่ได้ทดสอบใหม่หรือเปลี่ยนผลทดสอบ รายงานเดิมอ้างถึงภาพบางภาพที่ไม่มีอยู่ในโฟลเดอร์ต้นทาง ได้แก่ `profile-uid.png`, `profile-cancel.png`, `profile-name-restored-from-server.png` และ `photo-uploaded.png`
