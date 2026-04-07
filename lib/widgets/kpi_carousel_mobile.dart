import 'package:flutter/material.dart';

class KpiCarouselMobile extends StatefulWidget {
  final List<Widget> kpiCards;
  final List<Widget> chartCards;
  final Widget actionBadges;
  final double height;
  const KpiCarouselMobile({
    super.key,
    required this.kpiCards,
    required this.chartCards,
    required this.actionBadges,
    this.height = 136.0,
  });

  @override
  State<KpiCarouselMobile> createState() => _KpiCarouselMobileState();
}

class _KpiCarouselMobileState extends State<KpiCarouselMobile> {
  late final PageController _ctrl;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = PageController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  int get _kpiPages => (widget.kpiCards.length / 2).ceil();
  int get _totalPages => _kpiPages + widget.chartCards.length;

  Widget _buildPage(int pageIndex) {
    if (pageIndex < _kpiPages) {
      final i = pageIndex * 2;
      final first = widget.kpiCards[i];
      final second = i + 1 < widget.kpiCards.length
          ? widget.kpiCards[i + 1]
          : null;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: first),
          const SizedBox(width: 10),
          Expanded(child: second ?? const SizedBox()),
        ],
      );
    } else {
      return widget.chartCards[pageIndex - _kpiPages];
    }
  }

  void _goTo(int page) {
    _ctrl.animateToPage(
      page,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
    );
  }

  Widget _buildNavArrow({
    required bool isLeft,
    required VoidCallback onTap,
    required Color color,
  }) {
    return Positioned(
      left: isLeft ? 0 : null,
      right: isLeft ? null : 0,
      top: 0,
      bottom: 0,
      child: Center(
        child: Container(
          margin: EdgeInsets.only(left: isLeft ? 4 : 0, right: isLeft ? 0 : 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha:0.10),
                blurRadius: 6,
              ),
            ],
          ),
          child: Material(
            color: Colors.white.withValues(alpha:0.92),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: IconButton(
              onPressed: onTap,
              icon: Icon(isLeft
                  ? Icons.chevron_left_rounded
                  : Icons.chevron_right_rounded),
              iconSize: 20,
              color: color,
              padding: const EdgeInsets.all(5),
              constraints: const BoxConstraints(),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final total = _totalPages;
    return Column(
      children: [
        SizedBox(
          height: widget.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              PageView.builder(
                controller: _ctrl,
                itemCount: total,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
                  child: _buildPage(i),
                ),
              ),
              if (_page > 0)
                _buildNavArrow(
                  isLeft: true,
                  onTap: () => _goTo(_page - 1),
                  color: primaryColor,
                ),
              if (_page < total - 1)
                _buildNavArrow(
                  isLeft: false,
                  onTap: () => _goTo(_page + 1),
                  color: primaryColor,
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _buildIndicators(total, primaryColor),
        const SizedBox(height: 8),
        widget.actionBadges,
      ],
    );
  }

  Widget _buildIndicators(int total, Color primaryColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        total,
        (i) => AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: i == _page ? 16 : 6,
          height: 5,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: i == _page ? primaryColor : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}