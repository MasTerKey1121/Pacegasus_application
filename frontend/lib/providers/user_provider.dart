import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UserData extends ChangeNotifier {
  String username = 'UserName';
  double totalKm = 0;
  int totalSessions = 0;
  int streak = 0;
  String goalLabel = 'วิ่ง 10K · Sub 1:40';

  void setDisplayName(String name) {
    username = name;
    notifyListeners();
  }

  void addRunStats({required double km, required int sessions}) {
    totalKm += km;
    totalSessions += sessions;
    streak += 1;
    notifyListeners();
  }
}

final userProvider = ChangeNotifierProvider<UserData>((ref) => UserData());
