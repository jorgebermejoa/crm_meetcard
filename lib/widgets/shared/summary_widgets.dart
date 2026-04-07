import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SummaryChip extends StatelessWidget {
  final String label;
  final Color? dotColor;
  final Color textColor;

  const SummaryChip(this.label, this.dotColor, this.textColor, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (dotColor != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class HorizontalDivider extends StatelessWidget {
  const HorizontalDivider({super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Container(width: 1, height: 16, color: Colors.grey.shade200),
      );
}