import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/screening_service.dart';

class ResultScreen extends StatefulWidget {
  final double angle;
  final ScreeningSubmission? submission;
  final Future<int> Function(ScreeningSubmission submission)? saveAction;

  const ResultScreen({
    super.key,
    required this.angle,
    this.submission,
    this.saveAction,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  bool _saving = false;
  bool _saved = false;
  String? _saveError;
  int? _screeningId;

  @override
  void initState() {
    super.initState();
    if (widget.submission != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _save());
    }
  }

  // Display threshold in degrees (angle of trunk rotation).
  // Keep it equal to scoliosis_threshold in the API's config.py (7.0).
  // The server makes the official decision that gets saved.
  static const double threshold = 7.0;

  bool get hasScoliosis => widget.angle >= threshold;

  Future<void> _save() async {
    final submission = widget.submission;
    if (!mounted || submission == null || _saving || _saved) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      if (widget.saveAction != null) {
        _screeningId = await widget.saveAction!(submission);
      } else {
        await AuthService().signInAsGuest();
        _screeningId = await ScreeningService().saveScreening(
          submission: submission,
        );
      }
      if (mounted) setState(() => _saved = true);
    } on ApiException catch (error) {
      debugPrint(
        'Screening save failed (HTTP ${error.statusCode}) at '
        '${ApiClient.diagnosticOrigin}.',
      );
      if (mounted) setState(() => _saveError = error.message);
    } catch (error) {
      debugPrint(
        'Screening save failed (${error.runtimeType}) at '
        '${ApiClient.diagnosticOrigin}.',
      );
      if (mounted) {
        setState(() {
          _saveError = 'The result is not yet saved. Please retry when the server is available.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color color = hasScoliosis ? Colors.orange : Colors.green;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Screening Result'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: color.withValues(alpha: 0.15),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        hasScoliosis
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle_outline,
                        size: 64,
                        color: color,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        hasScoliosis
                            ? 'Possible scoliosis detected'
                            : 'No sign of scoliosis detected',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${widget.angle.toStringAsFixed(1)}°',
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text('Angle of trunk rotation'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'This is a screening result, not a medical diagnosis. '
                'Only a doctor can confirm scoliosis.',
                textAlign: TextAlign.center,
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Recommended next step',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        hasScoliosis
                            ? 'Discuss this screening result with a qualified healthcare professional.'
                            : 'If you have concerns, discuss them with a qualified healthcare professional.',
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.submission != null) ...[
                const SizedBox(height: 12),
                _buildSaveStatus(context),
              ],
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Find a Clinic',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'This screening does not identify a medical specialty or determine which clinic is right for you. Browse available clinics and discuss your result with a healthcare professional.',
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => context.push('/clinics'),
                        icon: const Icon(Icons.local_hospital_outlined),
                        label: const Text('Find Clinics'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => context.go('/'),
                child: const Text('Back to start'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSaveStatus(BuildContext context) {
    final text = _saved
        ? 'Saved'
        : _saving
        ? 'Saving result…'
        : 'Not yet saved';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  _saved ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (_saved && _screeningId != null)
              Text('Screening reference: $_screeningId'),
            if (!_saved && _saveError != null) ...[
              const SizedBox(height: 8),
              Text(_saveError!),
            ],
            if (!_saved && !_saving) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Save'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
