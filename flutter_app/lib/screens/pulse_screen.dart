import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import 'settings_screen.dart';

class PulseScreen extends StatelessWidget {
  const PulseScreen({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final tracks = state.recommendations.isNotEmpty
        ? state.recommendations
        : state.trending;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Music Hub Pulse',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Text(
                      'Your music community',
                      style: TextStyle(color: context.hubColors.textSecondary),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Settings',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SettingsScreen(state: state),
                  ),
                ),
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.hubColors.surfaceColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.hubColors.dividerColor),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.orange,
                  child: Icon(Icons.person, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'What are you listening to?',
                    style: TextStyle(color: context.hubColors.textMuted),
                  ),
                ),
                Icon(Icons.photo_outlined, color: context.hubColors.textMuted),
              ],
            ),
          ),
          const SizedBox(height: 22),
          if (tracks.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No community posts are available.'),
              ),
            )
          else
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Community posts will appear when returned by the backend.',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
