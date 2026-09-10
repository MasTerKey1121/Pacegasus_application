import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';
import '../../app_theme.dart';
import '../../models/side_quest.dart';
import '../../providers/auth_provider.dart';
import '../../providers/run_provider.dart';
import '../../widgets/common.dart';
import 'run_summary_screen.dart';
import '../../providers/run_setup_provider.dart';
import '../../services/run_draft_store.dart';

class RunSessionScreen extends ConsumerStatefulWidget {
  const RunSessionScreen({super.key});

  @override
  ConsumerState<RunSessionScreen> createState() => _RunSessionScreenState();
}

class _RunSessionScreenState extends ConsumerState<RunSessionScreen> {
  bool get _isTreadmill =>
      ref.read(runSetupProvider).environment == 'treadmill';
  final _treadmillDistanceController = TextEditingController();
  int _backStep = 0;
  Timer? _backResetTimer;
  Timer? _draftTimer;

  @override
  void initState() {
    super.initState();
    _draftTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _saveDraft());
    if (_isTreadmill) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startTreadmill());
      return;
    }
    _gistdaStyleFuture = _loadGistdaDarkStyle();
    // Do not block GPS recording forever if the map provider cannot finish
    // loading (for example, an unavailable network or invalid map key).
    _mapLoadTimer = Timer(const Duration(seconds: 15), () {
      debugPrint(
        '[GISTDA Map] timeout after 15s: mapReady=$_mapReady, '
        'gpsPermission=$_hasLocationPermission, '
        'initialGps=$_hasInitialPosition',
      );
      _askToStartWithoutMap();
    });
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

  MapLibreMapController? _mapController;
  Future<String>? _gistdaStyleFuture;
  Line? _routeBorderLine;
  Line? _routeLine;
  Circle? _startMarker;
  Circle? _currentMarker;
  bool _syncingMapOverlays = false;
  bool _mapOverlaySyncQueued = false;
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

  String _withGistdaKey(String url) =>
      '$url${url.contains('?') ? '&' : '?'}key='
      '${Uri.encodeQueryComponent(_gistdaApiKey)}';

  Future<String> _loadGistdaDarkStyle() async {
    const styleUrl =
        'https://basemap.sphere.gistda.or.th/vector/sphere_night.json';
    const capabilitiesUrl =
        'https://basemap.sphere.gistda.or.th/capabilities/sphere.json';

    final responses = await Future.wait([
      http.get(Uri.parse(styleUrl)),
      http.get(Uri.parse(capabilitiesUrl)),
    ]);
    if (responses.any((response) => response.statusCode != 200)) {
      throw StateError('GISTDA vector style could not be loaded');
    }

    final style = Map<String, dynamic>.from(
      jsonDecode(responses[0].body) as Map,
    );
    final capabilities = Map<String, dynamic>.from(
      jsonDecode(responses[1].body) as Map,
    );
    final rawTiles = capabilities['tiles'] as List<dynamic>? ?? const [];
    if (rawTiles.isEmpty) {
      throw StateError('GISTDA vector tile URL is missing');
    }

    final sources = Map<String, dynamic>.from(style['sources'] as Map);
    sources['sphere'] = <String, dynamic>{
      'type': 'vector',
      'tiles': rawTiles
          .map((tile) => _withGistdaKey(tile.toString()))
          .toList(growable: false),
      'minzoom': capabilities['minzoom'] ?? 0,
      'maxzoom': capabilities['maxzoom'] ?? 18,
      'attribution': capabilities['attribution'] ?? 'GISTDA sphere',
    };

    // GISTDA protects raster tile requests with the same API key. Preserve
    // the official night-style hillshade while authenticating its tiles.
    final dem = sources['dem'];
    if (dem is Map) {
      final demSource = Map<String, dynamic>.from(dem);
      final demTiles = demSource['tiles'];
      if (demTiles is List) {
        demSource['tiles'] = demTiles
            .map((tile) => _withGistdaKey(tile.toString()))
            .toList(growable: false);
      }
      sources['dem'] = demSource;
    }
    style['sources'] = sources;
    return jsonEncode(style);
  }

  void _syncMap() {
    final controller = _mapController;
    if (!_mapReady || controller == null) return;
    controller.animateCamera(
      CameraUpdate.newLatLng(_currentPosition.toMapLatLng()),
      duration: const Duration(milliseconds: 350),
    );
    _syncMapOverlays();
  }

  Future<void> _syncMapOverlays() async {
    final controller = _mapController;
    if (!_mapReady || controller == null) return;
    if (_syncingMapOverlays) {
      _mapOverlaySyncQueued = true;
      return;
    }

    _syncingMapOverlays = true;
    try {
      final route = _routePoints
          .map((point) => point.toMapLatLng())
          .toList(growable: false);
      final current = _currentPosition.toMapLatLng();
      final start = route.isEmpty ? current : route.first;

      if (_startMarker == null) {
        _startMarker = await controller.addCircle(
          CircleOptions(
            geometry: start,
            circleRadius: 7,
            circleColor: '#34D399',
            circleStrokeColor: '#081018',
            circleStrokeWidth: 3,
          ),
        );
      } else {
        await controller.updateCircle(
          _startMarker!,
          CircleOptions(geometry: start),
        );
      }

      if (_currentMarker == null) {
        _currentMarker = await controller.addCircle(
          CircleOptions(
            geometry: current,
            circleRadius: 8,
            circleColor: '#FF4D18',
            circleStrokeColor: '#FFFFFF',
            circleStrokeWidth: 2,
          ),
        );
      } else {
        await controller.updateCircle(
          _currentMarker!,
          CircleOptions(geometry: current),
        );
      }

      if (route.length > 1) {
        if (_routeBorderLine == null) {
          _routeBorderLine = await controller.addLine(
            LineOptions(
              geometry: route,
              lineColor: '#101318',
              lineWidth: 9,
              lineOpacity: .9,
              lineJoin: 'round',
            ),
          );
          _routeLine = await controller.addLine(
            LineOptions(
              geometry: route,
              lineColor: '#FF4D18',
              lineWidth: 6,
              lineOpacity: 1,
              lineJoin: 'round',
            ),
          );
        } else {
          await controller.updateLine(
            _routeBorderLine!,
            LineOptions(geometry: route),
          );
          await controller.updateLine(
            _routeLine!,
            LineOptions(geometry: route),
          );
        }
      }
    } catch (error) {
      debugPrint('[GISTDA Map] overlay sync failed: $error');
    } finally {
      _syncingMapOverlays = false;
      if (_mapOverlaySyncQueued) {
        _mapOverlaySyncQueued = false;
        unawaited(_syncMapOverlays());
      }
    }
  }

  void _markMapReady(String source) {
    if (!mounted || _mapReady) return;
    debugPrint(
        '[GISTDA Map] ready via $source; starting countdown when GPS is ready');
    _mapLoadTimer?.cancel();
    setState(() {
      _mapReady = true;
      _mapLoadTimedOut = false;
    });
    _syncMap();
    _maybeStartCountdown();
  }

  bool get _mapCanLoad => !Platform.isWindows && _gistdaApiKey.isNotEmpty;

  void _startTreadmill() {
    if (!mounted) return;
    setState(() {
      _hasLocationPermission = true;
      _hasInitialPosition = true;
      _mapReady = true;
      _locationMessage = null;
    });
    _maybeStartCountdown();
  }

  void _maybeStartCountdown() {
    if (ref.read(runProvider).isRunning) return;
    if (_countdownStarted ||
        (!_isTreadmill && (!_hasLocationPermission || !_hasInitialPosition))) {
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
            child: Text('เริ่ม Session',
                style: AppText.body(color: AppColors.purple2)),
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
    debugPrint('[GPS] initial permission: $permission');
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      debugPrint('[GPS] permission after request: $permission');
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(
            () => _locationMessage = 'อนุญาตตำแหน่งเพื่อบันทึกเส้นทางการวิ่ง');
      }
      debugPrint('[GPS] location permission was denied');
      return;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (mounted) {
        setState(() => _locationMessage = 'กรุณาเปิดบริการตำแหน่ง');
      }
      debugPrint('[GPS] location service is disabled');
      return;
    }

    if (mounted) {
      setState(() => _hasLocationPermission = true);
      if (!_mapCanLoad) _mapReady = true;
    }
    debugPrint('[GPS] location service is enabled; listening for positions');
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
                .inMilliseconds /
            1000;
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
      _saveDraft();
      _syncMap();
      _maybeStartCountdown();
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _countdownTimer?.cancel();
    _mapLoadTimer?.cancel();
    _backResetTimer?.cancel();
    _draftTimer?.cancel();
    _treadmillDistanceController.dispose();
    super.dispose();
  }

  Future<void> _handleBack() async {
    final run = ref.read(runProvider);
    if (!run.isRunning || run.isStopping) return;
    _backResetTimer?.cancel();
    if (_backStep == 0) {
      _backStep = 1;
      showAppToast(context,
          'Session กำลังดำเนินอยู่ กดย้อนกลับอีกครั้งเพื่อยืนยันการจบ');
    } else if (_backStep == 1) {
      _backStep = 2;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('ต้องการจบ Session การวิ่งหรือไม่?'),
          content: const Text(
              'กดย้อนกลับอีกครั้งภายใน 5 วินาทีเพื่อจบ Session หรือเลือกวิ่งต่อ'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('วิ่งต่อ'),
            ),
          ],
        ),
      );
      if (mounted)
        showAppToast(context, 'หากต้องการจบ Session ให้กดย้อนกลับอีกครั้ง');
    } else {
      await _finishRun();
      return;
    }
    _backResetTimer = Timer(const Duration(seconds: 5), () => _backStep = 0);
  }

  Future<void> _finishTreadmill() async {
    final controller = _treadmillDistanceController;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('จบการวิ่งบนลู่'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration:
              const InputDecoration(labelText: 'ระยะทางจากลู่วิ่ง (กม.)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ยกเลิก')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('จบการวิ่ง')),
        ],
      ),
    );
    if (confirmed != true) return;
    final distance = double.tryParse(controller.text.trim());
    if (distance == null || distance < 0) {
      if (mounted) showAppToast(context, 'กรุณากรอกระยะทางที่ถูกต้อง');
      return;
    }
    ref.read(runProvider).setDistance(distance);
    await _finishRun();
  }

  Future<void> _finishRun() async {
    final result = await ref.read(runProvider).stop(
          sessionId: ref.read(runSetupProvider).sessionId!,
          sideQuests: ref.read(runSetupProvider).activeSideQuests,
          endLat: _currentPosition.latitude,
          endLng: _currentPosition.longitude,
          routePoints: _routePoints
              .map((point) => {'lat': point.latitude, 'lng': point.longitude})
              .toList(),
        );
    if (!mounted || result == null) return;
    await runDraftStore.clear();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => RunSummaryScreen(result: result)),
    );
  }

  Future<void> _saveDraft() async {
    final run = ref.read(runProvider);
    final setup = ref.read(runSetupProvider);
    final ownerUserId = ref.read(authProvider).user?['id']?.toString();
    if (setup.sessionId == null || ownerUserId == null) return;
    await runDraftStore.save({
      'ownerUserId': ownerUserId,
      'sessionId': setup.sessionId,
      'environment': setup.environment,
      'elapsedSeconds': run.elapsedSeconds,
      'distanceKm': run.distanceKm,
      'isPaused': run.isPaused,
      'routePoints': _routePoints
          .map((point) => {'lat': point.latitude, 'lng': point.longitude})
          .toList(),
      'sideQuests': setup.activeSideQuests
          .map((quest) => {
                'id': quest.sideQuestId,
                'title': quest.title,
                'description': quest.description,
                'icon': quest.icon,
                'coinReward': quest.coinReward,
                'done': quest.done,
              })
          .toList(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final run = ref.watch(runProvider);
    final setup = ref.watch(runSetupProvider);
    final quests = setup.activeSideQuests;
    final doneCount = quests.where((q) => q.done).length;

    return WillPopScope(
        onWillPop: () async {
          if (!ref.read(runProvider).isRunning) return true;
          await _handleBack();
          return false;
        },
        child: Scaffold(
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
                          _Stat(
                              value: run.distanceKm.toStringAsFixed(2),
                              label: 'กม.'),
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
                              if (_isTreadmill)
                                const _TreadmillPanel()
                              else if (Platform.isWindows)
                                _WindowsLocationPanel(
                                  position: _currentPosition,
                                  hasLocation: _hasLocationPermission,
                                )
                              else if (_gistdaApiKey.isEmpty)
                                const _MapConfigurationPanel()
                              else
                                FutureBuilder<String>(
                                  future: _gistdaStyleFuture,
                                  builder: (context, snapshot) {
                                    if (snapshot.hasError) {
                                      return _MapLoadErrorPanel(
                                        onRetry: () {
                                          setState(() {
                                            _gistdaStyleFuture =
                                                _loadGistdaDarkStyle();
                                          });
                                        },
                                      );
                                    }
                                    if (!snapshot.hasData) {
                                      return const _MapLoadingPanel();
                                    }
                                    return Stack(
                                      children: [
                                        MapLibreMap(
                                          styleString: snapshot.data!,
                                          initialCameraPosition: CameraPosition(
                                            target:
                                                _currentPosition.toMapLatLng(),
                                            zoom: 16,
                                          ),
                                          minMaxZoomPreference:
                                              const MinMaxZoomPreference(3, 19),
                                          compassEnabled: false,
                                          rotateGesturesEnabled: false,
                                          tiltGesturesEnabled: false,
                                          logoEnabled: false,
                                          annotationOrder: const [
                                            AnnotationType.line,
                                            AnnotationType.circle,
                                          ],
                                          onMapCreated: (controller) {
                                            _mapController = controller;
                                            _routeBorderLine = null;
                                            _routeLine = null;
                                            _startMarker = null;
                                            _currentMarker = null;
                                          },
                                          onStyleLoadedCallback: () =>
                                              _markMapReady(
                                            'GISTDA night vector style',
                                          ),
                                        ),
                                        const Positioned(
                                          left: 8,
                                          bottom: 8,
                                          child: _GistdaAttribution(),
                                        ),
                                      ],
                                    );
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
                                        if (!_isTreadmill &&
                                            (!_hasLocationPermission ||
                                                (_mapCanLoad &&
                                                    !_mapReady &&
                                                    !_mapLoadTimedOut)))
                                          const CircularProgressIndicator()
                                        else
                                          Text(
                                            _countdown > 0
                                                ? '$_countdown'
                                                : 'เริ่ม!',
                                            style: AppText.heading(size: 64),
                                          ),
                                        const SizedBox(height: 12),
                                        Text(
                                          _isTreadmill
                                              ? 'เตรียมเริ่มวิ่งบนลู่'
                                              : !_hasLocationPermission
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
                                      size: 11.5,
                                      color: AppColors.textTertiary)),
                              Text(
                                  '${run.distanceKm.toStringAsFixed(1)} / ${run.goalDistanceKm.toStringAsFixed(0)} km',
                                  style: AppText.heading(size: 13.5)),
                            ],
                          ),
                          GestureDetector(
                            onTap: _openMissionsSheet,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('ภารกิจ',
                                    style: AppText.body(
                                        size: 11.5,
                                        color: AppColors.textTertiary)),
                                Text(
                                  quests.isEmpty
                                      ? 'ไม่มีภารกิจ'
                                      : '$doneCount/${quests.length}',
                                  style: AppText.heading(size: 13.5),
                                ),
                              ],
                            ),
                          ),
                        ],
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
                                  : () => _isTreadmill
                                      ? _finishTreadmill()
                                      : _finishRun(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        run.isPaused
                            ? 'หยุดชั่วคราว · ${run.elapsedLabel}'
                            : 'กำลังวิ่ง · ${run.elapsedLabel}',
                        style: AppText.body(
                            size: 11.5, color: AppColors.textTertiary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ));
  }
}

