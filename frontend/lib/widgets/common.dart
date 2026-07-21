import 'package:flutter/material.dart';
import '../app_theme.dart';

/// Big pill CTA button with a gradient background (purple by default).
class GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final double height;

  const GradientButton({
    super.key,
    required this.label,
    required this.onTap,
    this.gradient,
    this.height = 54,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final effectiveGradient = gradient ?? AppColors.purpleGradient;
    return SizedBox(
      width: double.infinity,
      height: height,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: disabled ? null : effectiveGradient,
              color: disabled ? Colors.white.withOpacity(.07) : null,
              boxShadow: disabled
                  ? null
                  : [
                      BoxShadow(
                        color: AppColors.purple1.withOpacity(.3),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
            ),
            child: Text(
              label,
              style: AppText.heading(
                size: 15,
                color: disabled ? AppColors.textTertiary : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Outlined pill button, used for secondary actions ("ย้อนกลับ" etc.)
class OutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const OutlineButton({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(label, style: AppText.heading(size: 14.5)),
          ),
        ),
      ),
    );
  }
}

/// Soft translucent card container, base building block for most sections.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? borderColor;
  final Gradient? backgroundGradient;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderColor,
    this.backgroundGradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundGradient == null ? AppColors.card : null,
        gradient: backgroundGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor ?? AppColors.border),
      ),
      child: child,
    );
  }
}

/// Small heading row used above most sections, e.g. "แผนการฝึกของคุณ".
class SectionLabel extends StatelessWidget {
  final String title;
  final String? hint;
  const SectionLabel({super.key, required this.title, this.hint});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 26, bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: AppText.heading(size: 15)),
          if (hint != null)
            Text(hint!, style: AppText.body(size: 11.5, color: AppColors.textTertiary)),
        ],
      ),
    );
  }
}

/// Rounded selectable chip, e.g. week-length picker, gender picker.
class SelectChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const SelectChip({super.key, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: active ? AppColors.purpleGradient : null,
          color: active ? null : Colors.white.withOpacity(.03),
          border: Border.all(color: active ? Colors.transparent : AppColors.border),
        ),
        child: Text(
          label,
          style: AppText.body(
            size: 13.5,
            weight: FontWeight.w500,
            color: active ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Circular back / icon button used in top bars.
class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const RoundIconButton({super.key, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap ?? () => Navigator.maybePop(context),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, size: 18, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

/// Small on/off switch styled to match the gold "Threshold" toggle in mocks.
class AppSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const AppSwitch({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 42,
        height: 24,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: value ? AppColors.goldGradient : null,
          color: value ? null : Colors.white.withOpacity(.08),
          border: Border.all(color: value ? Colors.transparent : AppColors.border),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 150),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 18,
            height: 18,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Dark, rounded text field matching the login/register/onboarding inputs.
class AppTextField extends StatelessWidget {
  final String label;
  final String? hint;
  final bool obscure;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;

  const AppTextField({
    super.key,
    required this.label,
    this.hint,
    this.obscure = false,
    this.controller,
    this.onChanged,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: AppText.body(size: 11.5, color: AppColors.textSecondary, weight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.03),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboardType,
            onChanged: onChanged,
            style: AppText.body(size: 14.5),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: AppText.body(size: 14, color: AppColors.textTertiary),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
          ),
        ),
      ],
    );
  }
}

/// Small logo mark used on Login/Register — a stylised wing badge since no
/// image asset was supplied, in the same gold as the original artwork.
class PacegasusLogo extends StatelessWidget {
  final double size;
  const PacegasusLogo({super.key, this.size = 64});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.goldGradient,
        boxShadow: [BoxShadow(color: AppColors.gold1.withOpacity(.35), blurRadius: 26, spreadRadius: 2)],
      ),
      child: Icon(Icons.bolt_rounded, color: AppColors.bg1, size: size * .55),
    );
  }
}

/// Top progress bar for the onboarding flow (N segments, first [active]
/// are filled).
class OnboardingProgress extends StatelessWidget {
  final int steps;
  final int active;
  const OnboardingProgress({super.key, required this.steps, required this.active});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(steps, (i) {
        final filled = i < active;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i == steps - 1 ? 0 : 6),
            height: 4,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: filled ? AppColors.purpleGradient : null,
              color: filled ? null : Colors.white.withOpacity(.08),
            ),
          ),
        );
      }),
    );
  }
}

/// Multi-select pill used for conditions/injuries lists.
class MultiChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const MultiChip({super.key, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: selected ? AppColors.purpleGradient : null,
          color: selected ? null : Colors.white.withOpacity(.03),
          border: Border.all(color: selected ? Colors.transparent : AppColors.border),
        ),
        child: Text(label,
            style: AppText.body(
                size: 13.5, weight: FontWeight.w500, color: selected ? Colors.white : AppColors.textSecondary)),
      ),
    );
  }
}

/// Labeled slider row used on Wellness check-in / run-summary screens,
/// e.g. "คุณภาพการนอน  7" with "แย่มาก" / "ดีมาก" captions underneath.
class LabeledSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String minCaption;
  final String maxCaption;
  final ValueChanged<double> onChanged;
  final String Function(double)? valueFormatter;

  const LabeledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.minCaption,
    required this.maxCaption,
    required this.onChanged,
    this.divisions,
    this.valueFormatter,
  });

  @override
  Widget build(BuildContext context) {
    final display = valueFormatter != null ? valueFormatter!(value) : value.round().toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AppText.body(size: 13.5, weight: FontWeight.w600)),
            Container(
              width: 34,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.purple1.withOpacity(.18),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(display, style: AppText.heading(size: 12.5, color: AppColors.purple2)),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            activeTrackColor: AppColors.purple1,
            inactiveTrackColor: Colors.white.withOpacity(.08),
            thumbColor: Colors.white,
            overlayColor: AppColors.purple1.withOpacity(.15),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
          ),
          child: Slider(value: value, min: min, max: max, divisions: divisions, onChanged: onChanged),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(minCaption, style: AppText.body(size: 11, color: AppColors.textTertiary)),
            Text(maxCaption, style: AppText.body(size: 11, color: AppColors.textTertiary)),
          ],
        ),
      ],
    );
  }
}

/// Circular arrow button for prev/next navigation, where passing `null`
/// truly disables it (unlike [RoundIconButton], which falls back to
/// popping the screen — appropriate for back buttons, not nav arrows).
class NavArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const NavArrowButton({super.key, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(21),
        side: BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(21),
        onTap: onTap,
        child: Opacity(
          opacity: disabled ? .35 : 1,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, size: 20, color: AppColors.textPrimary),
          ),
        ),
      ),
    );
  }
}

/// Shows a small pill toast at the bottom of the screen (used for schedule
/// rule violations etc.) instead of a default SnackBar.
void showAppToast(BuildContext context, String message, {bool isError = true}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Positioned(
      left: 24,
      right: 24,
      bottom: 110,
      child: Material(
        color: Colors.transparent,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1533),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: isError ? AppColors.red1.withOpacity(.4) : AppColors.green1.withOpacity(.4),
              ),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(.4), blurRadius: 20, offset: const Offset(0, 10))],
            ),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: AppText.body(size: 12.5, weight: FontWeight.w500, color: Colors.white),
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  Future.delayed(const Duration(milliseconds: 2200), () => entry.remove());
}
