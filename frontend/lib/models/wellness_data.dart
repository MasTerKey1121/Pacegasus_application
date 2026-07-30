class WellnessEntry {
  int sleepQuality;   // 1-5
  int muscleSoreness; // 1-5 (เดิมชื่อ muscleFatigue)
  int energyLevel;    // 1-5 (เดิมชื่อ musclePower)
  int stressLevel;    // 1-5
  int motivation;     // 1-5 (ฟิลด์ใหม่ ต้องมี ไม่งั้น API ปฏิเสธ)
  double sleepHours;  // 0-12 (ไม่ส่ง API แค่เก็บไว้ดูในแอป)

  WellnessEntry({
    this.sleepQuality = 3,
    this.muscleSoreness = 3,
    this.energyLevel = 3,
    this.stressLevel = 3,
    this.motivation = 3,
    this.sleepHours = 7,
  });

  Map<String, dynamic> toApiJson() => {
        'sleepQuality': sleepQuality,
        'energyLevel': energyLevel,
        'muscleSoreness': muscleSoreness,
        'stressLevel': stressLevel,
        'motivation': motivation,
      };

    factory WellnessEntry.fromRecord(Map<String, dynamic> record) => WellnessEntry(
      sleepQuality: (record['sleep_quality'] as num?)?.toInt() ?? 3,
      muscleSoreness: (record['muscle_soreness'] as num?)?.toInt() ?? 3,
      energyLevel: (record['energy_level'] as num?)?.toInt() ?? 3,
      stressLevel: (record['stress_level'] as num?)?.toInt() ?? 3,
      motivation: (record['motivation'] as num?)?.toInt() ?? 3,
      // sleepHours ไม่มีใน API (เก็บแค่ในแอป) ใช้ default ไปก่อน
    );
}