import 'package:flutter/material.dart';

class MobileConfig {
  // Responsive breakpoints - updated for better mobile/tablet/desktop distinction
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 900;
  static const double desktopBreakpoint = 1200;

  // Card dimensions for different screen sizes - optimized for UNO game
  static const double mobileCardWidth = 65;
  static const double mobileCardHeight = 90;
  static const double tabletCardWidth = 75;
  static const double tabletCardHeight = 105;
  static const double desktopCardWidth = 85;
  static const double desktopCardHeight = 120;

  // Spacing for different screen sizes
  static const double mobileSpacing = 16.0;
  static const double tabletSpacing = 20.0;
  static const double desktopSpacing = 24.0;

  // Button heights for touch targets
  static const double mobileButtonHeight = 48.0;
  static const double tabletButtonHeight = 56.0;
  static const double desktopButtonHeight = 64.0;

  // Game-specific responsive values
  static const double mobileGameCenterHeight = 100.0;
  static const double tabletGameCenterHeight = 120.0;
  static const double desktopGameCenterHeight = 140.0;

  static const double mobilePlayerCardsHeight = 90.0;
  static const double tabletPlayerCardsHeight = 110.0;
  static const double desktopPlayerCardsHeight = 130.0;

  // Get responsive card dimensions
  static Size getCardDimensions(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < mobileBreakpoint) {
      return const Size(mobileCardWidth, mobileCardHeight);
    } else if (width < tabletBreakpoint) {
      return const Size(tabletCardWidth, tabletCardHeight);
    } else {
      return const Size(desktopCardWidth, desktopCardHeight);
    }
  }

  // Get responsive spacing
  static double getSpacing(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < mobileBreakpoint) {
      return mobileSpacing;
    } else if (width < tabletBreakpoint) {
      return tabletSpacing;
    } else {
      return desktopSpacing;
    }
  }

  // Get responsive button height
  static double getButtonHeight(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < mobileBreakpoint) {
      return mobileButtonHeight;
    } else if (width < tabletBreakpoint) {
      return tabletButtonHeight;
    } else {
      return desktopButtonHeight;
    }
  }

  // Get responsive game center height
  static double getGameCenterHeight(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < mobileBreakpoint) {
      return mobileGameCenterHeight;
    } else if (width < tabletBreakpoint) {
      return tabletGameCenterHeight;
    } else {
      return desktopGameCenterHeight;
    }
  }

  // Get responsive player cards height
  static double getPlayerCardsHeight(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < mobileBreakpoint) {
      return mobilePlayerCardsHeight;
    } else if (width < tabletBreakpoint) {
      return tabletPlayerCardsHeight;
    } else {
      return desktopPlayerCardsHeight;
    }
  }

  // Check if device is mobile
  static bool isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < mobileBreakpoint;
  }

  // Check if device is tablet
  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= mobileBreakpoint && width < tabletBreakpoint;
  }

  // Check if device is desktop
  static bool isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= desktopBreakpoint;
  }

  // Get responsive text scale factor
  static double getTextScaleFactor(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < mobileBreakpoint) {
      return 0.9; // Slightly smaller text on mobile
    } else if (width < tabletBreakpoint) {
      return 1.0; // Normal text size on tablet
    } else {
      return 1.1; // Slightly larger text on desktop
    }
  }

  // Get responsive padding
  static EdgeInsets getResponsivePadding(BuildContext context) {
    final spacing = getSpacing(context);
    return EdgeInsets.all(spacing);
  }

  // Get responsive margin
  static EdgeInsets getResponsiveMargin(BuildContext context) {
    final spacing = getSpacing(context);
    return EdgeInsets.all(spacing);
  }

  // Get responsive border radius
  static double getBorderRadius(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < mobileBreakpoint) {
      return 12.0;
    } else if (width < tabletBreakpoint) {
      return 16.0;
    } else {
      return 20.0;
    }
  }

  // Get responsive elevation
  static double getElevation(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < mobileBreakpoint) {
      return 4.0;
    } else if (width < tabletBreakpoint) {
      return 6.0;
    } else {
      return 8.0;
    }
  }

  // Get mobile-safe padding that accounts for viewport insets
  static EdgeInsets getMobileSafePadding(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isMobileDevice = isMobile(context);

    if (isMobileDevice) {
      return EdgeInsets.only(
        left: mobileSpacing,
        right: mobileSpacing,
        top: mobileSpacing,
        bottom: mobileSpacing +
            mediaQuery.padding.bottom +
            20, // Extra bottom padding for mobile
      );
    } else {
      return EdgeInsets.all(getSpacing(context));
    }
  }

  // Get bottom padding that prevents cutoff on mobile devices
  static double getBottomPadding(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isMobileDevice = isMobile(context);

    if (isMobileDevice) {
      return mediaQuery.padding.bottom + 32; // Extra padding for mobile
    } else {
      return 24;
    }
  }

  // Check if device has notches or system UI that might cause cutoff
  static bool hasSystemUIOverlap(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return mediaQuery.padding.bottom > 0 ||
        mediaQuery.padding.top > 0 ||
        mediaQuery.viewInsets.bottom > 0;
  }

  // Get safe area height for mobile devices
  static double getSafeAreaHeight(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isMobileDevice = isMobile(context);

    if (isMobileDevice) {
      return mediaQuery.padding.top +
          mediaQuery.padding.bottom +
          40; // Extra buffer
    } else {
      return 0;
    }
  }

  // Get responsive card scaling factors for opponent cards
  static Map<String, double> getOpponentCardScaling(
      BuildContext context, int cardCount) {
    final isMobileDevice = isMobile(context);
    final isTabletDevice = isTablet(context);

    if (isMobileDevice) {
      if (cardCount <= 4) {
        return {'width': 0.75, 'height': 0.7, 'margin': 1.0};
      } else if (cardCount <= 6) {
        return {'width': 0.67, 'height': 0.62, 'margin': 0.75};
      } else if (cardCount <= 8) {
        return {'width': 0.58, 'height': 0.54, 'margin': 0.5};
      } else {
        return {'width': 0.5, 'height': 0.47, 'margin': 0.25};
      }
    } else if (isTabletDevice) {
      if (cardCount <= 4) {
        return {'width': 0.85, 'height': 0.8, 'margin': 1.5};
      } else if (cardCount <= 6) {
        return {'width': 0.75, 'height': 0.7, 'margin': 1.25};
      } else if (cardCount <= 8) {
        return {'width': 0.67, 'height': 0.62, 'margin': 1.0};
      } else {
        return {'width': 0.58, 'height': 0.54, 'margin': 0.75};
      }
    } else {
      if (cardCount <= 4) {
        return {'width': 0.9, 'height': 0.85, 'margin': 2.0};
      } else if (cardCount <= 6) {
        return {'width': 0.8, 'height': 0.75, 'margin': 1.75};
      } else if (cardCount <= 8) {
        return {'width': 0.7, 'height': 0.65, 'margin': 1.5};
      } else {
        return {'width': 0.6, 'height': 0.55, 'margin': 1.25};
      }
    }
  }

  // Get responsive player card scaling factors
  static Map<String, double> getPlayerCardScaling(
      BuildContext context, int cardCount) {
    final isMobileDevice = isMobile(context);
    final isTabletDevice = isTablet(context);

    if (isMobileDevice) {
      if (cardCount <= 4) {
        return {'width': 0.9, 'height': 0.9, 'margin': 2.0};
      } else if (cardCount <= 6) {
        return {'width': 0.8, 'height': 0.8, 'margin': 1.5};
      } else if (cardCount <= 8) {
        return {'width': 0.7, 'height': 0.7, 'margin': 1.0};
      } else {
        return {'width': 0.6, 'height': 0.6, 'margin': 0.5};
      }
    } else if (isTabletDevice) {
      if (cardCount <= 4) {
        return {'width': 0.95, 'height': 0.95, 'margin': 3.0};
      } else if (cardCount <= 6) {
        return {'width': 0.85, 'height': 0.85, 'margin': 2.5};
      } else if (cardCount <= 8) {
        return {'width': 0.75, 'height': 0.75, 'margin': 2.0};
      } else {
        return {'width': 0.65, 'height': 0.65, 'margin': 1.5};
      }
    } else {
      if (cardCount <= 4) {
        return {'width': 1.0, 'height': 1.0, 'margin': 4.0};
      } else if (cardCount <= 6) {
        return {'width': 0.9, 'height': 0.9, 'margin': 3.5};
      } else if (cardCount <= 8) {
        return {'width': 0.8, 'height': 0.8, 'margin': 3.0};
      } else {
        return {'width': 0.7, 'height': 0.7, 'margin': 2.5};
      }
    }
  }
}
