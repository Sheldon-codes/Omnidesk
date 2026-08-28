import 'package:flutter/material.dart';

import '../../flutter_flow/flutter_flow_theme.dart';
export 'splash_screen_model.dart';

class SplashScreenWidget extends StatelessWidget {
  const SplashScreenWidget({super.key});

  static const routeName = 'SplashScreen';
  static const routePath = '/splash';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}
