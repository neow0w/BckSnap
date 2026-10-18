import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.accessibility_new, size: 96),
              const SizedBox(height: 16),
              const Text(
                'Scoliosis Screening',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Quick, smartphone-based screening and clinic referral.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              FilledButton(
                // NO: not an existing user. The guest session is created
                // on the photo screen.
                onPressed: () => context.go('/screening/photo'),
                child: const Text('Start Screening'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                // YES: existing user
                onPressed: () => context.go('/login'),
                child: const Text('I already have an account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
