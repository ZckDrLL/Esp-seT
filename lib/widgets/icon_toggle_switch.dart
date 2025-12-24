// lib/widgets/icon_toggle_switch.dart
import 'package:flutter/material.dart';

/// Controlled switch with icon inside thumb (check / cross).
/// IMPORTANT: this widget is controlled — it does NOT mutate internal state.
/// Parent must pass the current `value` and react to `onChanged` by updating it
/// (for example, after user confirmation).
class IconToggleSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  // sizing
  final double width;
  final double height;
  final Duration duration;

  // colors
  final Color activeTrackColor;
  final Color inactiveTrackColor;
  final Color activeThumbInner;
  final Color inactiveThumbInner;
  final Color thumbBorderColorOn;
  final Color thumbBorderColorOff;
  final Color iconColorOn;
  final Color iconColorOff;

const IconToggleSwitch({
  super.key,
  required this.value,
  required this.onChanged,
  this.width = 72,
  this.height = 38,
  this.duration = const Duration(milliseconds: 220),
  this.activeTrackColor = const Color(0xFFD9F1FF),
  this.inactiveTrackColor = const Color(0xFF2F3437),
  this.activeThumbInner = const Color(0xFF123A52),
  this.inactiveThumbInner = const Color(0xFF2F3437),
  this.thumbBorderColorOn = const Color(0xFF274B62),
  this.thumbBorderColorOff = const Color(0xFF9EA3A6),
  this.iconColorOn = Colors.white,
  this.iconColorOff = Colors.white,
});

  @override
  Widget build(BuildContext context) {
    final w = width;
    final h = height;
    final thumbDiameter = h * 0.85; // slightly smaller than height
    final horizontalPadding = (h - thumbDiameter) / 2;

    return GestureDetector(
      onTap: () {
        // do NOT update internal state here — just notify parent
        onChanged(!value);
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: duration,
        width: w,
        height: h,
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        decoration: BoxDecoration(
          color: value ? activeTrackColor : inactiveTrackColor,
          borderRadius: BorderRadius.circular(h / 2),
        ),
        // Use AnimatedAlign so thumb moves only when 'value' actually changes (i.e. parent updated it)
        child: Stack(
          clipBehavior: Clip.none, // ensure thumb shadow/outline not clipped
          children: [
            AnimatedAlign(
              duration: duration,
              curve: Curves.easeOut,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: thumbDiameter,
                height: thumbDiameter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: value ? activeThumbInner : inactiveThumbInner,
                  border: Border.all(
                    color: value ? thumbBorderColorOn : thumbBorderColorOff,
                    width: 3.0,
                  ),
                ),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: duration,
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeIn,
                    child: value
                        ? Icon(Icons.check, key: const ValueKey('on'), size: thumbDiameter * 0.5, color: iconColorOn)
                        : Icon(Icons.close, key: const ValueKey('off'), size: thumbDiameter * 0.5, color: iconColorOff),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
