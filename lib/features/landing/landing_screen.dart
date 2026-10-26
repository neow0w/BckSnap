import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Expanded(child: Center(child: BrandLogo(size: 220))),
                  Text(
                    'Preliminary screening tool • Non-diagnostic',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    // For now this opens the camera. It will open the
                    // Screening Hub in UI phase 3.
                    onPressed: () => context.go('/screening/photo'),
                    child: const Text('GET STARTED AS GUEST'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.tonal,
                      foregroundColor: AppColors.primary,
                    ),
                    onPressed: () => context.go('/login'),
                    child: const Text('LOG IN'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