/// หน้าต่างเล็ก ๆ (modal bottom sheet) แสดงภารกิจที่เลือกไว้ตอนหน้าเลือกประเภทการวิ่ง
/// กดจบทีละภารกิจได้เลยระหว่างที่ยังวิ่งอยู่
class _MapPoint {
  const _MapPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  LatLng toMapLatLng() => LatLng(latitude, longitude);
}

class _GistdaAttribution extends StatelessWidget {
  const _GistdaAttribution();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .62),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Text(
            '© GISTDA sphere',
            style: AppText.body(size: 9, color: Colors.white),
          ),
        ),
      );
}

class _MapLoadingPanel extends StatelessWidget {
  const _MapLoadingPanel();

  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: Color(0xFF0D131C),
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFFFF4D18)),
        ),
      );
}

class _MapLoadErrorPanel extends StatelessWidget {
  const _MapLoadErrorPanel({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: const Color(0xFF0D131C),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.map_outlined,
                  color: AppColors.textSecondary,
                  size: 40,
                ),
                const SizedBox(height: 10),
                Text(
                  'โหลดแผนที่ GISTDA ไม่สำเร็จ',
                  textAlign: TextAlign.center,
                  style: AppText.body(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: onRetry,
                  child: const Text('ลองอีกครั้ง'),
                ),
              ],
            ),
          ),
        ),
      );
}

