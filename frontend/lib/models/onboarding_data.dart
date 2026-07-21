/// Everything collected across the 3 onboarding steps + the register step.
class OnboardingData {
  String day = '';
  String month = '';
  String year = '';
  String gender = 'หญิง'; // 'ชาย' | 'หญิง'
  String weightKg = '';
  String heightCm = '';

  final Set<String> conditions = {}; // โรคประจำตัว
  final Set<String> injuries = {}; // อาการบาดเจ็บ

  String goal = 'วิ่ง 5K';

  String pastExperience = 'เคย 1-2 ครั้ง'; // เคยซ้อม/แข่งมาก่อนไหม
  String trainingDuration = '6-12 เดือน'; // เริ่มซ้อมมานานไหม
  String longestDistance = '5-10 km'; // วิ่งไกลสุดในสัปดาห์

  OnboardingData copy() {
    final o = OnboardingData()
      ..day = day
      ..month = month
      ..year = year
      ..gender = gender
      ..weightKg = weightKg
      ..heightCm = heightCm
      ..goal = goal
      ..pastExperience = pastExperience
      ..trainingDuration = trainingDuration
      ..longestDistance = longestDistance;
    o.conditions.addAll(conditions);
    o.injuries.addAll(injuries);
    return o;
  }
}
