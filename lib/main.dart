import 'package:flutter/material.dart';

import 'core/router.dart';
import 'core/theme.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthService().init(); // restores the saved login, if any
  runApp(const ScolioApp());
}

class ScolioApp extends StatelessWidget {
  const ScolioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Scoliosis Screening',
      theme: appTheme,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
