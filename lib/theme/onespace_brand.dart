import 'package:material_ui/material_ui.dart';

/// OneSpace's shared brand lockup. Keep the mark, name and tagline identical
/// on sign-in, startup and future marketing-facing app surfaces.
class OneSpaceBrand extends StatelessWidget {
  const OneSpaceBrand({super.key, this.logoSize = 82, this.nameSize = 32});

  final double logoSize;
  final double nameSize;

  static const tagline = 'Two of Us. One Space.';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final navy = isDark ? const Color(0xFFF5F7FB) : const Color(0xFF14213D);
    final slate = isDark ? const Color(0xFFCCD5E3) : const Color(0xFF51657A);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/branding/mark.png',
          width: logoSize,
          height: logoSize,
          semanticLabel: 'OneSpace logo',
        ),
        const SizedBox(height: 9),
        Text(
          'OneSpace',
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            color: navy,
            fontSize: nameSize,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
            height: 1.12,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          tagline,
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontSize: nameSize >= 32 ? 13 : 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.15,
            height: 1.35,
            color: slate,
          ),
        ),
      ],
    );
  }
}
