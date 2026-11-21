import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/app_storage_service.dart';

class AllowlistNotifier extends StateNotifier<List<String>> {
  AllowlistNotifier() : super(['trusted-site.com']) {
    _initPersistence();
  }

  Future<void> _initPersistence() async {
    final saved = await AppStorageService.loadAllowlist();
    if (!mounted) return;
    if (saved != null) {
      state = saved;
    }
  }

  void add(String domain) {
    final clean = domain.trim().toLowerCase();
    if (clean.isNotEmpty && !state.contains(clean)) {
      state = [...state, clean];
      AppStorageService.saveAllowlist(state);
    }
  }

  void remove(String domain) {
    state = state.where((d) => d != domain).toList();
    AppStorageService.saveAllowlist(state);
  }
}

final allowlistProvider =
    StateNotifierProvider<AllowlistNotifier, List<String>>((ref) {
  return AllowlistNotifier();
});
