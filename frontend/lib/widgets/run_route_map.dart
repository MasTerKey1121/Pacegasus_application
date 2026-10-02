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
  const RunRouteMap(
      {super.key,
      required this.points,
      this.loading = false,
      this.treadmill = false,
      this.loadFailed = false,
      this.onRetry});
  @override
  State<RunRouteMap> createState() => _RunRouteMapState();
}

class _RunRouteMapState extends State<RunRouteMap> {
  Future<String>? _style;
  MapLibreMapController? _controller;
  bool _failed = false;

  bool get _nativeSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    if (_nativeSupported &&
        gistdaMapApiKey.isNotEmpty &&
        widget.points.isNotEmpty &&
        !widget.treadmill) {
      _style = loadGistdaDarkStyle();
    }
  }

  Future<void> _drawRoute() async {
    final controller = _controller;
    if (controller == null) return;
    final route = widget.points
        .map((point) => LatLng(point.latitude, point.longitude))
        .toList();
    if (route.isEmpty) return;
    try {
      if (route.length > 1) {
        await controller.addLine(
            LineOptions(geometry: route, lineColor: '#071321', lineWidth: 7));
        if (!mounted) return;
        await controller.addLine(
            LineOptions(geometry: route, lineColor: '#52B9FF', lineWidth: 4));
      }
      if (!mounted) return;
      await controller.addCircle(CircleOptions(
          geometry: route.first,
          circleColor: '#34D399',
          circleRadius: 6,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 2));
      if (!mounted) return;
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
      if (!mounted) return;
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
      if (mounted) setState(() => _failed = true);
    }
  }

  Widget _preview({String? caption}) => Stack(fit: StackFit.expand, children: [
        CustomPaint(painter: _RoutePainter(widget.points)),
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
                    if (snapshot.hasError) {
                      return _preview(
                          caption: 'เส้นทาง GPS • โหลดแผนที่พื้นหลังไม่สำเร็จ');
                    }
                    if (!snapshot.hasData) {
                      return _preview(caption: 'กำลังโหลดแผนที่…');
                    }
                    return MapLibreMap(
                        styleString: snapshot.data!,
                        initialCameraPosition: CameraPosition(
                            target: LatLng(widget.points.first.latitude,
                                widget.points.first.longitude),
                            zoom: 15),
                        compassEnabled: false,
                        rotateGesturesEnabled: false,
                        tiltGesturesEnabled: false,
                        scrollGesturesEnabled: false,
                        zoomGesturesEnabled: false,
                        annotationOrder: const [
                          AnnotationType.line,
                          AnnotationType.circle
                        ],
                        onMapCreated: (controller) => _controller = controller,
                        onStyleLoadedCallback: _drawRoute);
                  }),
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
