import 'dart:async';
import 'package:flutter/gestures.dart';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../app_theme.dart';
import '../models/run_result.dart';
import '../services/gistda_map_style.dart';

/// Uses only recorded session coordinates; never the device's current location.
class RunRouteMap extends StatefulWidget {
  final List<RunRoutePoint> points;
  final bool loading, treadmill, loadFailed;
  final VoidCallback? onRetry;
  final String? sessionId;
  final Future<String> Function()? styleLoader;
  const RunRouteMap(
      {super.key,
      required this.points,
      this.loading = false,
      this.treadmill = false,
      this.loadFailed = false,
      this.onRetry,
      this.sessionId,
      this.styleLoader});
  @override
  State<RunRouteMap> createState() => _RunRouteMapState();
}

class _RunRouteMapState extends State<RunRouteMap> {
  Future<String>? _style;
  MapLibreMapController? _controller;
  bool _failed = false;
  bool _styleReady = false, _drawing = false, _drawAgain = false;
  int _mapVersion = 0;
  Timer? _loadTimer;
  int? _routeSignature;
  int get _signature => Object.hashAll(
      widget.points.map((p) => Object.hash(p.latitude, p.longitude)));

  bool get _nativeSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _canLoad =>
      _nativeSupported &&
      (widget.styleLoader != null || gistdaMapApiKey.isNotEmpty) &&
      widget.points.isNotEmpty &&
      !widget.treadmill;
  @override
  void initState() {
    super.initState();
    _routeSignature = _signature;
    _prepareStyle();
  }

  void _prepareStyle() {
    if (!_canLoad) return;
    _failed = false;
    _styleReady = false;
    _style = (widget.styleLoader ?? loadGistdaDarkStyle)();
    _loadTimer?.cancel();
    final version = _mapVersion;
    _loadTimer = Timer(const Duration(seconds: 20), () {
      if (mounted && version == _mapVersion && !_styleReady) {
        setState(() => _failed = true);
      }
    });
  }

