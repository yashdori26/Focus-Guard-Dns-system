import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focus_dns/models/app_models.dart';
import 'package:focus_dns/state_management/deep_focus_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DeepFocusProvider Category Tests', () {
    test('Initializes with empty websites and empty categories by default prior to user addition', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(deepFocusProvider);
      expect(state.websites, isEmpty);
      expect(state.categories, isEmpty);
    });

    test('addCategory and removeCategory update state and sync rules', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(deepFocusProvider.notifier);

      // Add dating
      notifier.addCategory(const BlockedItem(
        id: 'dating',
        name: 'Dating Services',
        icon: '💘',
      ));
      expect(container.read(deepFocusProvider).categories.any((c) => c.id == 'dating'), isTrue);

      // Remove dating
      notifier.removeCategory('Dating Services');
      expect(container.read(deepFocusProvider).categories.any((c) => c.id == 'dating'), isFalse);
    });
  });
}
