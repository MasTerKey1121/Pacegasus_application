/// Everything collected across the 3 onboarding steps + the register step.
class OnboardingData {
  String day = '';
  String month = '';
  String year = '';
  String gender = 'หญิง'; // 'ชาย' | 'หญิง'
  String weightKg = '';
  String heightCm = '';

  final Set<String> conditions = {}; // โรคประจำตัว
  final Set<String> pastInjuries = {}; // อาการบาดเจ็บที่เคยเป็น
  final Set<String> currentInjuries = {}; // อาการบาดเจ็บในปัจจุบัน

  String? healthGoal; // เป้าหมายด้านสุขภาพ (เลือกได้ 1)
  String? distanceGoal; // เป้าหมายด้านระยะทาง (เลือกได้ 1)
  String targetFinishTime = ''; // เวลาที่ต้องการจบ เช่น "01:30" (ใช้เมื่อเลือก distanceGoal เท่านั้น)
  double? targetPaceSecPerKm; // pace ที่คำนวณได้ (วินาที/กม.) ไว้ validate ช่วง 2:30 - 12:00
  double? targetSpeedKmPerSec; // ความเร็วเป้าหมาย (กม./วินาที) — ค่าที่จะส่งให้ API

  bool? hasRunningExperience; // เคยซ้อม/แข่งวิ่งมาก่อนไหม
  bool? isCurrentlyTraining; // ปัจจุบันยังซ้อมอยู่ไหม (ถามต่อเมื่อ hasRunningExperience == true)
  String? trainingDuration; // ซ้อมต่อเนื่องมานานเท่าไหร่แล้ว (ถ้ายังซ้อมอยู่)
  String? notTrainingDuration; // ไม่ได้ซ้อมมานานเท่าไหร่แล้ว (ถ้าไม่ได้ซ้อมแล้ว)

  String longestDistance = '5-10 km';

  OnboardingData copy() {
    final o = OnboardingData()
      ..day = day
      ..month = month
      ..year = year
      ..gender = gender
      ..weightKg = weightKg
      ..heightCm = heightCm
      ..healthGoal = healthGoal
      ..distanceGoal = distanceGoal
      ..targetFinishTime = targetFinishTime
      ..targetPaceSecPerKm = targetPaceSecPerKm
      ..targetSpeedKmPerSec = targetSpeedKmPerSec
      ..hasRunningExperience = hasRunningExperience
      ..isCurrentlyTraining = isCurrentlyTraining
      ..trainingDuration = trainingDuration
      ..notTrainingDuration = notTrainingDuration
      ..longestDistance = longestDistance;
    o.conditions.addAll(conditions);
    o.pastInjuries.addAll(pastInjuries);
    o.currentInjuries.addAll(currentInjuries);
    return o;
  }
}