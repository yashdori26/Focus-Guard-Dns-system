import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/app_storage_service.dart';

class DenylistNotifier extends StateNotifier<List<String>> {
  DenylistNotifier() : super(['example.com']) {
    _initPersistence();
  }

  Future<void> _initPersistence() async {
    final saved = await AppStorageService.loadDenylist();
    if (!mounted) return;
    if (saved != null) {
      state = saved;
    }
  }

  void add(String domain) {
    final clean = domain.trim().toLowerCase();
    if (clean.isNotEmpty && !state.contains(clean)) {
      state = [...state, clean];
      AppStorageService.saveDenylist(state);
    }
  }

  void remove(String domain) {
    state = state.where((d) => d != domain).toList();
    AppStorageService.saveDenylist(state);
  }
}

final denylistProvider =
    StateNotifierProvider<DenylistNotifier, List<String>>((ref) {
  return DenylistNotifier();
});
