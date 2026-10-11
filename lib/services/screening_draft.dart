import 'dart:typed_data';

/// Holds the back photo between the photo screen and the scoliometer
/// screen, so both can be saved together in one request.
class ScreeningDraft {
  static Uint8List? photoBytes;
  static String? photoName;

  static void clear() {
    photoBytes = null;
    photoName = null;
  }
}
