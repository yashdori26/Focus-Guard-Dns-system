import 'package:flutter_riverpod/flutter_riverpod.dart';

class AllowlistNotifier extends StateNotifier<List<String>> {
  AllowlistNotifier() : super(['trusted-site.com']);

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

final allowlistProvider =
    StateNotifierProvider<AllowlistNotifier, List<String>>((ref) {
  return AllowlistNotifier();
});
