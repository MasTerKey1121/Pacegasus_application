import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/mission.dart';

class MissionNotifier extends ChangeNotifier {
  final List<Mission> missions = [
    Mission(id: 'run', icon: '🏃', title: 'Easy run 5 km', subtitle: 'Zone 2 · ประมาณ 35 นาที', coinReward: 20),
    Mission(id: 'stretch', icon: '🧘', title: 'Stretching 10 นาที', subtitle: 'ยืดเส้นหลังซ้อมวิ่ง', coinReward: 5),
    Mission(id: 'wellness', icon: '💬', title: 'Daily Wellness Check-in', subtitle: 'บันทึกสุขภาพวันนี้', coinReward: 10),
  ];

  int get doneCount => missions.where((m) => m.done).length;

  void setDone(String id, bool done) {
    final m = missions.firstWhere((m) => m.id == id);
    m.done = done;
    notifyListeners();
  }

  bool isDone(String id) => missions.firstWhere((m) => m.id == id).done;
}

final missionProvider = ChangeNotifierProvider<MissionNotifier>((ref) => MissionNotifier());
