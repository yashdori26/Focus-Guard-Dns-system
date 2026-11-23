import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backend/blocker_service.dart';

class BlockerState {
  final bool isEnabled;
  final bool isLoading;

  const BlockerState({
    this.isEnabled = false,
    this.isLoading = false,
  });

  BlockerState copyWith({
    bool? isEnabled,
    bool? isLoading,
  }) {
    return BlockerState(
      isEnabled: isEnabled ?? this.isEnabled,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class BlockerNotifier extends StateNotifier<BlockerState> {
  BlockerNotifier() : super(const BlockerState()) {
    checkStatus();
  }

  Future<void> checkStatus() async {
    state = state.copyWith(isLoading: true);
    final enabled = await FocusDnsBlockerManager.isAccessibilityServiceEnabled();
    if (!mounted) return;
    state = state.copyWith(isEnabled: enabled, isLoading: false);
  }

  Future<void> openSettings() async {
    await FocusDnsBlockerManager.openAccessibilitySettings();
    if (!mounted) return;
    await checkStatus();
  }

  Future<void> openAppSettings() async {
    await FocusDnsBlockerManager.openAppSettings();
  }

  Future<void> syncRules({
    required List<String> packages,
    required bool isStrictMode,
  }) async {
    await FocusDnsBlockerManager.syncRules(
      packages: packages,
      isStrictMode: isStrictMode,
    );
  }
}

final blockerProvider = StateNotifierProvider<BlockerNotifier, BlockerState>((ref) {
  return BlockerNotifier();
});
