import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_hub_app/core/providers.dart';
import 'package:music_hub_app/features/library/data/library_repository.dart';

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return LibraryRepository(ref.watch(apiClientProvider));
});

final libraryControllerProvider =
    StateNotifierProvider<LibraryController, AsyncValue<LibraryData>>((ref) {
      return LibraryController(ref.watch(libraryRepositoryProvider))..load();
    });

class LibraryController extends StateNotifier<AsyncValue<LibraryData>> {
  LibraryController(this._repository) : super(const AsyncLoading());

  final LibraryRepository _repository;

  Future<void> load() async {
    state = await AsyncValue.guard(_repository.load);
  }

  Future<void> createPlaylist(String name, String? description) async {
    await _repository.createPlaylist(name, description);
    await load();
  }
}
