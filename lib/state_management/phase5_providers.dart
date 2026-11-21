import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../engine/analytics/analytics_persistence_store.dart';
import '../engine/profile/accountability_partner_manager.dart';
import '../engine/profile/cross_device_sync_coordinator.dart';
import '../engine/profile/user_profile_model.dart';

/// Provider for the Longitudinal Analytics Persistence Store
final analyticsStoreFutureProvider = FutureProvider<AnalyticsPersistenceStore>((ref) async {
  return await AnalyticsPersistenceStore.create();
});

/// Provider for the Accountability Partner Manager
final partnerManagerFutureProvider = FutureProvider<AccountabilityPartnerManager>((ref) async {
  return await AccountabilityPartnerManager.create();
});

/// Provider for Cross-Device Sync Coordinator (singleton per app session)
final syncCoordinatorProvider = Provider<CrossDeviceSyncCoordinator>((ref) {
  final coordinator = CrossDeviceSyncCoordinator(
    userId: 'usr_master_warrior',
    localDeviceId: 'dev_android_prime',
  );
  coordinator.start();
  ref.onDispose(() => coordinator.dispose());
  return coordinator;
});

/// StateNotifier for the User Profile Model
class UserProfileNotifier extends StateNotifier<UserProfileModel> {
  UserProfileNotifier() : super(UserProfileModel.initial(displayName: 'Focus Pioneer'));

  void updateProfile(UserProfileModel updated) {
    state = updated;
  }

  void setArchetype(FocusArchetype archetype) {
    state = state.copyWith(archetype: archetype);
  }

  void toggleStrictAntiUninstall(bool enabled) {
    state = state.copyWith(strictAntiUninstallEnabled: enabled);
  }

  void toggleBiometrics(bool enabled) {
    state = state.copyWith(biometricUnlockRequired: enabled);
  }

  void togglePartnerSignoff(bool enabled) {
    state = state.copyWith(emergencyPartnerRequired: enabled);
  }
}

final userProfileProvider = StateNotifierProvider<UserProfileNotifier, UserProfileModel>((ref) {
  return UserProfileNotifier();
});
