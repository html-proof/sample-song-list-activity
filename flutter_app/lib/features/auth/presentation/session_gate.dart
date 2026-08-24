import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:music_hub_app/core/startup/startup_controller.dart';
import 'package:music_hub_app/core/startup/startup_state.dart';

class SessionGate extends ConsumerWidget {
  const SessionGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destination = ref.watch(startupDestinationProvider);
    return destination.when(
      loading: () => const _Loading(),
      error: (error, _) => _Error(
        message: error.toString(),
        onRetry: () => ref.invalidate(startupDestinationProvider),
      ),
      data: (destination) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) context.go(destination.location);
        });
        return const _Loading();
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
  );
}

class _Error extends StatelessWidget {
  const _Error({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 52),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ],
        ),
      ),
    ),
  );
}
