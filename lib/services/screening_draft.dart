import 'dart:typed_data';

import 'pose_burst.dart';

/// Holds the capture results between screens, so they can be saved together.
class ScreeningDraft {
  static Uint8List? photoBytes;
  static String? photoName;
  static AveragedPose? landmarks; // averaged body points from the capture burst
  static bool photoQualityGood = false; // did the photo pass the quality check?

  static void clear() {
    photoBytes = null;
    photoName = null;
    landmarks = null;
    photoQualityGood = false;
  }
}
