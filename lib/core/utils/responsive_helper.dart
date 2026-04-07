import 'package:flutter/material.dart';

enum DeviceType { mobile, tablet, desktop }

class ResponsiveHelper {
  // Breakpoints
  static const double mobileBreakpoint = 600.0;
  static const double tabletBreakpoint = 1200.0;

  static DeviceType getDeviceType(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    if (width < mobileBreakpoint) return DeviceType.mobile;
    if (width < tabletBreakpoint) return DeviceType.tablet;
    return DeviceType.desktop;
  }

  static bool isMobile(BuildContext context) =>
      getDeviceType(context) == DeviceType.mobile;

  static bool isTablet(BuildContext context) =>
      getDeviceType(context) == DeviceType.tablet;

  static bool isDesktop(BuildContext context) =>
      getDeviceType(context) == DeviceType.desktop;

  // Responsive Width/Height
  static double getResponsiveWidth(BuildContext context, double percentage) {
    return MediaQuery.of(context).size.width * (percentage / 100);
  }

  // Scaling factors for modern typography
  static double getResponsiveFontSize(BuildContext context, double baseSize) {
    double width = MediaQuery.of(context).size.width;
    if (width < mobileBreakpoint) return baseSize * 0.9;
    if (width < tabletBreakpoint) return baseSize;
    return baseSize * 1.1;
  }

  // Dynamic Padding based on screen size
  static EdgeInsets getResponsivePadding(BuildContext context) {
    DeviceType type = getDeviceType(context);
    switch (type) {
      case DeviceType.mobile:
        return const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0);
      case DeviceType.tablet:
        return const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0);
      case DeviceType.desktop:
        return const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0);
    }
  }

  // Max width for content containers to keep readability on ultra-wide screens
  static double getMaxContentWidth(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    if (width >= 1600) return 1400.0;
    if (width >= 1200) return 1100.0;
    return width;
  }

  static double getHorizontalPadding(BuildContext context) {
    DeviceType type = getDeviceType(context);
    double width = MediaQuery.of(context).size.width;
    
    if (type == DeviceType.desktop) {
      if (width > 1600) return 64.0;
      return 32.0;
    }
    if (type == DeviceType.tablet) return 24.0;
    return 16.0;
  }
}
