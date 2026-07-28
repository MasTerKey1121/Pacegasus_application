import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_client.dart';
import '../services/program_api.dart';

final programApiProvider = Provider<ProgramApi>(
  (ref) => ProgramApi(ref.read(apiClientProvider)),
);

class ProgramNotifier extends ChangeNotifier {
  ProgramNotifier(this._api);

  final ProgramApi _api;
  List<Map<String, dynamic>> quests = const [];
  bool isLoading = false;
  String? errorMessage;

  Map<String, dynamic>? get todayQuest {
    final today = DateTime.now();
    final todayKey =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    for (final quest in quests) {
      final scheduledDate = quest['scheduled_date']?.toString() ?? '';
      if (scheduledDate.startsWith(todayKey)) return quest;
    }
    return null;
  }

  Future<bool> loadCurrentWeek() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final response = await _api.getCurrentWeek();
      final data = response['data'] as Map<String, dynamic>? ?? const {};
      final rawQuests = data['quests'] as List<dynamic>? ?? const [];
      quests = rawQuests
          .whereType<Map>()
          .map((quest) => Map<String, dynamic>.from(quest))
          .toList(growable: false);
      isLoading = false;
      notifyListeners();
      return true;
    } catch (error) {
      errorMessage = error.toString();
      isLoading = false;
      notifyListeners();
      return false;
    }
  }
}

final programProvider = ChangeNotifierProvider<ProgramNotifier>(
  (ref) => ProgramNotifier(ref.read(programApiProvider)),
);