  @override
  void didUpdateWidget(covariant RunRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId ||
        oldWidget.treadmill != widget.treadmill) {
      _controller = null;
      _style = null;
      _failed = false;
      _styleReady = false;
      _mapVersion++;
      _loadTimer?.cancel();
      _prepareStyle();
    } else if (_style == null && _canLoad) {
      _prepareStyle();
    } else if (_routeSignature != _signature && _styleReady) {
      unawaited(_drawRoute());
    }
    _routeSignature = _signature;
  }

  void _retry() {
    setState(() {
      _controller = null;
      _style = null;
      _mapVersion++;
      _prepareStyle();
    });
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
    super.dispose();
  }

  Future<void> _drawRoute() async {
    final controller = _controller;
    if (controller == null || !_styleReady) return;
    if (_drawing) {
      _drawAgain = true;
      return;
    }
    _drawing = true;
    final version = _mapVersion;
    final route = widget.points
        .map((point) => LatLng(point.latitude, point.longitude))
        .toList();
    if (route.isEmpty) {
      _drawing = false;
      return;
    }
    try {
      await controller.clearLines();
      await controller.clearCircles();
      if (!mounted || version != _mapVersion) return;
      if (route.length > 1) {
        await controller.addLine(
            LineOptions(geometry: route, lineColor: '#071321', lineWidth: 7));
        if (!mounted || version != _mapVersion) return;
        await controller.addLine(
            LineOptions(geometry: route, lineColor: '#52B9FF', lineWidth: 4));
      }
      if (!mounted || version != _mapVersion) return;
      await controller.addCircle(CircleOptions(
          geometry: route.first,
          circleColor: '#34D399',
          circleRadius: 6,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 2));
      if (!mounted || version != _mapVersion) return;
      await controller.addCircle(CircleOptions(
          geometry: route.last,
          circleColor: '#52B9FF',
          circleRadius: 6,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 2));
      final south = route.map((point) => point.latitude).reduce(math.min);
      final north = route.map((point) => point.latitude).reduce(math.max);
      final west = route.map((point) => point.longitude).reduce(math.min);
      final east = route.map((point) => point.longitude).reduce(math.max);
      if (!mounted || version != _mapVersion) return;
      if (north - south < .00001 && east - west < .00001) {
        await controller
            .moveCamera(CameraUpdate.newLatLngZoom(route.first, 16));
      } else {
        await controller.moveCamera(CameraUpdate.newLatLngBounds(
            LatLngBounds(
                southwest: LatLng(south, west), northeast: LatLng(north, east)),
            left: 32,
            right: 32,
            top: 44,
            bottom: 40));
      }
    } catch (_) {
      if (mounted && version == _mapVersion) setState(() => _failed = true);
    } finally {
      _drawing = false;
      if (_drawAgain && mounted) {
        _drawAgain = false;
        unawaited(_drawRoute());
      }
    }
  }

  Widget _preview({String? caption}) => Stack(fit: StackFit.expand, children: [
        InteractiveViewer(
            minScale: .5,
            maxScale: 8,
            child: SizedBox.expand(
                child: CustomPaint(painter: _RoutePainter(widget.points)))),
        if (caption != null)
          Positioned(
              left: 12,
              right: 12,
              bottom: 8,
              child: Text(caption,
                  textAlign: TextAlign.center,
                  style:
                      AppText.body(size: 10, color: AppColors.textSecondary))),
      ]);

  @override
  Widget build(BuildContext context) => Semantics(
      label: 'เส้นทางการวิ่งที่เพิ่งจบ',
      child: Container(
          height: 180,
          width: double.infinity,
          decoration: BoxDecoration(
              color: const Color(0xFF141B2B),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.borderHi)),
          clipBehavior: Clip.antiAlias,
          child: Stack(fit: StackFit.expand, children: [
            if (widget.treadmill || widget.points.isEmpty)
              Center(
                  child: widget.loading && !widget.treadmill
                      ? const CircularProgressIndicator()
                      : Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(
                              widget.treadmill
                                  ? Icons.directions_run
                                  : Icons.location_off_outlined,
                              color: AppColors.textSecondary),
                          const SizedBox(height: 8),
                          Text(
                              widget.treadmill
                                  ? 'วิ่งบนลู่วิ่ง • ไม่มีเส้นทาง GPS'
                                  : widget.loadFailed
                                      ? 'โหลดข้อมูลเส้นทางไม่สำเร็จ'
                                      : 'ไม่มีข้อมูลเส้นทาง GPS สำหรับการวิ่งนี้',
                              textAlign: TextAlign.center,
                              style: AppText.body(
                                  size: 12, color: AppColors.textSecondary)),
                          if (widget.loadFailed &&
                              !widget.treadmill &&
                              widget.onRetry != null)
                            TextButton(
                                onPressed: widget.onRetry,
                                child: const Text('ลองอีกครั้ง')),
                        ]))
            else if (_style == null || _failed)
              _preview(caption: 'เส้นทาง GPS • แผนที่พื้นหลังไม่พร้อมใช้งาน')
            else
              FutureBuilder<String>(
                  future: _style,
                  builder: (_, snapshot) {
                    final version = _mapVersion;
                    if (snapshot.hasError) {
                      return _preview(
                          caption: 'เส้นทาง GPS • โหลดแผนที่พื้นหลังไม่สำเร็จ');
                    }
                    if (!snapshot.hasData) {
                      return _preview(caption: 'กำลังโหลดแผนที่…');
                    }
                    return MapLibreMap(
                        key: ValueKey(_mapVersion),
                        gestureRecognizers: {
                          Factory<OneSequenceGestureRecognizer>(
                              () => EagerGestureRecognizer())
                        },
                        styleString: snapshot.data!,
                        initialCameraPosition: CameraPosition(
                            target: LatLng(widget.points.first.latitude,
                                widget.points.first.longitude),
                            zoom: 15),
                        compassEnabled: false,
                        rotateGesturesEnabled: false,
                        tiltGesturesEnabled: false,
                        scrollGesturesEnabled: true,
                        zoomGesturesEnabled: true,
                        annotationOrder: const [
                          AnnotationType.line,
                          AnnotationType.circle
                        ],
                        onMapCreated: (controller) {
                          if (mounted && version == _mapVersion) {
                            _controller = controller;
                          }
                        },
                        onStyleLoadedCallback: () {
                          if (!mounted || version != _mapVersion) return;
                          _loadTimer?.cancel();
                          _styleReady = true;
                          unawaited(_drawRoute());
                        });
                  }),
            if (widget.loadFailed &&
                widget.onRetry != null &&
                widget.points.isNotEmpty &&
                !widget.treadmill)
              Positioned(
                  right: 8,
                  bottom: 32,
                  child: TextButton(
                      onPressed: widget.onRetry,
                      child: const Text('ลองโหลดข้อมูลเส้นทางใหม่'))),
            if (_canLoad && (_failed || (_style != null)))
              Positioned(
                  right: 8,
                  bottom: 2,
                  child: FutureBuilder<String>(
                      future: _style,
                      builder: (_, snap) => _failed || snap.hasError
                          ? TextButton(
                              onPressed: _retry,
                              child: const Text('ลองโหลดแผนที่ใหม่'))
                          : const SizedBox.shrink())),
            Positioned(
                left: 12,
                top: 10,
                child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: AppColors.bg1.withValues(alpha: .85),
                        borderRadius: BorderRadius.circular(12)),
                    child: Text('เส้นทางการวิ่ง',
                        style:
                            AppText.body(size: 12, weight: FontWeight.w600)))),
            if (widget.points.isNotEmpty && !widget.treadmill)
              Positioned(
                  right: 12,
                  top: 10,
                  child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: AppColors.bg1.withValues(alpha: .85),
                          borderRadius: BorderRadius.circular(12)),
                      child:
                          const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.circle, size: 8, color: Color(0xFF34D399)),
                        SizedBox(width: 4),
                        Text('เริ่ม', style: TextStyle(fontSize: 10)),
                        SizedBox(width: 8),
                        Icon(Icons.circle, size: 8, color: Color(0xFF52B9FF)),
                        SizedBox(width: 4),
                        Text('จบ', style: TextStyle(fontSize: 10)),
                      ]))),
            if (_style != null && !_failed && widget.points.isNotEmpty)
              const Positioned(
                  left: 8,
                  bottom: 3,
                  child: Text('GISTDA sphere',
                      style: TextStyle(
                          fontSize: 9, color: AppColors.textSecondary))),
          ])));
}

