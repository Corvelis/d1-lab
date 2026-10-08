import 'package:flutter/material.dart';
import 'l10n/strings.dart';

const ink = Color(0xff172c2b);
const teal = Color(0xff237a68);
const mint = Color(0xffbde6c8);
const canvas = Color(0xfff3f5f0);
const muted = Color(0xff71817b);
const line = Color(0xffe2e8df);

ThemeData labTheme() => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: teal,
    primary: teal,
    secondary: ink,
    surface: canvas,
  ),
  scaffoldBackgroundColor: canvas,
  textTheme: TextTheme(
    headlineMedium: TextStyle(
      color: ink,
      fontSize: 28,
      fontWeight: FontWeight.w700,
      letterSpacing: -1,
    ),
    headlineSmall: TextStyle(
      color: ink,
      fontSize: 24,
      fontWeight: FontWeight.w700,
      letterSpacing: -.6,
    ),
    titleLarge: TextStyle(
      color: ink,
      fontSize: 21,
      fontWeight: FontWeight.w700,
    ),
    titleMedium: TextStyle(
      color: ink,
      fontSize: 16,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: TextStyle(color: ink, fontSize: 15, height: 1.5),
    bodyMedium: TextStyle(color: ink, fontSize: 13, height: 1.5),
    bodySmall: TextStyle(color: muted, fontSize: 11, height: 1.5),
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: canvas,
    foregroundColor: ink,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
  ),
  cardTheme: CardThemeData(
    color: Colors.white,
    elevation: 0,
    margin: EdgeInsets.only(bottom: 14),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: BorderSide(color: line),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Color(0xfff6f8f4),
    contentPadding: EdgeInsets.all(16),
    labelStyle: TextStyle(color: muted, fontSize: 13),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: teal, width: 1.5),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: ink,
      foregroundColor: Colors.white,
      minimumSize: Size(0, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: ink,
      side: BorderSide(color: line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  chipTheme: ChipThemeData(
    backgroundColor: canvas,
    side: BorderSide.none,
    labelStyle: TextStyle(color: ink, fontSize: 11),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  ),
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: Colors.white,
    indicatorColor: mint,
    height: 68,
    labelTextStyle: WidgetStateProperty.resolveWith(
      (s) => TextStyle(
        fontSize: 11,
        fontWeight: s.contains(WidgetState.selected)
            ? FontWeight.w700
            : FontWeight.w500,
        color: ink,
      ),
    ),
  ),
  dividerTheme: DividerThemeData(color: line, thickness: 1),
  progressIndicatorTheme: ProgressIndicatorThemeData(
    color: teal,
    linearTrackColor: line,
  ),
);

class LabBadge extends StatelessWidget {
  const LabBadge(this.text, {super.key, this.icon, this.dark = false});
  final String text;
  final IconData? icon;
  final bool dark;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: dark ? Colors.white.withValues(alpha: .1) : Color(0xffeaf3e9),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: dark ? mint : teal),
          SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: .3,
              color: dark ? mint : teal,
            ),
          ),
        ),
      ],
    ),
  );
}

class LabHero extends StatelessWidget {
  const LabHero({super.key});
  @override
  Widget build(BuildContext context) => Container(
    margin: EdgeInsets.only(bottom: 22),
    padding: EdgeInsets.all(24),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xff183c35), ink],
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            LabBadge('ON-DEVICE', icon: Icons.radio_button_checked, dark: true),
            Spacer(),
            Icon(Icons.auto_awesome_outlined, color: mint, size: 25),
          ],
        ),
        SizedBox(height: 20),
        Text(
          context.strings.text("判断を、\n手のひらで。"),
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            height: 1.3,
            fontWeight: FontWeight.w700,
            letterSpacing: -.8,
          ),
        ),
        SizedBox(height: 10),
        Text(
          context.strings.text("条件を変えて、確率と速さを確かめる。"),
          style: TextStyle(
            color: Colors.white.withValues(alpha: .65),
            fontSize: 12,
          ),
        ),
        SizedBox(height: 20),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            _HeroFeature(Icons.notes_rounded, context.strings.text("テキスト")),
            _HeroFeature(Icons.image_outlined, context.strings.text("画像")),
            _HeroFeature(Icons.graphic_eq, context.strings.text("音声")),
          ],
        ),
      ],
    ),
  );
}

class _HeroFeature extends StatelessWidget {
  const _HeroFeature(this.icon, this.label);
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: mint, size: 16),
      SizedBox(width: 5),
      Text(label, style: TextStyle(color: mint, fontSize: 11)),
    ],
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.title, {super.key, this.caption});
  final String title;
  final String? caption;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: 12),
    child: Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          title,
          style: TextStyle(
            color: ink,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        if (caption != null)
          Text(caption!, style: TextStyle(color: muted, fontSize: 11)),
      ],
    ),
  );
}

class ChoiceControl extends StatelessWidget {
  const ChoiceControl({
    super.key,
    required this.options,
    required this.selected,
    this.onChanged,
  });
  final Map<String, String> options;
  final String selected;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: canvas,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        for (final option in options.entries)
          Expanded(
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: selected == option.key
                    ? mint
                    : Colors.transparent,
                foregroundColor: ink,
                minimumSize: Size.zero,
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: onChanged == null
                  ? null
                  : () => onChanged!(option.key),
              child: Text(
                option.value,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
      ],
    ),
  );
}
