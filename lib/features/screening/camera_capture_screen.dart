import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../services/auth_service.dart';
import '../../services/pose_detector.dart';
import '../../services/screening_draft.dart';
import 'back_guide.dart';
import 'guide_checker.dart';
import 'pose_overlay.dart';

enum _CamState { checking, needsPermission, blocked, noCamera, error, ready }

class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  _CamState _state = _CamState.checking;
  String? _errorText;
  Uint8List? _captured; // set while the user is reviewing the photo
  bool _capturing = false;
  bool _starting = false;

  // Pose detection and the live guideline checker
  final BodyPoseDetector _detector = BodyPoseDetector();
  final GuideChecker _checker = GuideChecker();
  final ValueNotifier<PoseFrame?> _pose = ValueNotifier<PoseFrame?>(null);
  final ValueNotifier<GuideStatus?> _status = ValueNotifier<GuideStatus?>(null);
  String? _detectorError;
  int _lastRunMs = 0;

  // How the phone is held (from the accelerometer)
  StreamSubscription<AccelerometerEvent>? _accelSub;
  PhoneTilt? _tilt;
  int _lastTiltMs = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Make sure there is a session (guest or logged in) before screening.
    AuthService().signInAsGuest().catchError((_) {});
    _listenTilt();
    _start(request: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accelSub?.cancel();
    _controller?.dispose();
    _detector.stop();
    _pose.dispose();
    _status.dispose();
    super.dispose();
  }

  // Release the camera when the app goes to the background and
  // check again when it comes back (for example from Settings).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      final c = _controller;
      if (c != null) {
        _controller = null;
        c.dispose(); // also stops the frame stream
        _clearLive();
        if (mounted && _captured == null) {
          setState(() => _state = _CamState.checking);
        }
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null && _captured == null) _start();
    }
  }

  void _clearLive() {
    _pose.value = null;
    _status.value = null;
    _checker.reset();
  }

  // ---- phone tilt -----------------------------------------------------------

  void _listenTilt() {
    try {
      _accelSub = accelerometerEventStream().listen((e) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastTiltMs < 80) return;
        _lastTiltMs = now;

        // 0 degrees = phone upright in portrait, screen facing the user.
        final roll = math.atan2(e.x, e.y) * 180 / math.pi;
        final pitch =
            math.atan2(e.z, math.sqrt(e.x * e.x + e.y * e.y)) * 180 / math.pi;

        final old = _tilt;
        _tilt = old == null
            ? PhoneTilt(roll, pitch)
            : PhoneTilt(
                old.rollDeg * 0.7 + roll * 0.3,
                old.pitchDeg * 0.7 + pitch * 0.3,
              );
      }, onError: (_) {});
    } catch (_) {
      // No accelerometer: the "Level" check is simply skipped.
    }
  }

  // ---- camera start ---------------------------------------------------------

  /// [request] = true shows the system permission dialog (only on first
  /// open or when the user taps "Allow camera").
  Future<void> _start({bool request = false}) async {
    if (_starting) return;
    _starting = true;
    try {
      var status = await Permission.camera.status;
      if (!status.isGranted && request && !status.isPermanentlyDenied) {
        status = await Permission.camera.request();
      }
      if (!mounted) return;

      if (status.isPermanentlyDenied || status.isRestricted) {
        setState(() => _state = _CamState.blocked);
      } else if (!status.isGranted) {
        setState(() => _state = _CamState.needsPermission);
      } else {
        await _initCamera();
      }
    } finally {
      _starting = false;
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final back = cameras.where(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      if (back.isEmpty) {
        if (mounted) setState(() => _state = _CamState.noCamera);
        return;
      }

      final controller = CameraController(
        back.first,
        ResolutionPreset.high,
        enableAudio: false,
        // The pose detector reads 3-plane YUV420 frames on Android.
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.android
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);

      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller?.dispose();
      _clearLive();
      setState(() {
        _controller = controller;
        _state = _CamState.ready;
      });
      _startAnalysis(controller);
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _CamState.error;
        _errorText = e.description ?? e.code;
      });
    }
  }

  // ---- pose detection on live frames ----------------------------------------

  Future<void> _startAnalysis(CameraController c) async {
    try {
      await _detector.start();
      if (!mounted || _controller != c) return;
      if (c.value.isStreamingImages) return;
      await c.startImageStream(_onFrame);
      if (mounted && _detectorError != null) {
        setState(() => _detectorError = null);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _detectorError = e.toString());
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    final c = _controller;
    if (c == null || _captured != null || _capturing) return;

    // At most 5 analyses per second, and never two at once.
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_detector.busy || now - _lastRunMs < 200) return;
    _lastRunMs = now;

    try {
      final frame = await _detector.detect(
        image,
        c.description.sensorOrientation,
      );
      if (!mounted || frame == null || _controller != c) return;
      _pose.value = frame;
      _status.value = _checker.update(frame, tilt: _tilt);
    } catch (e) {
      if (mounted && _detectorError == null) {
        setState(() => _detectorError = e.toString());
      }
    }
  }

  String _poseStatus() {
    final f = _pose.value;
    if (f == null) return '';
    if (!f.found) return 'No person detected  (${f.millis} ms)';
    String s(int i) => ((f.point(i)?.score ?? 0) * 100).round().toString();
    final t = _tilt;
    final tilt = t == null
        ? ''
        : '   Tilt ${t.rollDeg.toStringAsFixed(0)}/${t.pitchDeg.toStringAsFixed(0)}';
    return '${f.millis} ms   '
        'Shoulders ${s(PoseIndex.leftShoulder)}/${s(PoseIndex.rightShoulder)}   '
        'Hips ${s(PoseIndex.leftHip)}/${s(PoseIndex.rightHip)}$tilt';
  }

  // ---- capture --------------------------------------------------------------

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
      final file = await c.takePicture();
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      _clearLive();
      setState(() => _captured = bytes);
    } on CameraException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not take the photo: ${e.description ?? e.code}'),
        ),
      );
      _startAnalysis(c); // go back to live detection
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _continue() {
    ScreeningDraft.photoBytes = _captured;
    ScreeningDraft.photoName = 'back_photo.jpg';
    context.go('/screening/test');
  }

  void _retake() {
    _clearLive();
    setState(() => _captured = null);
    final c = _controller;
    if (c == null) {
      _start();
    } else {
      _startAnalysis(c);
    }
  }

  // ---- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Take Back Photo'),
        leading: BackButton(onPressed: () => context.go('/')),
      ),
      body: SafeArea(child: _captured != null ? _buildReview() : _buildBody()),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _CamState.checking:
        return const Center(child: CircularProgressIndicator());
      case _CamState.needsPermission:
        return _message(
          icon: Icons.camera_alt_outlined,
          title: 'Camera access needed',
          text:
              'The app uses the camera to photograph the back for screening. '
              'The photo is saved only to your account.',
          primaryLabel: 'Allow camera',
          onPrimary: () => _start(request: true),
        );
      case _CamState.blocked:
        return _message(
          icon: Icons.no_photography_outlined,
          title: 'Camera is blocked',
          text:
              'Camera permission was turned off. Open the app settings, '
              'tap Permissions, and allow Camera.',
          primaryLabel: 'Open settings',
          onPrimary: openAppSettings,
        );
      case _CamState.noCamera:
        return _message(
          icon: Icons.videocam_off_outlined,
          title: 'No camera found',
          text: 'This device has no back camera.',
        );
      case _CamState.error:
        return _message(
          icon: Icons.error_outline,
          title: 'Camera problem',
          text: _errorText ?? 'The camera could not be started.',
          primaryLabel: 'Try again',
          onPrimary: () => _start(request: true),
        );
      case _CamState.ready:
        return _buildPreview();
    }
  }

  Widget _message({
    required IconData icon,
    required String title,
    required String text,
    String? primaryLabel,
    VoidCallback? onPrimary,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            if (primaryLabel != null)
              FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
            TextButton(
              onPressed: () => context.go('/screening/upload'),
              child: const Text('Use a photo from the gallery instead'),
            ),
          ],
        ),
      ),
    );
  }

  Color _guideColor(GuideStatus? st) {
    if (st == null) return Colors.white;
    if (st.ready) return Colors.greenAccent;
    if (st.allOk) return Colors.amberAccent;
    return Colors.white;
  }

  Widget _buildPreview() {
    final c = _controller!;
    return Column(
      children: [
        _buildCoach(),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1 / c.value.aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CameraPreview(c),
                  ValueListenableBuilder<GuideStatus?>(
                    valueListenable: _status,
                    builder: (context, st, _) => IgnorePointer(
                      child: CustomPaint(
                        painter: AlignmentOverlayPainter(
                          color: _guideColor(st),
                        ),
                      ),
                    ),
                  ),
                  RepaintBoundary(
                    child: IgnorePointer(
                      child: ValueListenableBuilder<PoseFrame?>(
                        valueListenable: _pose,
                        builder: (context, pose, _) =>
                            CustomPaint(painter: PoseOverlayPainter(pose)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: ValueListenableBuilder<GuideStatus?>(
            valueListenable: _status,
            builder: (context, st, _) => SizedBox(
              width: 72,
              height: 72,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  backgroundColor: (st?.ready ?? false) ? Colors.green : null,
                ),
                onPressed: _capturing ? null : _capture,
                child: _capturing
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.camera_alt, size: 32),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The banner above the preview: what to do next, plus a checklist.
  Widget _buildCoach() {
    return ValueListenableBuilder<GuideStatus?>(
      valueListenable: _status,
      builder: (context, st, _) {
        final ready = st?.ready ?? false;
        final String hint = _detectorError != null
            ? 'Pose detector problem: $_detectorError'
            : (st?.hint ?? 'Starting pose detection...');

        return Container(
          width: double.infinity,
          color: ready ? Colors.green.shade700 : Colors.black87,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hint,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (st != null) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  children: [for (final item in st.items) _chip(item)],
                ),
                if (st.allOk && !st.ready) ...[
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: st.progress),
                ],
              ],
              const SizedBox(height: 4),
              Text(
                _poseStatus(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(CheckItem item) {
    final color = item.ok ? Colors.greenAccent : Colors.redAccent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          item.ok ? Icons.check_circle : Icons.cancel,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 3),
        Text(
          item.label,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildReview() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Is the image clear and within the guidelines?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Expanded(child: Image.memory(_captured!, fit: BoxFit.contain)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _continue,
            child: const Text('Yes, continue'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _retake, child: const Text('No, retake')),
        ],
      ),
    );
  }
}
