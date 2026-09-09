import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../app_state.dart';
import '../models.dart';
import '../services.dart';
import '../theme.dart';

class LyricsScreen extends StatefulWidget {
  const LyricsScreen({super.key, required this.state, required this.track});
  final AppState state;
  final Track track;

  @override
  State<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends State<LyricsScreen> {
  late Future<Lyrics> _future;
  final _scrollController = ScrollController();
  final List<GlobalKey> _lineKeys = [];
  bool _manualScroll = false;
  int _active = -1;

  @override
  void initState() {
    super.initState();
    _fetchLyrics();
  }

  void _fetchLyrics() {
    _future = widget.state.api.lyrics(
      widget.track.seokey.isNotEmpty ? widget.track.seokey : widget.track.id,
      title: widget.track.title,
      artist: widget.track.artist,
    );
  }

  int _lineIndex(List<LyricLine> lines, int positionMs) {
    if (lines.isEmpty) return -1;
    if (positionMs <= lines.first.startMs) {
      return 0;
    }
    var low = 0, high = lines.length - 1, result = 0;
    while (low <= high) {
      final middle = (low + high) ~/ 2;
      if (lines[middle].startMs <= positionMs) {
        result = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return result;
  }

  void _scrollToIndex(int index) {
    if (index >= 0 && index < _lineKeys.length) {
      final keyContext = _lineKeys[index].currentContext;
      if (keyContext != null) {
        Scrollable.ensureVisible(
          keyContext,
          alignment: 0.35, // Position active line comfortably at 35% from the top
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  void _returnToCurrent(List<LyricLine> lines) {
    final index = _lineIndex(
      lines,
      widget.state.player.position.inMilliseconds,
    );
    setState(() {
      _manualScroll = false;
      _active = index;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToIndex(index);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          Text(
            widget.track.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: context.hubColors.textSecondary,
            ),
          ),
        ],
      ),
    ),
    body: FutureBuilder<Lyrics>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Finding lyrics...', style: TextStyle(fontSize: 16)),
              ],
            ),
          );
        }
        if (snapshot.hasError) {
          final error =
              snapshot.error is ApiException &&
                  (snapshot.error as ApiException).statusCode == 429
              ? 'Lyrics are temporarily rate limited.'
              : 'Couldn\'t load lyrics right now.';
          return _message(error, retry: true);
        }
        final lyrics = snapshot.data!;
        if (lyrics.instrumental) {
          return _message('♪ This track is instrumental.');
        }
        if (lyrics.status == 'not_found' ||
            (!lyrics.synced && (lyrics.plainLyrics == null || lyrics.plainLyrics!.trim().isEmpty))) {
          return _message('Lyrics aren\'t available for this song.');
        }
        if (!lyrics.synced) {
          return _plainLyrics(lyrics.plainLyrics);
        }
        return AnimatedBuilder(
          animation: widget.state.player,
          builder: (_, _) => _syncedLyrics(lyrics.lines),
        );
      },
    ),
  );

  Widget _message(String text, {bool retry = false}) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lyrics_outlined, size: 54, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          if (retry) ...[
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: () => setState(_fetchLyrics),
              icon: const Icon(Icons.refresh),
              label: const Text('Search again'),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _plainLyrics(String? text) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 60),
      child: Text(
        text?.trim().isNotEmpty == true
            ? text!
            : 'Lyrics aren\'t available for this song.',
        softWrap: true,
        style: const TextStyle(fontSize: 19, height: 1.6, fontWeight: FontWeight.w500),
      ),
    ),
  );

  Widget _syncedLyrics(List<LyricLine> lines) {
    final visibleLines = lines
        .where((line) => line.text.trim().isNotEmpty)
        .toList(growable: false);
    if (visibleLines.isEmpty) {
      return _message('Lyrics aren\'t available for this song.');
    }

    while (_lineKeys.length < visibleLines.length) {
      _lineKeys.add(GlobalKey());
    }

    final index = _lineIndex(
      visibleLines,
      widget.state.player.position.inMilliseconds,
    );
    final screenHeight = MediaQuery.of(context).size.height;
    final topPadding = (screenHeight * 0.28).clamp(140.0, 280.0);
    final bottomPadding = (screenHeight * 0.45).clamp(220.0, 420.0);

    if (index != _active && !_manualScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _active = index);
        _scrollToIndex(index);
      });
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        NotificationListener<UserScrollNotification>(
          onNotification: (notification) {
            if (notification.direction != ScrollDirection.idle &&
                !_manualScroll &&
                mounted) {
              setState(() => _manualScroll = true);
            }
            return false;
          },
          child: ListView.builder(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              20,
              topPadding,
              20,
              bottomPadding,
            ),
            itemCount: visibleLines.length,
            itemBuilder: (context, i) {
              final isCurrent = i == _active;
              return Container(
                key: _lineKeys[i],
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    widget.state.player.seek(
                      Duration(milliseconds: visibleLines[i].startMs),
                    );
                    setState(() {
                      _manualScroll = false;
                      _active = i;
                    });
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _scrollToIndex(i);
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: isCurrent
                          ? (isDark
                              ? Colors.white.withValues(alpha: 0.12)
                              : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.50))
                          : Colors.transparent,
                    ),
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      style: TextStyle(
                        fontSize: isCurrent ? 24 : 18,
                        height: 1.4,
                        fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                        color: isCurrent
                            ? (isDark ? Colors.white : Theme.of(context).colorScheme.primary)
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.65)
                                : context.hubColors.textPrimary.withValues(alpha: 0.60)),
                      ),
                      child: Text(
                        visibleLines[i].text.trim(),
                        softWrap: true,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (_manualScroll && index >= 0)
          Positioned(
            bottom: MediaQuery.viewPaddingOf(context).bottom + 16,
            left: 24,
            right: 24,
            child: Center(
              child: FilledButton.icon(
                onPressed: () => _returnToCurrent(visibleLines),
                icon: const Icon(Icons.my_location),
                label: const Text('Return to current lyric'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
