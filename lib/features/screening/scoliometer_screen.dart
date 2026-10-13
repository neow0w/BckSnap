import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../services/screening_draft.dart';
import '../../services/screening_service.dart';

class ScoliometerScreen extends StatefulWidget {
  const ScoliometerScreen({super.key});

  @override
  State<ScoliometerScreen> createState() => _ScoliometerScreenState();
}

class _ScoliometerScreenState extends State<ScoliometerScreen> {
  StreamSubscription<AccelerometerEvent>? _sub;
  Timer? _sensorTimer;

  double _smoothAngle = 0; // filtered tilt from the sensor
  double _zeroOffset = 0; // calibration offset
  double? _captured; // frozen reading (null = still measuring)
  bool _hasSensor = false;
  bool _testMode = false; // used when no sensor exists (e.g. PC browser)
  double _simAngle = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _sub = accelerometerEventStream().listen((event) {
      // Tilt left/right when the phone lies flat on the back
      final angle = math.atan2(event.x, event.z) * 180 / math.pi;
      if (!mounted) return;
      setState(() {
        _hasSensor = true;
        _smoothAngle = _smoothAngle * 0.8 + angle * 0.2;
      });
    }, onError: (_) {});

    // If no sensor data arrives, switch on test mode with a slider
    _sensorTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && !_hasSensor) setState(() => _testMode = true);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sensorTimer?.cancel();
    super.dispose();
  }

  double get _angle => _testMode ? _simAngle : _smoothAngle - _zeroOffset;

  void _setZero() => setState(() => _zeroOffset = _smoothAngle);

  void _capture() => setState(() => _captured = _angle);

  void _retake() => setState(() => _captured = null);

  // Show the completed reading immediately; the result page handles saving.
  Future<void> _confirm() async {
    final angle = _captured!.abs();
    if (!angle.isFinite || angle < 0 || angle > 90) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This reading is outside the supported range. Please measure again.',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);

    final submission = ScreeningSubmission.create(
      angle: angle,
      photoBytes: ScreeningDraft.photoBytes,
      photoName: ScreeningDraft.photoName,
    );
    ScreeningDraft.clear();
    if (!mounted) return;
    context.go('/screening/result', extra: submission);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Adam's Forward Bend Test"),
        leading: BackButton(onPressed: () => context.go('/screening/photo')),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildInstructions(),
              const SizedBox(height: 24),
              _buildReading(),
              const SizedBox(height: 24),
              if (_captured == null)
                _buildMeasureButtons()
              else
                _buildConfirm(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstructions() {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How to measure',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              '1. Place the phone flat on a level surface and tap "Set Zero".',
            ),
            SizedBox(height: 6),
            Text(
              '2. The patient stands with feet together and bends forward, arms hanging, palms together.',
            ),
            SizedBox(height: 6),
            Text(
              '3. Lay the phone flat across the back, screen facing up, at the most prominent part of the back.',
            ),
            SizedBox(height: 6),
            Text('4. Hold still, then tap "Capture Reading".'),
          ],
        ),
      ),
    );
  }

  Widget _buildReading() {
    final value = (_captured ?? _angle).abs();
    return Column(
      children: [
        Text(
          _captured == null ? 'Live reading' : 'Captured reading',
          style: const TextStyle(fontSize: 16),
        ),
        Text(
          '${value.toStringAsFixed(1)}°',
          style: const TextStyle(fontSize: 64, fontWeight: FontWeight.bold),
        ),
        const Text('Angle of trunk rotation'),
      ],
    );
  }

  Widget _buildMeasureButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_testMode) ...[
          const Text(
            'No motion sensor detected. Test mode: use the slider.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.orange),
          ),
          Slider(
            value: _simAngle,
            min: -20,
            max: 20,
            divisions: 80,
            label: _simAngle.toStringAsFixed(1),
            onChanged: (v) => setState(() => _simAngle = v),
          ),
        ] else
          OutlinedButton.icon(
            onPressed: _setZero,
            icon: const Icon(Icons.exposure_zero),
            label: const Text('Set Zero (phone on level surface)'),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _capture,
          icon: const Icon(Icons.check_circle),
          label: const Text('Capture Reading'),
        ),
      ],
    );
  }

  Widget _buildConfirm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Is the user satisfied with the reading?',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _saving ? null : _confirm,
          child: _saving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Yes, see result'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _saving ? null : _retake,
          child: const Text('No, measure again'),
        ),
      ],
    );
  }
}
