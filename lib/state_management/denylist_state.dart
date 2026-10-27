import 'package:flutter_riverpod/flutter_riverpod.dart';

class DenylistNotifier extends StateNotifier<List<String>> {
  DenylistNotifier() : super(['example.com']);

  void add(String domain) {
    final clean = domain.trim().toLowerCase();
    if (clean.isNotEmpty && !state.contains(clean)) {
      state = [...state, clean];
    }
  }

  void remove(String domain) {
    state = state.where((d) => d != domain).toList();
  }
}

final denylistProvider =
    StateNotifierProvider<DenylistNotifier, List<String>>((ref) {
  return DenylistNotifier();
});
