import 'package:flutter/material.dart';

/// Temporary 2.5D mannequin, ready to be replaced by the final character asset.
class HomeAvatar extends StatelessWidget {
  const HomeAvatar({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
          child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
            width: 230,
            height: 310,
            child: Stack(children: [
              Positioned(
                  left: 0,
                  right: 0,
                  bottom: 8,
                  height: 62,
                  child: Container(
                      decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(120),
                    gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF9570AC), Color(0xFF352640)]),
                    border:
                        Border.all(color: const Color(0xFFB093C5), width: 2),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x66130D20),
                          blurRadius: 20,
                          offset: Offset(0, 12))
                    ],
                  ))),
              _part(87, 24, 58, 65, 28, const [
                Color(0xFFF0DEFC),
                Color(0xFFAF91C4),
                Color(0xFF785E93)
              ]),
              _part(53, 101, 27, 98, 20,
                  const [Color(0xFFCFBCE7), Color(0xFF816397)],
                  angle: .2),
              _part(153, 101, 27, 98, 20,
                  const [Color(0xFFCFBCE7), Color(0xFF816397)],
                  angle: -.2),
              _part(76, 178, 34, 84, 12,
                  const [Color(0xFF9578B2), Color(0xFF533E70)],
                  angle: .05),
              _part(122, 178, 34, 84, 12,
                  const [Color(0xFF9578B2), Color(0xFF533E70)],
                  angle: -.05),
              _part(72, 94, 88, 98, 30, const [
                Color(0xFFE2D4F4),
                Color(0xFFA78AC6),
                Color(0xFF715688)
              ]),
              const Positioned(
                  left: 101,
                  top: 118,
                  child: Text('P',
                      style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF694D87)))),
              _part(62, 251, 48, 24, 10,
                  const [Color(0xFFE3D4F6), Color(0xFFB398D0)]),
              _part(123, 251, 48, 24, 10,
                  const [Color(0xFFE3D4F6), Color(0xFFB398D0)]),
            ])),
      ));

  Widget _part(double left, double top, double width, double height,
          double radius, List<Color> colors,
          {double angle = 0}) =>
      Positioned(
        left: left,
        top: top,
        width: width,
        height: height,
        child: Transform.rotate(
            angle: angle,
            child: Container(
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: colors)),
            )),
      );
}
