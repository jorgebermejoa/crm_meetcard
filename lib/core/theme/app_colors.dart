import 'package:flutter/material.dart';

/// Tokens de color centralizados para toda la app.
/// Usar siempre estos en lugar de hardcodear Color(0xFF...).
class AppColors {
  // ── Brand / Primary ──────────────────────────────────────────────────────
  static const Color primary        = Color(0xFF007AFF); // iOS Blue
  static const Color primaryDark    = Color(0xFF0056B3);
  static const Color primaryLight   = Color(0xFF5AC8FA);
  static const Color primaryMuted   = Color(0xFF0EA5E9); // Sky-500

  // ── Texto ─────────────────────────────────────────────────────────────────
  static const Color textPrimary    = Color(0xFF1E293B); // Slate-800
  static const Color textBody       = Color(0xFF334155); // Slate-700
  static const Color textSecondary  = Color(0xFF475569); // Slate-600
  static const Color textMuted      = Color(0xFF64748B); // Slate-500
  static const Color textFaint      = Color(0xFF94A3B8); // Slate-400
  static const Color textApple      = Color(0xFF1D1D1F); // Apple dark

  // ── Fondos ────────────────────────────────────────────────────────────────
  static const Color background     = Color(0xFFF2F2F7); // iOS System bg
  static const Color scaffoldBackground = Color(0xFFF2F2F7);
  static const Color surface        = Colors.white;
  static const Color surfaceAlt     = Color(0xFFF8FAFC); // Slate-50
  static const Color surfaceSubtle  = Color(0xFFF1F5F9); // Slate-100

  // ── Bordes / Divisores ────────────────────────────────────────────────────
  static const Color border         = Color(0xFFE2E8F0); // Slate-200
  static const Color borderLight    = Color(0xFFE5E7EB); // Gray-200
  static const Color divider        = Color(0xFFF1F5F9);
  static const Color borderApple    = Color(0xFFD1D1D6);

  // ── Semánticos ────────────────────────────────────────────────────────────
  static const Color success        = Color(0xFF10B981); // Emerald-500
  static const Color successDark    = Color(0xFF059669); // Emerald-600
  static const Color successDeep    = Color(0xFF16A34A); // Green-600
  static const Color successSurface = Color(0xFFF0FDF4); // Green-50

  static const Color warning        = Color(0xFFF59E0B); // Amber-500
  static const Color warningDark    = Color(0xFFD97706); // Amber-600
  static const Color warningSurface = Color(0xFFFFF7ED); // Orange-50

  static const Color error          = Color(0xFFEF4444); // Red-500
  static const Color errorDark      = Color(0xFFDC2626); // Red-600
  static const Color errorSurface   = Color(0xFFFEF2F2); // Red-50

  // ── Acentos ───────────────────────────────────────────────────────────────
  static const Color indigo         = Color(0xFF6366F1); // Indigo-500
  static const Color violet         = Color(0xFF5B21B6); // Violet-800
  static const Color gray500        = Color(0xFF6B7280); // Gray-500
  static const Color gray700        = Color(0xFF374151); // Gray-700
  static const Color systemGray     = Color(0xFF8E8E93); // Apple System Gray
  static const Color blue500        = Color(0xFF3B82F6); // Blue-500
  static const Color blueSurface    = Color(0xFFEFF6FF); // Blue-50
}
