import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets.dart';

class LanguageSelectionScreen extends StatefulWidget {
  const LanguageSelectionScreen({
    super.key,
    required this.state,
    required this.onBack,
    required this.onContinue,
  });
  final AppState state;
  final VoidCallback onBack, onContinue;
  @override
  State<LanguageSelectionScreen> createState() =>
      _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen> {
  bool loading = true, saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    widget.state.addListener(_refresh);
    if (widget.state.languages.isNotEmpty) {
      loading = false;
    }
    _load();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.state.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.state.languages.isEmpty) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      await widget.state.loadLanguages();
    } catch (_) {
      if (widget.state.languages.isEmpty) {
        error = 'Couldn\'t load languages. Check your connection and try again.';
      }
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _continue() async {
    if (saving || widget.state.selectedLanguages.isEmpty) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      unawaited(widget.state.saveLanguages());
      widget.onContinue();
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Couldn\'t save your languages. Try again.');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: widget.onBack,
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerLeft,
                      icon: const Icon(Icons.arrow_back_rounded, size: 30),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Choose Your Languages',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontSize: 34,
                      height: 1.02,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Your choices personalize music from the backend.',
                    style: TextStyle(color: AppColors.muted, height: 1.3),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ClipRect(
              child: loading
                  ? ListView.builder(
                      padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
                      itemCount: 6,
                      itemBuilder: (_, _) =>
                          const Card(child: SizedBox(height: 58)),
                    )
                  : error != null
                  ? _Error(message: error!, retry: _load)
                  : widget.state.languages.isEmpty
                  ? _Error(
                      message: 'No languages are available right now.',
                      retry: _load,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
                      clipBehavior: Clip.hardEdge,
                      itemCount: widget.state.languages.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 9),
                      itemBuilder: (_, index) {
                        final item = widget.state.languages[index];
                        final id = '${item['id'] ?? ''}';
                        final active = widget.state.selectedLanguages.contains(
                          id,
                        );
                        return ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 78),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            tileColor: active
                                ? AppColors.orange.withValues(alpha: .08)
                                : context.hubColors.surfaceColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: active
                                    ? AppColors.orange
                                    : context.hubColors.dividerColor,
                              ),
                            ),
                            onTap: () => setState(
                              () => widget.state.toggleLanguage(id),
                            ),
                            title: Text(
                              '${item['native_name'] ?? item['name'] ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                height: 1.25,
                                fontWeight: active
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            subtitle: item['native_name'] == item['name']
                                ? null
                                : Text(
                                    '${item['name'] ?? ''}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            trailing: active
                                ? const Icon(
                                    Icons.check_circle,
                                    color: AppColors.orange,
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
            child: PillButton(
              label: saving ? 'Saving…' : 'Continue',
              onPressed: saving || widget.state.selectedLanguages.isEmpty
                  ? null
                  : _continue,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: retry, child: const Text('Retry')),
      ],
    ),
  );
}
