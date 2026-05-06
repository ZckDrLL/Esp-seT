// lib/widgets/miui_explosion.dart
import 'dart:math';
import 'package:flutter/material.dart';

/// Небольшая "MIUI-like" анимация удаления: множество круглых частиц,
/// которые разлетаются из центра и исчезают.
/// Вызывается автоматически при создании виджета; вызывает onCompleted по окончании.
class MiuiExplosion extends StatefulWidget {
  final Color color;
  final Duration duration;
  final double size; // размер контейнера (высота)
  final VoidCallback? onCompleted;

  const MiuiExplosion({
    super.key,
    this.color = const Color(0xFF32E3FE),
    this.duration = const Duration(milliseconds: 600),
    this.size = 48.0,
    this.onCompleted,
  });

  @override
  State<MiuiExplosion> createState() => _MiuiExplosionState();
}

class _MiuiExplosionState extends State<MiuiExplosion> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  final Random _rnd = Random();
  final int _particles = 14;
  late final List<Offset> _dirs;

  @override
  void initState() {
    super.initState();
    _dirs = List.generate(_particles, (_) {
      final angle = _rnd.nextDouble() * pi * 2;
      final radius = 26 + _rnd.nextDouble() * 48; // разброс дальности
      return Offset(cos(angle) * radius, sin(angle) * radius);
    });

    _ctrl = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          widget.onCompleted?.call();
        }
      })
      ..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.size,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = Curves.easeOut.transform(_ctrl.value);
          return Stack(
            alignment: Alignment.centerLeft, // использую left-alignment чтобы занимать ширину
            children: List.generate(_particles, (i) {
              final dx = _dirs[i].dx * t;
              final dy = _dirs[i].dy * t;
              final opacity = (1.0 - _ctrl.value).clamp(0.0, 1.0);
              final scale = 0.6 + (1.0 - _ctrl.value) * 0.8;
              // небольшая вариативность размеров
              final partSize = 6.0 + (i % 3) * 2.5;
              return Transform.translate(
                offset: Offset(dx, dy),
                child: Opacity(
                  opacity: opacity,
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: partSize,
                      height: partSize,
                      decoration: BoxDecoration(
                        color: widget.color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: widget.color.withAlpha(64),
                            blurRadius: 4,
                            spreadRadius: 0.5,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
