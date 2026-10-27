import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backend/blocker_service.dart';
import '../models/app_models.dart';

class DeepFocusState {
  final List<BlockedItem> websites;
  final List<BlockedItem> categories;

  const DeepFocusState({
    required this.websites,
    required this.categories,
  });

  DeepFocusState copyWith({
    List<BlockedItem>? websites,
    List<BlockedItem>? categories,
  }) {
    return DeepFocusState(
      websites: websites ?? this.websites,
      categories: categories ?? this.categories,
    );
  }
}

class DeepFocusNotifier extends StateNotifier<DeepFocusState> {
  DeepFocusNotifier()
      : super(const DeepFocusState(
          websites: [
            BlockedItem(
              id: 'reddit',
              name: 'Reddit',
              icon: 'R',
              color: Color(0xFFEA580C),
              packages: [
                'com.reddit.frontpage',
                'com.laurencedawson.reddit_sync',
                'com.rubenmayayo.reddit',
                'ml.docilealligator.infinityforreddit',
              ],
            ),
          ],
          categories: [
            BlockedItem(
              id: 'piracy',
              name: 'Piracy',
              description:
                  'Blocks P2P websites, protocols, and illegal streaming.',
            ),
            BlockedItem(
              id: 'gambling',
              name: 'Gambling',
              description: 'Blocks all online gambling and betting websites.',
            ),
          ],
        )) {
    syncWithBlocker();
  }

  void syncWithBlocker() {
    final allPackages = <String>{};
    for (final site in state.websites) {
      allPackages.addAll(site.packages);
    }
    FocusDnsBlockerManager.setBlockedPackages(allPackages.toList());
  }

  void addWebsite(BlockedItem item) {
    if (!state.websites.any((w) => w.name == item.name)) {
      state = state.copyWith(websites: [...state.websites, item]);
      syncWithBlocker();
    }
  }

  void removeWebsite(String name) {
    state = state.copyWith(
      websites: state.websites.where((w) => w.name != name).toList(),
    );
    syncWithBlocker();
  }

  void addCategory(BlockedItem item) {
    if (!state.categories.any((c) => c.name == item.name)) {
      state = state.copyWith(categories: [...state.categories, item]);
    }
  }

  void removeCategory(String name) {
    state = state.copyWith(
      categories: state.categories.where((c) => c.name != name).toList(),
    );
  }
}

final deepFocusProvider =
    StateNotifierProvider<DeepFocusNotifier, DeepFocusState>((ref) {
  return DeepFocusNotifier();
});