class _MapConfigurationPanel extends StatelessWidget {
  const _MapConfigurationPanel();

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFF211B3D),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Text(
          'ไม่พบ GISTDA_MAP_API_KEY ในไฟล์ .env',
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

class _TreadmillPanel extends StatelessWidget {
  const _TreadmillPanel();

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFF211B3D),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.directions_run_rounded,
                color: AppColors.purple2, size: 54),
            const SizedBox(height: 12),
            Text('กำลังวิ่งบนลู่', style: AppText.heading(size: 17)),
            const SizedBox(height: 6),
            Text(
              'ระบบจะให้กรอกระยะจากลู่วิ่งเมื่อจบ Session',
              textAlign: TextAlign.center,
              style: AppText.body(size: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
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
                    icon: Icons.close,
                    onTap: () => Navigator.of(context).pop()),
              ],
            ),
            const SizedBox(height: 12),
            if (quests.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('ไม่ได้เลือกภารกิจไว้สำหรับการวิ่งนี้',
                    style: AppText.body(
                        size: 12.5, color: AppColors.textSecondary)),
              )
            else
              ...quests.map((q) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      borderColor: q.done
                          ? AppColors.green1.withOpacity(.4)
                          : AppColors.border,
                      child: Row(
                        children: [
                          Text(q.icon ?? '🎯',
                              style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(q.title,
                                    style: AppText.heading(size: 13.5)),
                                if (q.description.isNotEmpty)
                                  Text(q.description,
                                      style: AppText.body(
                                          size: 11.5,
                                          color: AppColors.textSecondary)),
                                Text('+${q.coinReward} coin',
                                    style: AppText.body(
                                        size: 11, color: AppColors.gold1)),
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
