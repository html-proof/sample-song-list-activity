import 'package:flutter_test/flutter_test.dart';
import 'package:music_hub_app/features/home/data/home_repository.dart';

void main() {
  final now = DateTime.utc(2026, 8, 25, 12);
  int msAfter(Duration offset) => now.add(offset).millisecondsSinceEpoch;

  test('a feed inside the stale window is painted before revalidating', () {
    expect(
      HomeRepository.canServeStale(
        expiresAt: msAfter(const Duration(hours: -11, minutes: -59)),
        now: now,
      ),
      isTrue,
    );
  });

  test('a feed past the stale window waits for the network instead', () {
    expect(
      HomeRepository.canServeStale(
        expiresAt: msAfter(const Duration(hours: -12, minutes: -1)),
        now: now,
      ),
      isFalse,
    );
  });

  test('a backwards device clock never discards a usable feed', () {
    expect(
      HomeRepository.canServeStale(
        expiresAt: msAfter(const Duration(days: 30)),
        now: now,
      ),
      isTrue,
    );
  });
}