/// Offline fallback preserves the route's proportions using Mercator projection.
class _RoutePainter extends CustomPainter {
  final List<RunRoutePoint> points;
  _RoutePainter(this.points);
  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final projected = points.map((point) {
      final latitude = point.latitude.clamp(-85.0, 85.0) * math.pi / 180;
      return Offset(point.longitude * math.pi / 180,
          math.log(math.tan(math.pi / 4 + latitude / 2)));
    }).toList();
    final minX = projected.map((point) => point.dx).reduce(math.min);
    final maxX = projected.map((point) => point.dx).reduce(math.max);
    final minY = projected.map((point) => point.dy).reduce(math.min);
    final maxY = projected.map((point) => point.dy).reduce(math.max);
    final scale = math.min((size.width - 48) / math.max(maxX - minX, .000001),
        (size.height - 80) / math.max(maxY - minY, .000001));
    final center = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    final route = projected
        .map((point) => Offset(size.width / 2 + (point.dx - center.dx) * scale,
            size.height / 2 - (point.dy - center.dy) * scale))
        .toList();
    final path = Path()..moveTo(route.first.dx, route.first.dy);
    for (final point in route.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF52B9FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
    for (final marker in [
      (route.first, const Color(0xFF34D399)),
      (route.last, const Color(0xFF52B9FF))
    ]) {
      canvas.drawCircle(marker.$1, 7, Paint()..color = Colors.white);
      canvas.drawCircle(marker.$1, 5, Paint()..color = marker.$2);
    }
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) =>
      oldDelegate.points != points;
}
