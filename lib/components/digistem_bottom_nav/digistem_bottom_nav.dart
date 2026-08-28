import 'package:flutter/material.dart';

import '/flutter_flow/flutter_flow_theme.dart';

class DigiStemBottomNavItem {
  const DigiStemBottomNavItem({
    required this.icon,
    required this.label,
    this.id,
    this.selectedIcon,
    this.semanticLabel,
    this.selected = false,
  });

  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final String? id;
  final String? semanticLabel;
  final bool selected;
}

/// Edge-to-edge application shell matching the bottom dock used by DigiStem.
///
/// The system safe area is part of the dock surface, rather than padding around
/// it. This keeps the navigation attached to the bottom of edge-to-edge iOS and
/// Android screens.
class DigiStemBottomNav extends StatefulWidget {
  const DigiStemBottomNav({
    super.key,
    required this.body,
    required this.items,
    this.initialIndex = 0,
    this.onSelected,
  }) : assert(items.length >= 2, 'The bottom nav needs at least two tabs.');

  final Widget body;
  final List<DigiStemBottomNavItem> items;
  final int initialIndex;
  final ValueChanged<int>? onSelected;

  @override
  State<DigiStemBottomNav> createState() => _DigiStemBottomNavState();
}

class _DigiStemBottomNavState extends State<DigiStemBottomNav> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = _selectedIndex(widget.items) ??
        widget.initialIndex.clamp(0, widget.items.length - 1);
  }

  @override
  void didUpdateWidget(covariant DigiStemBottomNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedIndex = _selectedIndex(widget.items);
    if (selectedIndex != null) {
      _currentIndex = selectedIndex;
    } else if (oldWidget.items.length != widget.items.length) {
      _currentIndex = _currentIndex.clamp(0, widget.items.length - 1);
    }
  }

  int? _selectedIndex(List<DigiStemBottomNavItem> items) {
    final index = items.indexWhere((item) => item.selected);
    return index < 0 ? null : index;
  }

  void _selectItem(int index) {
    if (_currentIndex != index) {
      setState(() => _currentIndex = index);
    }
    widget.onSelected?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      body: widget.body,
      bottomNavigationBar: _BottomDock(
        items: widget.items,
        currentIndex: _currentIndex,
        onSelected: _selectItem,
        backgroundColor: theme.primaryBackground,
        selectedColor: theme.primary,
        selectedGradientColor: Theme.of(context).brightness == Brightness.dark
            ? theme.primary
            : theme.tertiary,
        unselectedColor: theme.secondaryText,
      ),
    );
  }
}

class _BottomDock extends StatelessWidget {
  const _BottomDock({
    required this.items,
    required this.currentIndex,
    required this.onSelected,
    required this.backgroundColor,
    required this.selectedColor,
    required this.selectedGradientColor,
    required this.unselectedColor,
  });

  static const double _navigationHeight = 76;

