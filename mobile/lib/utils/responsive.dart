import 'package:flutter/material.dart';

class ResponsiveHelper {
  static bool isSmallPhone(BuildContext context) {
    return MediaQuery.of(context).size.width < 380;
  }

  static bool isPhone(BuildContext context) {
    return MediaQuery.of(context).size.width < 600;
  }

  static bool isTablet(BuildContext context) {
    return MediaQuery.of(context).size.width >= 600 &&
        MediaQuery.of(context).size.width < 1024;
  }

  static bool isDesktopLike(BuildContext context) {
    return MediaQuery.of(context).size.width >= 1024;
  }

  static double horizontalPadding(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    if (width < 380) return 14;
    if (width < 600) return 18;
    if (width < 1024) return 28;
    return 40;
  }

  static double contentMaxWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    if (width < 600) return width;
    if (width < 1024) return 760;
    return 900;
  }
}