import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UserData extends ChangeNotifier {
  String username = 'UserName';
  int level = 1;
  int coin = 500;
  int exp = 0;
  double totalKm = 0;
  int totalSessions = 0;
  int streak = 0;
  String goalLabel = 'วิ่ง 10K · Sub 1:40';

  void addReward({int coin = 0, int exp = 0}) {
    this.coin += coin;
    this.exp += exp;
    // very small mock level-up curve: every 100 exp = 1 level.
    level = 1 + (this.exp ~/ 100);
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
