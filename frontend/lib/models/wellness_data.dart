class WellnessEntry {
  int? sleepQuality;   // 1-5
  int? muscleSoreness; // 1-5 (เดิมชื่อ muscleFatigue)
  int? energyLevel;    // 1-5 (เดิมชื่อ musclePower)
  int? stressLevel;    // 1-5
  int? motivation;     // 1-5
  double? sleepHours;  // 1-12 (ไม่ส่ง API)

  WellnessEntry({
    this.sleepQuality,
    this.muscleSoreness,
    this.energyLevel,
    this.stressLevel,
    this.motivation,
    this.sleepHours,
  });

  bool get isComplete =>
      sleepQuality != null &&
      muscleSoreness != null &&
      energyLevel != null &&
      stressLevel != null &&
      motivation != null;

  Map<String, dynamic> toApiJson() => {
        'sleepQuality': sleepQuality!,
        'energyLevel': energyLevel!,
        'muscleSoreness': muscleSoreness!,
        'stressLevel': stressLevel!,
        'motivation': motivation!,
      };

    factory WellnessEntry.fromRecord(Map<String, dynamic> record) => WellnessEntry(
      sleepQuality: (record['sleep_quality'] as num?)?.toInt(),
      muscleSoreness: (record['muscle_soreness'] as num?)?.toInt(),
      energyLevel: (record['energy_level'] as num?)?.toInt(),
      stressLevel: (record['stress_level'] as num?)?.toInt(),
      motivation: (record['motivation'] as num?)?.toInt(),
      // sleepHours ไม่มีใน API (เก็บแค่ในแอป) ใช้ default ไปก่อน
    );
}
