import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:reaprime/src/theme/theme.dart';

class StartupFailureShell extends StatelessWidget {
  const StartupFailureShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ShadApp(
      title: 'Decaid',
      debugShowCheckedModeBanner: false,
      theme: buildDecentTheme(),
      darkTheme: buildDecentTheme(brightness: Brightness.dark),
      themeMode: ThemeMode.system,
      home: child,
    );
  }
}
