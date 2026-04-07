import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class KpiCardShell extends StatefulWidget {
  final String label;
  final Color color;
  final Widget icon;
  final Widget value;
  final int pageCount;
  final int currentIndex;
  final void Function(bool forward) onSwipe;
  final VoidCallback? onTap;

  const KpiCardShell({
    super.key,
    required this.label,
    required this.color,
    required this.icon,
    required this.value,
    required this.pageCount,
    required this.currentIndex,
    required this.onSwipe,
    this.onTap,
  });

  @override
  State<KpiCardShell> createState() => _KpiCardShellState();
}

class _KpiCardShellState extends State<KpiCardShell>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  late AnimationController _iconCtrl;
  late Animation<double> _iconScale;
  late Animation<double> _iconOpacity;

  @override
  void initState() {
    super.initState();
    _iconCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _iconScale = Tween<double>(
      begin: 0.72,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _iconCtrl, curve: Curves.easeOut));
    _iconOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _iconCtrl,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
      ),
    );
    _iconCtrl.value = 1.0; // start fully visible, no animation on first build
  }

  @override
  void didUpdateWidget(KpiCardShell old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      _iconCtrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _iconCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canTap = widget.onTap != null;
    return MouseRegion(
      cursor: canTap ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) {
        if (canTap) setState(() => _hovered = true);
      },
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onHorizontalDragEnd: (d) {
          if (d.primaryVelocity == null) return;
          widget.onSwipe(d.primaryVelocity! < 0);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade100, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      widget.label,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                    ),
                  ),
                  FadeTransition(
                    opacity: _iconOpacity,
                    child: ScaleTransition(
                      scale: _iconScale,
                      child: widget.icon,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              widget.value,
              const SizedBox(height: 8),
              // Bottom row: dots (left) + Apple-style arrow (right, hover only)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onSwipe(true),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: ClipRect(
                          child: Row(
                            children: List.generate(
                              widget.pageCount,
                              (i) => AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: i == widget.currentIndex ? 12 : 5,
                                height: 4,
                                margin: const EdgeInsets.only(right: 4),
                                decoration: BoxDecoration(
                                  color: i == widget.currentIndex
                                      ? widget.color
                                      : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Apple-style chevron — only when tappable and hovered
                      if (canTap)
                        AnimatedOpacity(
                          opacity: _hovered ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 180),
                          child: AnimatedSlide(
                            offset: _hovered
                                ? Offset.zero
                                : const Offset(0.3, 0),
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.chevron_right_rounded,
                                size: 14,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}