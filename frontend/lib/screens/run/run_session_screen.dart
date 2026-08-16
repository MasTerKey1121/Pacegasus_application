import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sphere_maps_flutter/sphere_maps_flutter.dart';
import '../../app_theme.dart';
import '../../models/side_quest.dart';
import '../../providers/run_provider.dart';
import '../../widgets/common.dart';
import 'run_summary_screen.dart';
import '../../providers/run_setup_provider.dart';

class RunSessionScreen extends ConsumerStatefulWidget {
  const RunSessionScreen({super.key});

  @override
  ConsumerState<RunSessionScreen> createState() => _RunSessionScreenState();
}

class _RunSessionScreenState extends ConsumerState<RunSessionScreen> {
  @override
  void initState() {
    super.initState();
    // Do not block GPS recording forever if the map provider cannot finish
    // loading (for example, an unavailable network or invalid map key).
    _mapLoadTimer = Timer(const Duration(seconds: 15), _askToStartWithoutMap);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startLocationTracking();
    });
  }

  void _openMissionsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _MissionsMiniWindow(),
    );
  }

  final _mapKey = GlobalKey<SphereMapState>();
  StreamSubscription<Position>? _positionSub;
  _MapPoint _currentPosition = const _MapPoint(13.7563, 100.5018);
  final List<_MapPoint> _routePoints = [];
  bool _hasLocationPermission = false;
  bool _hasInitialPosition = false;
  bool _mapReady = false;
  bool _mapLoadTimedOut = false;
  bool _mapLoadDialogShown = false;
  bool _startWithoutMapApproved = false;
  bool _countdownStarted = false;
  int _countdown = 3;
  Timer? _countdownTimer;
  Timer? _mapLoadTimer;
  Position? _lastMeasuredPosition;
  String? _locationMessage;

  String get _gistdaApiKey => dotenv.env['GISTDA_MAP_API_KEY'] ?? '';
  String get _gistdaBundleId =>
      dotenv.env['GISTDA_BUNDLE_ID'] ?? 'pacegasus_application';

  void _syncMap() {
    if (!_mapReady || _mapKey.currentState == null) return;
    final map = _mapKey.currentState!;
    map.call('location', args: [_currentPosition.toSphereLocation()]);
    map.call('Overlays.clear');
    map.call('Overlays.add', args: [Sphere.SphereObject('Marker', args: [
      _currentPosition.toSphereLocation(),
      {'title': 'Current location'},
    ])]);
    if (_routePoints.length > 1) {
      map.call('Overlays.add', args: [Sphere.SphereObject('Polyline', args: [
        _routePoints.map((point) => point.toSphereLocation()).toList(),
        {'lineWidth': 6, 'lineColor': 'rgba(169, 112, 255, 0.9)'},
      ])]);
    }
  }

  bool get _mapCanLoad => !Platform.isWindows && _gistdaApiKey.isNotEmpty;

  void _maybeStartCountdown() {
    if (_countdownStarted || !_hasLocationPermission || !_hasInitialPosition) {
      return;
    }
    if (_mapCanLoad && !_mapReady) {
      if (!_mapLoadTimedOut || !_startWithoutMapApproved) return;
    }
    _countdownStarted = true;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      if (_countdown <= 1) {
        timer.cancel();
        setState(() => _countdown = 0);
        _routePoints
          ..clear()
          ..add(_currentPosition);
        _lastMeasuredPosition = null;
        ref.read(runProvider).start();
      } else {
        setState(() => _countdown--);
      }
    });
  }

  Future<void> _askToStartWithoutMap() async {
    if (!mounted || _mapReady || !_mapCanLoad || _mapLoadDialogShown) return;

    setState(() {
      _mapLoadTimedOut = true;
      _mapLoadDialogShown = true;
    });

    final shouldStart = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.bg2,
        title: Text('โหลดแผนที่ไม่สำเร็จ', style: AppText.heading(size: 17)),
        content: Text(
          'ต้องการเริ่ม Session ต่อโดยไม่แสดงแผนที่ไหม? ระบบยังบันทึกเวลา ระยะทาง และ GPS ได้ตามปกติ',
          style: AppText.body(size: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('ยกเลิก', style: AppText.body(color: AppColors.red1)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('เริ่ม Session', style: AppText.body(color: AppColors.purple2)),
          ),
        ],
      ),
    );
    if (!mounted) return;

    if (shouldStart == true) {
      setState(() => _startWithoutMapApproved = true);
      _maybeStartCountdown();
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _startLocationTracking() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(
            () => _locationMessage = 'อนุญาตตำแหน่งเพื่อบันทึกเส้นทางการวิ่ง');
      }
      return;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (mounted) {
        setState(() => _locationMessage = 'กรุณาเปิดบริการตำแหน่ง');
      }
      return;
    }

    if (mounted) {
      setState(() => _hasLocationPermission = true);
      if (!_mapCanLoad) _mapReady = true;
    }
    _maybeStartCountdown();

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((pos) {
      final latLng = _MapPoint(pos.latitude, pos.longitude);
      if (!mounted) return;
      final run = ref.read(runProvider);
      if (run.isRunning && !run.isPaused && _lastMeasuredPosition != null) {
        final meters = Geolocator.distanceBetween(
          _lastMeasuredPosition!.latitude,
          _lastMeasuredPosition!.longitude,
          pos.latitude,
          pos.longitude,
        );
        final seconds = pos.timestamp
            .difference(_lastMeasuredPosition!.timestamp)
            .inMilliseconds / 1000;
        // Ignore GPS jumps and stationary noise.
        if (meters >= 2 && meters < 150 && seconds > 0) {
          run.recordGpsDistance(meters: meters, seconds: seconds);
        }
      }
      _lastMeasuredPosition = pos;
      setState(() {
        _hasInitialPosition = true;
        _currentPosition = latLng;
        if (_routePoints.isEmpty ||
            Geolocator.distanceBetween(
                  _routePoints.last.latitude,
                  _routePoints.last.longitude,
                  latLng.latitude,
                  latLng.longitude,
                ) >=
                5) {
          _routePoints.add(latLng);
        }
        _locationMessage = null;
      });
      _syncMap();
      _maybeStartCountdown();
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _countdownTimer?.cancel();
    _mapLoadTimer?.cancel();
    _mapKey.currentState?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final run = ref.watch(runProvider);
    final setup = ref.watch(runSetupProvider);
    final quests = setup.activeSideQuests;
    final doneCount = quests.where((q) => q.done).length;

    return Scaffold(
      backgroundColor: AppColors.bg1,
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _Stat(value: run.distanceKm.toStringAsFixed(2), label: 'กม.'),
                      _Stat(value: run.elapsedLabel, label: 'เวลา'),
                      _Stat(
                          value: run.speedKmh > 0
                              ? run.speedKmh.toStringAsFixed(1)
                              : '0.0',
                          label: 'กม./ชม.'),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Stack(
                        children: [
                          if (Platform.isWindows)
                            _WindowsLocationPanel(
                              position: _currentPosition,
                              hasLocation: _hasLocationPermission,
                            )
                          else if (_gistdaApiKey.isEmpty)
                            const _MapConfigurationPanel()
                          else
                            SphereMapWidget(
                              key: _mapKey,
                              apiKey: _gistdaApiKey,
                              bundleId: _gistdaBundleId,
                              eventName: [
                                IJavascriptChannel(
                                  name: 'Ready',
                                  onMessageReceived: (_) {
                                    _mapLoadTimer?.cancel();
                                    if (mounted) {
                                      setState(() {
                                        _mapReady = true;
                                        _mapLoadTimedOut = false;
                                      });
                                    }
                                    _syncMap();
                                    _maybeStartCountdown();
                                  },
                                ),
                                IJavascriptChannel(
                                  name: 'error',
                                  onMessageReceived: (message) {
                                    debugPrint('Sphere map error: ${message.message}');
                                    _askToStartWithoutMap();
                                  },
                                ),
                              ],
                              options: {
                                'layer': Sphere.SphereStatic('Layers', 'NORMAL'),
                                'zoom': 16,
                                'zoomRange': {'min': 3, 'max': 20},
                                'location': _currentPosition.toSphereLocation(),
                                'lastView': false,
                              },
                            ),
                          if (_locationMessage != null)
                            Positioned(
                              left: 12,
                              right: 12,
                              bottom: 12,
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.card.withOpacity(.94),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _locationMessage!,
                                  textAlign: TextAlign.center,
                                  style: AppText.body(size: 12),
                                ),
                              ),
                            ),
                          if (!run.isRunning)
                            Positioned.fill(
                              child: Container(
                                color: Colors.black.withOpacity(.38),
                                alignment: Alignment.center,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (!_hasLocationPermission ||
                                        (_mapCanLoad &&
                                            !_mapReady &&
                                            !_mapLoadTimedOut))
                                      const CircularProgressIndicator()
                                    else
                                      Text(
                                        _countdown > 0 ? '$_countdown' : 'เริ่ม!',
                                        style: AppText.heading(size: 64),
                                      ),
                                    const SizedBox(height: 12),
                                    Text(
                                      !_hasLocationPermission
                                          ? 'กำลังเชื่อมต่อ GPS'
                                          : (_mapCanLoad &&
                                                  !_mapReady &&
                                                  !_mapLoadTimedOut)
                                          ? 'กำลังโหลดแผนที่'
                                          : _mapLoadTimedOut
                                              ? 'แผนที่โหลดไม่สำเร็จ แต่บันทึกการวิ่งได้'
                                              : 'เตรียมพร้อมออกวิ่ง',
                                      style: AppText.heading(size: 15),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ระยะทางที่เหลือ',
                              style: AppText.body(
                                  size: 11.5, color: AppColors.textTertiary)),
                          Text(
                              '${run.distanceKm.toStringAsFixed(1)} / ${run.goalDistanceKm.toStringAsFixed(0)} km',
                              style: AppText.heading(size: 13.5)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('เป้าหมาย',
                              style: AppText.body(
                                  size: 11.5, color: AppColors.textTertiary)),
                          Text(run.goalPace, style: AppText.heading(size: 13.5)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (quests.isNotEmpty)
                    Center(
                      child: GestureDetector(
                        onTap: _openMissionsSheet,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF211B3D),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppColors.border),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withOpacity(.25),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4)),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('🎯', style: TextStyle(fontSize: 14)),
                              const SizedBox(width: 8),
                              Text('ภารกิจ $doneCount/${quests.length}',
                                  style: AppText.heading(size: 13)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: !run.isRunning || run.isStopping
                            ? null
                            : () => ref.read(runProvider).togglePause(),
                        child: Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Icon(
                              run.isPaused
                                  ? Icons.play_arrow_rounded
                                  : Icons.pause_rounded,
                              color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GradientButton(
                          label: '■ จบการวิ่ง',
                          loading: run.isStopping,
                          gradient: LinearGradient(
                              colors: [AppColors.red1, AppColors.red2]),
                          onTap: !run.isRunning || run.isStopping
                              ? null
                              : () async {
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: Text('จบการวิ่ง?'),
                                      content: Text('ต้องการจบการวิ่งจริงหรือไม่'),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: Text('ยกเลิก')),
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
                                            child: Text('จบการวิ่ง')),
                                      ],
                                    ),
                                  );
                                  if (confirmed != true) return;
                                  final result =
                                          await ref.read(runProvider).stop(
                                            sessionId: ref
                                                .read(runSetupProvider)
                                                .sessionId!,
                                            sideQuests: ref
                                                .read(runSetupProvider)
                                                .activeSideQuests,
                                            endLat: _currentPosition.latitude,
                                            endLng: _currentPosition.longitude,
                                            routePoints: _routePoints
                                                .map((point) => {
                                                      'lat': point.latitude,
                                                      'lng': point.longitude,
                                                    })
                                                .toList(),
                                          );
                                  if (!context.mounted) return;
                                  final failed =
                                      ref.read(runProvider).failedQuestTitles;
                                  if (failed.isNotEmpty) {
                                    showAppToast(
                                      context,
                                      'จบการวิ่งสำเร็จ แต่ยืนยันภารกิจไม่สำเร็จ: '
                                      '${failed.join(', ')}',
                                    );
                                  }
                                  if (result != null && context.mounted) {
                                    Navigator.of(context).pushReplacement(
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              RunSummaryScreen(result: result)),
                                    );
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    run.isPaused
                        ? 'หยุดชั่วคราว · ${run.elapsedLabel}'
                        : 'กำลังวิ่ง · ${run.elapsedLabel}',
                    style: AppText.body(size: 11.5, color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// หน้าต่างเล็ก ๆ (modal bottom sheet) แสดงภารกิจที่เลือกไว้ตอนหน้าเลือกประเภทการวิ่ง
/// กดจบทีละภารกิจได้เลยระหว่างที่ยังวิ่งอยู่
class _MapPoint {
  const _MapPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  Map<String, double> toSphereLocation() => {'lat': latitude, 'lon': longitude};
}

class _MapConfigurationPanel extends StatelessWidget {
  const _MapConfigurationPanel();

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFF211B3D),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Text(
          'GISTDA_MAP_API_KEY is missing from .env',
          textAlign: TextAlign.center,
          style: AppText.body(size: 13, color: AppColors.textSecondary),
        ),
      );
}

class _WindowsLocationPanel extends StatelessWidget {
  const _WindowsLocationPanel({
    required this.position,
    required this.hasLocation,
  });

  final _MapPoint position;
  final bool hasLocation;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF211B3D),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_on_rounded,
                  color: AppColors.purple2, size: 48),
              const SizedBox(height: 12),
              Text(
                hasLocation ? 'กำลังบันทึกตำแหน่ง GPS' : 'กำลังเชื่อมต่อ GPS',
                style: AppText.heading(size: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'แผนที่ยังไม่รองรับบน Windows',
                textAlign: TextAlign.center,
                style: AppText.body(size: 12, color: AppColors.textSecondary),
              ),
              if (hasLocation) ...[
                const SizedBox(height: 12),
                Text(
                  '${position.latitude.toStringAsFixed(5)}, '
                  '${position.longitude.toStringAsFixed(5)}',
                  style: AppText.body(size: 12, color: AppColors.textTertiary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MissionsMiniWindow extends ConsumerWidget {
  const _MissionsMiniWindow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setup = ref.watch(runSetupProvider);
    final quests = setup.activeSideQuests;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF17122B),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('ภารกิจระหว่างวิ่ง', style: AppText.heading(size: 15)),
                RoundIconButton(
                    icon: Icons.close, onTap: () => Navigator.of(context).pop()),
              ],
            ),
            const SizedBox(height: 12),
            if (quests.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('ไม่ได้เลือกภารกิจไว้สำหรับการวิ่งนี้',
                    style:
                        AppText.body(size: 12.5, color: AppColors.textSecondary)),
              )
            else
              ...quests.map((q) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      borderColor:
                          q.done ? AppColors.green1.withOpacity(.4) : AppColors.border,
                      child: Row(
                        children: [
                          Text(q.icon ?? '🎯', style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(q.title, style: AppText.heading(size: 13.5)),
                                if (q.description.isNotEmpty)
                                  Text(q.description,
                                      style: AppText.body(
                                          size: 11.5, color: AppColors.textSecondary)),
                                Text('+${q.coinReward} coin',
                                    style:
                                        AppText.body(size: 11, color: AppColors.gold1)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _MissionActionButton(quest: q),
                        ],
                      ),
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

class _MissionActionButton extends ConsumerWidget {
  final ActiveSideQuest quest;
  const _MissionActionButton({required this.quest});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setup = ref.watch(runSetupProvider);
    final loading = setup.isCompletingQuest(quest.sideQuestId);

    if (quest.done) {
      return const Icon(Icons.check_circle, color: AppColors.green1, size: 26);
    }

    if (loading) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.4),
      );
    }

    return GestureDetector(
      onTap: () =>
          ref.read(runSetupProvider).completeSideQuest(quest.sideQuestId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.purple2.withOpacity(.18),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.purple2),
        ),
        child: Text('จบภารกิจ',
            style: AppText.body(
                size: 11.5, weight: FontWeight.w600, color: AppColors.purple2)),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: AppText.heading(size: 22)),
        const SizedBox(height: 2),
        Text(label,
            style: AppText.body(size: 11.5, color: AppColors.textTertiary)),
      ],
    );
  }
}
