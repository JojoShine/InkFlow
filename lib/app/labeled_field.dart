import 'package:flutter/material.dart';
import '../features/appearance/theme_presets.dart';

class LabeledField extends StatelessWidget {
  const LabeledField({super.key, required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ExcludeSemantics(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            height: 1.4,
            color: InkPalette.of(context).ink,
          ),
        ),
      ),
      const SizedBox(height: 12),
      Semantics(label: label, child: child),
    ],
  );
}
