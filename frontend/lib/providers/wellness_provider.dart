import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/wellness_data.dart';
import '../services/wellness_api.dart';
import 'auth_provider.dart';

final wellnessApiProvider = Provider<WellnessApi>(
  (ref) => WellnessApi(ref.read(apiClientProvider)),
);

class WellnessNotifier extends ChangeNotifier {
  final WellnessApi api;

  WellnessNotifier(this.api);

  WellnessEntry entry = WellnessEntry();

  bool completedToday = false;
  bool hasLoadedToday = false;
  bool isLoadingToday = false;
  bool isSaving = false;
  int awardedCoins = 0;
  String? errorMessage;
  int _accountVersion = 0;
  Future<bool>? _todayRequest;

  void update(void Function(WellnessEntry e) mutate) {
    mutate(entry);
    notifyListeners();
  }

  void reset() {
    _accountVersion++;
    _todayRequest = null;
    entry = WellnessEntry();
    completedToday = false;
    hasLoadedToday = false;
    isLoadingToday = false;
    isSaving = false;
    awardedCoins = 0;
    errorMessage = null;
    notifyListeners();
  }

  Future<bool> submit() async {
    if (isSaving) return false;
    if (!hasLoadedToday || isLoadingToday) {
      errorMessage = 'กรุณาโหลดสถานะ Wellness ของวันนี้ก่อนบันทึก';
      notifyListeners();
      return false;
    }
    if (!entry.isComplete) {
      errorMessage = 'กรุณาเลือกข้อมูล Daily Wellness ให้ครบทุกข้อ';
      notifyListeners();
      return false;
    }

    isSaving = true;
    awardedCoins = 0;
    final accountVersion = _accountVersion;
    errorMessage = null;
    notifyListeners();

    try {
      if (completedToday) {
        await api.update(entry.toApiJson());
      } else {
        final response = await api.create(entry.toApiJson());
        if (accountVersion != _accountVersion) return false;
        final reward = response['data']?['record']?['reward'];
        if (reward is Map && reward['awarded'] == true) {
          awardedCoins = (reward['coins'] as num?)?.toInt() ?? 0;
        }
      }

      if (accountVersion != _accountVersion) return false;
      completedToday = true;
      isSaving = false;
      notifyListeners();

      return true;
    } catch (e) {
      if (accountVersion != _accountVersion) return false;
      errorMessage = e.toString();
      isSaving = false;
      notifyListeners();

      return false;
    }
  }

  Future<bool> loadToday() => _todayRequest ??= _loadToday();

  Future<bool> _loadToday() async {
    final accountVersion = _accountVersion;
    isLoadingToday = true;
    errorMessage = null;
    notifyListeners();
    try {
      final response = await api.getToday();
      if (accountVersion != _accountVersion) return false;
      final data = response['data'] as Map<String, dynamic>? ?? const {};
      final status = data['status'] as String?;
      final record = data['record'] as Map<String, dynamic>?;
      if (status != 'done' && status != 'not_done') {
        throw const FormatException('Invalid wellness status');
      }

      completedToday = status == 'done';
      entry =
          record == null ? WellnessEntry() : WellnessEntry.fromRecord(record);
      hasLoadedToday = true;
      return true;
    } catch (_) {
      if (accountVersion == _accountVersion) {
        errorMessage = 'โหลดสถานะ Wellness ของวันนี้ไม่สำเร็จ กรุณาลองใหม่';
      }
      return false;
    } finally {
      if (accountVersion == _accountVersion) {
        isLoadingToday = false;
        _todayRequest = null;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _accountVersion++;
    super.dispose();
  }
}

final wellnessProvider = ChangeNotifierProvider<WellnessNotifier>(
  (ref) {
    final notifier = WellnessNotifier(ref.read(wellnessApiProvider));
    ref.listen<AuthState>(authProvider, (previous, next) {
      final previousUserId = previous?.user?['id'];
      final nextUserId = next.user?['id'];
      if (previousUserId != nextUserId) notifier.reset();
    });
    return notifier;
  },
);
