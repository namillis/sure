import 'package:flutter/services.dart';

/// The app's haptic vocabulary, so every screen uses the same feedback for the
/// same kind of moment.
abstract final class SureHaptics {
  /// A swipe action committed (Categorize, Delete).
  static Future<void> swipeCommit() => HapticFeedback.lightImpact();

  /// A selection changed in a segmented control, chip or picker.
  static Future<void> selection() => HapticFeedback.selectionClick();

  /// A save finished successfully.
  static Future<void> success() => HapticFeedback.lightImpact();
}
