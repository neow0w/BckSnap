import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth_service.dart';

class ResultScreen extends StatelessWidget {
  final double angle;
  const ResultScreen({super.key, required this.angle});

  // Display threshold in degrees (angle of trunk rotation).
  // Keep it equal to scoliosis_threshold in the API's config.py (7.0).
  // The server makes the official decision that gets saved.
  static const double threshold = 7.0;

  bool get hasScoliosis => angle >= threshold;

  // "Did the user use the app as a guest?"
  // YES -> Sign up, NO -> User Home (connector A)
  void _goToReferral(BuildContext context) {
    context.go(AuthService().isGuest ? '/signup' : '/home');
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
        child: Padding(
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
                        '${angle.toStringAsFixed(1)}°',
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
              const Spacer(),
              if (hasScoliosis) ...[
                // Scoliosis = YES
                FilledButton(
                  onPressed: () => _goToReferral(context),
                  child: const Text('Continue to clinic referral'),
                ),
              ] else ...[
                // Scoliosis = NO
                const Text(
                  'Do you still wish to proceed to the clinic referral option?',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => _goToReferral(context),
                  child: const Text('Yes, proceed to referral'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => context.go('/'),
                  child: const Text('No, back to start'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
