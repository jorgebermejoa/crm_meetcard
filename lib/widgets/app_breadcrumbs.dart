import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const _primaryColor = Color(0xFF5B21B6);
const _bgColor = Color(0xFFF2F2F7);

class BreadcrumbItem {
  final String label;
  final VoidCallback? onTap;
  const BreadcrumbItem(this.label, {this.onTap});
}

/// AppBar estandarizado con breadcrumbs + menú hamburguesa (siempre izquierda).
/// Úsalo como el `appBar` de un Scaffold o dentro de una Column manual.
PreferredSizeWidget buildBreadcrumbAppBar({
  required BuildContext context,
  required List<BreadcrumbItem> crumbs,
  VoidCallback? onOpenMenu,
  List<Widget> actions = const [],
  double maxWidth = 880,
  double hPad = 20,
}) {
  return AppBar(
    backgroundColor: _bgColor,
    elevation: 0,
    automaticallyImplyLeading: false,
    titleSpacing: 0,
    actions: actions.isEmpty ? const [] : [...actions, SizedBox(width: hPad - 8)],
    title: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: hPad - 8),
          child: Row(children: [
            // Hamburger siempre a la izquierda
            if (onOpenMenu != null) ...[
              IconButton(
                icon: const Icon(Icons.menu, color: Color(0xFF1E293B), size: 22),
                onPressed: onOpenMenu,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Menú',
              ),
              const SizedBox(width: 10),
            ],
            // Breadcrumbs
            Expanded(child: _BreadcrumbRow(crumbs: crumbs)),
          ]),
        ),
      ),
    ),
  );
}

class _BreadcrumbRow extends StatelessWidget {
  final List<BreadcrumbItem> crumbs;
  const _BreadcrumbRow({required this.crumbs});

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (int i = 0; i < crumbs.length; i++) {
      final c = crumbs[i];
      final isLast = i == crumbs.length - 1;

      items.add(_CrumbChip(label: c.label, isLast: isLast, onTap: c.onTap));
      if (!isLast) {
        items.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade400),
        ));
      }
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: items,
    );
  }
}

class _CrumbChip extends StatelessWidget {
  final String label;
  final bool isLast;
  final VoidCallback? onTap;

  const _CrumbChip({required this.label, required this.isLast, this.onTap});

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.inter(
      fontSize: 13,
      fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
      color: isLast ? _primaryColor : const Color(0xFF64748B),
    );

    final text = Text(label, style: style, overflow: TextOverflow.ellipsis);

    if (!isLast && onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: text,
        ),
      );
    }
    return Flexible(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: text,
      ),
    );
  }
}
