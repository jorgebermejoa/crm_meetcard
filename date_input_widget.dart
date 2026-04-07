import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';

/// Un widget de campo de formulario para seleccionar una fecha con un calendario.
class DateInputWidget extends StatelessWidget {
  final String label;
  final DateTime? value;
  final void Function(DateTime?) onDateSelected;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final String hint;

  const DateInputWidget({
    super.key,
    required this.label,
    required this.value,
    required this.onDateSelected,
    this.firstDate,
    this.lastDate,
    this.hint = 'No establecida',
  });

  @override
  Widget build(BuildContext context) {
    final displayFormat = DateFormat('dd/MM/yyyy');
    final text = value != null ? displayFormat.format(value!) : hint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            final selectedDate = await showDatePicker(
              context: context,
              initialDate: value ?? DateTime.now(),
              firstDate: firstDate ?? DateTime(2010),
              lastDate: lastDate ?? DateTime(2040),
              locale: const Locale('es', 'ES'),
              builder: (context, child) {
                return Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: const ColorScheme.light(
                      primary: AppColors.primary,
                      onPrimary: Colors.white,
                      onSurface: AppColors.textPrimary,
                    ),
                    textButtonTheme: TextButtonThemeData(
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                      ),
                    ),
                  ),
                  child: child!,
                );
              },
            );
            if (selectedDate != null) {
              onDateSelected(selectedDate);
            }
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE5E7EB)),
              borderRadius: BorderRadius.circular(10),
              color: const Color(0xFFFAFAFA),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.textMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: value != null ? AppColors.textPrimary : AppColors.textMuted,
                    ),
                  ),
                ),
                if (value != null)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => onDateSelected(null),
                      borderRadius: BorderRadius.circular(30),
                      child: const Padding(
                        padding: EdgeInsets.all(4.0),
                        child: Icon(Icons.close, size: 18, color: AppColors.textMuted),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}