  final List<DigiStemBottomNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelected;
  final Color backgroundColor;
  final Color selectedColor;
  final Color selectedGradientColor;
  final Color unselectedColor;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return ColoredBox(
      color: backgroundColor,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SizedBox(
          height: _navigationHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth / items.length;

              return Stack(
                children: [
                  Positioned.fill(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(end: currentIndex.toDouble()),
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      builder: (context, animatedIndex, _) {
                        return IgnorePointer(
                          child: CustomPaint(
                            painter: _SelectedTopGradientPainter(
                              centerX: itemWidth * (animatedIndex + 0.45),
                              horizontalRadius: itemWidth,
                              primaryColor: selectedColor,
                              secondaryColor: selectedGradientColor,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: Container(
                      height: 1,
                      color: selectedGradientColor.withValues(alpha: 0.08),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: List.generate(items.length, (index) {
                      return Expanded(
                        child: _BottomDockItem(
                          item: items[index],
                          selected: currentIndex == index,
                          selectedColor: selectedColor,
                          unselectedColor: unselectedColor,
                          onTap: () => onSelected(index),
                        ),
                      );
                    }),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SelectedTopGradientPainter extends CustomPainter {
  const _SelectedTopGradientPainter({
    required this.centerX,
    required this.horizontalRadius,
    required this.primaryColor,
    required this.secondaryColor,
  });

  final double centerX;
  final double horizontalRadius;
  final Color primaryColor;
  final Color secondaryColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(centerX, 0);
    final glowRect = Rect.fromLTWH(
      centerX - horizontalRadius,
      0,
      horizontalRadius * 2,
      48,
    );

    canvas.saveLayer(glowRect, Paint());

    final verticalGlowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          secondaryColor.withValues(alpha: 0.28),
          primaryColor.withValues(alpha: 0.12),
          primaryColor.withValues(alpha: 0),
        ],
        stops: const [0, 0.48, 1],
      ).createShader(glowRect);
    canvas.drawRect(glowRect, verticalGlowPaint);

    final horizontalMaskPaint = Paint()
      ..blendMode = BlendMode.dstIn
      ..shader = const LinearGradient(
        colors: [Colors.transparent, Colors.white, Colors.transparent],
        stops: [0, 0.5, 1],
      ).createShader(glowRect);
    canvas.drawRect(glowRect, horizontalMaskPaint);
    canvas.restore();

    final beamPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          primaryColor.withValues(alpha: 0),
          secondaryColor.withValues(alpha: 0.9),
          primaryColor.withValues(alpha: 0),
        ],
        stops: const [0, 0.5, 1],
      ).createShader(
        Rect.fromLTWH(
          center.dx - horizontalRadius,
          0,
          horizontalRadius * 2,
          2,
        ),
      );
    canvas.drawRect(
      Rect.fromLTWH(
        center.dx - horizontalRadius,
        0,
        horizontalRadius * 2,
        2,
      ),
      beamPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SelectedTopGradientPainter oldDelegate) {
    return oldDelegate.centerX != centerX ||
        oldDelegate.horizontalRadius != horizontalRadius ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.secondaryColor != secondaryColor;
  }
}

class _BottomDockItem extends StatelessWidget {
  const _BottomDockItem({
    required this.item,
    required this.selected,
    required this.selectedColor,
    required this.unselectedColor,
    required this.onTap,
  });

  final DigiStemBottomNavItem item;
  final bool selected;
  final Color selectedColor;
  final Color unselectedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Semantics(
      button: true,
      selected: selected,
      label: item.semanticLabel ?? item.label,
      child: InkResponse(
        onTap: onTap,
        containedInkWell: true,
        highlightShape: BoxShape.rectangle,
        splashColor: selectedColor.withValues(alpha: 0.14),
        highlightColor: selectedColor.withValues(alpha: 0.07),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 9, 4, 5),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: selected ? 1 : 0),
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOutCubic,
            builder: (context, selectionProgress, _) {
              final color = Color.lerp(
                unselectedColor,
                selectedColor,
                selectionProgress,
              )!;
              final fontWeight = FontWeight.lerp(
                    FontWeight.w400,
                    FontWeight.w600,
                    selectionProgress,
                  ) ??
                  FontWeight.w400;

              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: item.selectedIcon == null ||
                            item.selectedIcon == item.icon
                        ? Icon(
                            item.icon,
                            color: color,
                            size: 24 + (selectionProgress * 6),
                          )
                        : Stack(
                            alignment: Alignment.center,
                            children: [
                              Opacity(
                                opacity: 1 - selectionProgress,
                                child: Transform.scale(
                                  scale: 1 - (selectionProgress * 0.08),
                                  child: Icon(
                                    item.icon,
                                    color: color,
                                    size: 24,
                                  ),
                                ),
                              ),
                              Opacity(
                                opacity: selectionProgress,
                                child: Transform.scale(
                                  scale: 0.82 + (selectionProgress * 0.18),
                                  child: Icon(
                                    item.selectedIcon!,
                                    color: color,
                                    size: 30,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 3),
                  Transform.scale(
                    scale: 0.98 + (selectionProgress * 0.02),
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: theme.bodySmall.override(
                        fontFamily: theme.bodySmallFamily,
                        color: color,
                        fontSize: 12,
                        lineHeight: 1,
                        fontWeight: fontWeight,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
