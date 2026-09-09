import 'package:flutter/foundation.dart';
import '../models.dart';

class PlayerProvider extends ChangeNotifier {
  Track? _currentTrack;
  bool _isPlaying = false;
  Duration _position = Duration.zero;

  Track? get currentTrack => _currentTrack;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;

  void play(Track track) {
    _currentTrack = track;
    _isPlaying = true;
    _position = Duration.zero;
    notifyListeners();
  }

  void togglePlayPause() {
    _isPlaying = !_isPlaying;
    notifyListeners();
  }

  void seek(Duration position) {
    _position = position;
    notifyListeners();
  }

  void next() {
    _position = Duration.zero;
    notifyListeners();
  }

  void previous() {
    _position = Duration.zero;
    notifyListeners();
  }
}
