class LyricWord {
  const LyricWord({required this.text, required this.start, required this.end});

  final String text;
  final Duration start;
  final Duration end;

  factory LyricWord.fromJson(Map<String, dynamic> json) => LyricWord(
    text: json['text']?.toString() ?? '',
    start: Duration(milliseconds: _milliseconds(json['start_ms'])),
    end: Duration(milliseconds: _milliseconds(json['end_ms'])),
  );

  Map<String, dynamic> toJson() => {
    'text': text,
    'start_ms': start.inMilliseconds,
    'end_ms': end.inMilliseconds,
  };
}

class LyricLine {
  const LyricLine({
    required this.start,
    required this.end,
    required this.text,
    this.words = const [],
  });

  final Duration start;
  final Duration end;
  final String text;
  final List<LyricWord> words;

  factory LyricLine.fromJson(Map<String, dynamic> json) => LyricLine(
    start: Duration(milliseconds: _milliseconds(json['start_ms'])),
    end: Duration(milliseconds: _milliseconds(json['end_ms'])),
    text: json['text']?.toString() ?? '',
    words: _maps(json['words']).map(LyricWord.fromJson).toList(growable: false),
  );

  Map<String, dynamic> toJson() => {
    'start_ms': start.inMilliseconds,
    'end_ms': end.inMilliseconds,
    'text': text,
    if (words.isNotEmpty)
      'words': words.map((word) => word.toJson()).toList(growable: false),
  };
}

int _milliseconds(dynamic value) => int.tryParse(value?.toString() ?? '') ?? 0;

Iterable<Map<String, dynamic>> _maps(dynamic value) sync* {
  if (value is! List) return;
  for (final item in value) {
    if (item is Map) yield item.cast<String, dynamic>();
  }
}
