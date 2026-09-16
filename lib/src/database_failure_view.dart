import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:reaprime/src/ui/startup_failure_shell.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class DatabaseFailureView extends StatelessWidget {
  const DatabaseFailureView({
    super.key,
    required this.logFilePath,
    this.detail,
  });

  final String logFilePath;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final textTheme = ShadTheme.of(context).textTheme;
    final detail = this.detail;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ShadAlert.destructive(
                icon: const Icon(LucideIcons.databaseZap, size: 16),
                title: const Text(
                  'The local database could not be safely opened or updated',
                ),
                description: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 12,
                  children: [
                    const Text(
                      'Decaid stopped because its local database could not be '
                      'opened or updated. Your existing data has been left in '
                      'place.',
                    ),
                    if (detail != null)
                      Text('Diagnostic: $detail', style: textTheme.muted),
                    Text('Log file: $logFilePath', style: textTheme.muted),
                    const Text(
                      'Please preserve your data and share your logs (and a '
                      'data package if one is available) with Decent support, '
                      'then use an updated Decaid build or assisted repair '
                      'before trying again.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DatabaseFailureApp extends StatelessWidget {
  const DatabaseFailureApp({super.key, required this.logFilePath, this.detail});

  final String logFilePath;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return StartupFailureShell(
      child: DatabaseFailureView(logFilePath: logFilePath, detail: detail),
    );
  }
}

@Preview(name: 'Database Startup Failure', group: 'Startup')
Widget databaseStartupFailurePreview() {
  return StartupFailureShell(
    child: DatabaseFailureView(
      logFilePath: '/tmp/support/log.txt',
      detail: 'StateError: incompatible column',
    ),
  );
}
