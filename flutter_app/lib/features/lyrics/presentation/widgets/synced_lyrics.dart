import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_hub_app/core/providers.dart';
import 'package:music_hub_app/features/lyrics/domain/entities/lyrics.dart';
import 'package:music_hub_app/features/lyrics/presentation/controllers/lyrics_controller.dart';
import 'package:music_hub_app/features/lyrics/presentation/widgets/lyric_line.dart';

class SyncedLyrics extends ConsumerStatefulWidget {
  const SyncedLyrics({super.key, required this.lyrics, required this.accent});

  final Lyrics lyrics;
  final Color accent;

  @override
  ConsumerState<SyncedLyrics> createState() => _SyncedLyricsState();
}

class _SyncedLyricsState extends ConsumerState<SyncedLyrics> {
  static const _lineExtent = 92.0;

  final ScrollController _scrollController = ScrollController();
  var _following = true;
  var _lastActive = -2;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(currentLyricLineProvider(widget.lyrics));
    if (_following && active >= 0 && active != _lastActive) {
      _lastActive = active;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTo(active));
    }
    return Stack(
      children: [
        NotificationListener<UserScrollNotification>(
          onNotification: (notification) {
            if (notification.direction != ScrollDirection.idle && _following) {
              setState(() => _following = false);
            }
            return false;
          },
          child: ListView.builder(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.only(
              top: MediaQuery.sizeOf(context).height * 0.26,
              bottom: MediaQuery.sizeOf(context).height * 0.40,
            ),
            itemExtent: _lineExtent,
            itemCount: widget.lyrics.lines.length,
            itemBuilder: (context, index) {
              final line = widget.lyrics.lines[index];
              return LyricLineTile(
                key: ValueKey('${line.start.inMilliseconds}:$index'),
                text: line.text,
                active: index == active,
                accent: widget.accent,
                onTap: () {
                  final target = line.start + widget.lyrics.offset;
                  ref
                      .read(audioHandlerProvider)
                      .seek(target.isNegative ? Duration.zero : target);
                  setState(() => _following = true);
                  _scrollTo(index);
                },
              );
            },
          ),
        ),
        if (!_following)
          Positioned(
            right: 18,
            bottom: 20,
            child: FilledButton.icon(
              onPressed: () {
                setState(() => _following = true);
                final current = ref.read(
                  currentLyricLineProvider(widget.lyrics),
                );
                if (current >= 0) _scrollTo(current);
              },
              style: FilledButton.styleFrom(
                backgroundColor: widget.accent,
                foregroundColor: Colors.black,
              ),
              icon: const Icon(Icons.radio_button_checked_rounded, size: 16),
              label: const Text('Live'),
            ),
          ),
      ],
    );
  }

  void _scrollTo(int index) {
    if (!mounted || !_scrollController.hasClients || index < 0) return;
    final viewport = _scrollController.position.viewportDimension;
    final wanted = index * _lineExtent - viewport * 0.40;
    final target = wanted.clamp(
      _scrollController.position.minScrollExtent,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }
}
