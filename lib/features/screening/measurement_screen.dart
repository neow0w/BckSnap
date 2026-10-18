import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/screening_draft.dart';
import '../../services/screening_service.dart';
import '../../services/tilt_sensor.dart';
import 'back_levels.dart';

enum _Phase { zero, measure, review }

class MeasurementScreen extends StatefulWidget {
  const MeasurementScreen({super.key});

  @override
  State<MeasurementScreen> createState() => _MeasurementScreenState();
}

class _MeasurementScreenState extends State<MeasurementScreen> {
  final TiltSensor _sensor = TiltSensor();
  Timer? _sensorTimer;

  _Phase _phase = _Phase.zero;
  int _levelIndex = 0;
  bool _fromReview = false; // re-measuring one level from the review screen
  final Map<String, LevelReading> _readings = {};
  LevelReading? _pending; // captured, waiting for "Keep" or "Re-measure"
  bool _capturing = false;
  String? _message;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _sensor.start();
    // No sensor data after 2 seconds (a computer): test mode with a slider.
    _sensorTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && !_sensor.hasAccelerometer) {
        setState(() => _sensor.testMode = true);
      }
    });
  }

  @override
  void dispose() {
    _sensorTimer?.cancel();
    _sensor.dispose();
    super.dispose();
  }

  // ---- logic ----------------------------------------------------------------

  LevelReading? get _highest {
    LevelReading? best;
    for (final r in _readings.values) {
      if (best == null || r.atr > best.atr) best = r;
    }
    return best;
  }

  void _setZeroAndStart() {
    _sensor.setZero();
    setState(() {
      _phase = _Phase.measure;
      _levelIndex = 0;
      _fromReview = false;
      _pending = null;
      _message = null;
    });
  }

  Future<void> _capture(BackLevel level) async {
    setState(() {
      _capturing = true;
      _message = null;
    });
    final r = await _sensor.capture();
    if (!mounted) return;
    setState(() {
      _capturing = false;
      if (r == null) {
        _message =
            'No motion sensor data. Check that this phone has a '
            'motion sensor and try again.';
      } else if (r.range > TiltRules.maxRange) {
        _message =
            'The phone moved during the reading '
            '(${r.range.toStringAsFixed(1)}°). Hold it steady and try again.';
      } else {
        _pending = LevelReading(level, r.angle, r.range);
      }
    });
  }

  void _keep() {
    final p = _pending!;
    _readings[p.level.id] = p;
    setState(() {
      _pending = null;
      if (_fromReview || _levelIndex >= BackLevels.all.length - 1) {
        _fromReview = false;
        _phase = _Phase.review;
      } else {
        _levelIndex++;
      }
    });
  }

  void _remeasure() => setState(() {
    _pending = null;
    _message = null;
  });

  void _remeasureLevel(int index) => setState(() {
    _levelIndex = index;
    _fromReview = true;
    _pending = null;
    _message = null;
    _phase = _Phase.measure;
  });

  void _measureAgain() => setState(() {
    _readings.clear();
    _levelIndex = 0;
    _fromReview = false;
    _pending = null;
    _message = null;
    _phase = _Phase.measure;
  });

  void _back() {
    switch (_phase) {
      case _Phase.zero:
        context.go('/screening/photo');
      case _Phase.measure:
        setState(() {
          _pending = null;
          _message = null;
          if (_fromReview) {
            _fromReview = false;
            _phase = _Phase.review;
          } else if (_levelIndex > 0) {
            _levelIndex--;
          } else {
            _phase = _Phase.zero;
          }
        });
      case _Phase.review:
        setState(() {
          _levelIndex = BackLevels.all.length - 1;
          _fromReview = false;
          _phase = _Phase.measure;
        });
    }
  }

  // Save the highest ATR, then show the result.
  Future<void> _save() async {
    final highest = _highest;
    if (highest == null) return;
    setState(() => _saving = true);

    var saved = true;
    try {
      await ScreeningService().saveScreening(
        angle: highest.atr,
        photoBytes: ScreeningDraft.photoBytes,
        photoName: ScreeningDraft.photoName,
      );
      ScreeningDraft.clear();
    } catch (_) {
      saved = false;
    }

    if (!mounted) return;
    setState(() => _saving = false);
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The result could not be saved. Check your connection.',
          ),
        ),
      );
    }
    context.go('/screening/result', extra: highest.atr);
  }

  // ---- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final title = switch (_phase) {
      _Phase.zero => 'Set zero',
      _Phase.measure => 'Measure ATR',
      _Phase.review => 'Review readings',
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: BackButton(onPressed: _back),
      ),
      body: SafeArea(
        child: switch (_phase) {
          _Phase.zero => _buildZero(),
          _Phase.measure => _buildMeasure(),
          _Phase.review => _buildReview(),
        },
      ),
    );
  }

  Widget _liveReading() {
    return ValueListenableBuilder<double>(
      valueListenable: _sensor.angle,
      builder: (context, value, _) {
        final steady = _sensor.isSteady;
        return Column(
          children: [
            Text(
              '${value.abs().toStringAsFixed(1)}°',
              style: const TextStyle(fontSize: 64, fontWeight: FontWeight.bold),
            ),
            Text('Angle of trunk rotation  (${value >= 0 ? "+" : "-"})'),
            const SizedBox(height: 8),
            Chip(
              avatar: Icon(
                steady ? Icons.check_circle : Icons.sync,
                size: 18,
                color: steady ? Colors.green : Colors.orange,
              ),
              label: Text(steady ? 'Steady' : 'Moving'),
            ),
          ],
        );
      },
    );
  }

  Widget _simulatorSlider() {
    return Column(
      children: [
        const Text(
          'No motion sensor detected. Test mode: use the slider.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.orange),
        ),
        ValueListenableBuilder<double>(
          valueListenable: _sensor.angle,
          builder: (context, v, _) => Slider(
            value: v.clamp(-20.0, 20.0).toDouble(),
            min: -20,
            max: 20,
            divisions: 80,
            label: v.toStringAsFixed(1),
            onChanged: _sensor.setSimulated,
          ),
        ),
      ],
    );
  }

  Widget _buildZero() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Zero the phone',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  '1. Put the phone flat on a level table, screen facing up, '
                  'with the long edge pointing left to right.',
                ),
                SizedBox(height: 6),
                Text(
                  '2. Check the axis: lift one of the two narrow ends a '
                  'little, like a see-saw. The number should change. '
                  'Lifting a long edge should not.',
                ),
                SizedBox(height: 6),
                Text(
                  '3. Put it back flat and wait for "Steady", then tap '
                  '"Set zero and start".',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        _liveReading(),
        if (_sensor.testMode) _simulatorSlider(),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _setZeroAndStart,
          icon: const Icon(Icons.exposure_zero),
          label: const Text('Set zero and start'),
        ),
      ],
    );
  }

  Widget _buildMeasure() {
    final level = BackLevels.all[_levelIndex];
    final pending = _pending;
    final total = BackLevels.all.length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          _fromReview
              ? 'Re-measuring: ${level.name}'
              : 'Level ${_levelIndex + 1} of $total',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        Text(level.name, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: _levelIndex / total),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Where: ${level.where}'),
                const SizedBox(height: 8),
                const Text(
                  "The patient bends forward (Adam's forward bend), arms "
                  'hanging. Lay the phone flat across the back, screen up, '
                  'long edge across the spine. Hold it steady, then tap '
                  '"Capture reading".',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _liveReading(),
        if (_sensor.testMode) _simulatorSlider(),
        const SizedBox(height: 16),
        if (_message != null)
          Card(
            color: Colors.orange.withValues(alpha: 0.15),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_message!),
            ),
          ),
        const SizedBox(height: 8),
        if (pending == null)
          FilledButton.icon(
            onPressed: _capturing ? null : () => _capture(level),
            icon: _capturing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle),
            label: Text(_capturing ? 'Hold still...' : 'Capture reading'),
          )
        else
          Card(
            color: Colors.green.withValues(alpha: 0.12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Reading: ${pending.atr.toStringAsFixed(1)}°',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _keep,
                    child: Text(
                      _fromReview || _levelIndex >= total - 1
                          ? 'Keep this reading'
                          : 'Keep and go to the next level',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _remeasure,
                    child: const Text('Re-measure'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildReview() {
    final highest = _highest;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: highest == null
                      ? const Text(
                          'No readings yet. Measure at least one level.',
                        )
                      : Column(
                          children: [
                            const Text('Highest ATR (this is the value saved)'),
                            Text(
                              '${highest.atr.toStringAsFixed(1)}°',
                              style: const TextStyle(
                                fontSize: 44,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'at the ${highest.level.name.toLowerCase()} level',
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < BackLevels.all.length; i++)
                _reviewTile(i, highest),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: (highest == null || _saving) ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Confirm and save'),
              ),
              TextButton(
                onPressed: _saving ? null : _measureAgain,
                child: const Text('Measure all levels again'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _reviewTile(int index, LevelReading? highest) {
    final level = BackLevels.all[index];
    final r = _readings[level.id];
    final isHighest =
        r != null && highest != null && r.level.id == highest.level.id;
    return Card(
      child: ListTile(
        leading: Icon(
          isHighest ? Icons.star : Icons.straighten,
          color: isHighest ? Colors.amber : null,
        ),
        title: Text(level.name),
        subtitle: Text(
          r == null
              ? 'Not measured'
              : 'ATR ${r.atr.toStringAsFixed(1)}°   (moved ${r.range.toStringAsFixed(1)}° during the reading)',
        ),
        trailing: OutlinedButton(
          onPressed: _saving ? null : () => _remeasureLevel(index),
          child: Text(r == null ? 'Measure' : 'Re-measure'),
        ),
      ),
    );
  }
}
