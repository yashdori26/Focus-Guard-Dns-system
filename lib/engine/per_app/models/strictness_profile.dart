import 'package:flutter/foundation.dart';
import 'app_lock_config.dart';
import 'friction_challenge_model.dart';

/// Comprehensive behavioral policy profile defining the resistance parameters for app locks.
@immutable
class StrictnessProfile {
  final StrictnessTier tier;
  final String title;
  final String description;
  final bool allowsEmergencyUnlock;
  final bool requiresFrictionChallenge;
  final List<FrictionChallengeType> challengeTypesAllowed;
  final int maxEmergencyUnlocksPerDay;
  final bool rebootResistant;
  final bool preventsAppUninstall;
  final bool preventsForceStop;
  final int emergencyUnlockCooldownPenaltyMinutes;

  const StrictnessProfile({
    required this.tier,
    required this.title,
    required this.description,
    required this.allowsEmergencyUnlock,
    required this.requiresFrictionChallenge,
    required this.challengeTypesAllowed,
    required this.maxEmergencyUnlocksPerDay,
    required this.rebootResistant,
    required this.preventsAppUninstall,
    required this.preventsForceStop,
    required this.emergencyUnlockCooldownPenaltyMinutes,
  });

  static const Map<StrictnessTier, StrictnessProfile> profiles = {
    StrictnessTier.flexible: StrictnessProfile(
      tier: StrictnessTier.flexible,
      title: 'Flexible Mode',
      description: 'Gentle nudges. Can be paused or disabled at any time with a single tap.',
      allowsEmergencyUnlock: true,
      requiresFrictionChallenge: false,
      challengeTypesAllowed: [],
      maxEmergencyUnlocksPerDay: 99,
      rebootResistant: false,
      preventsAppUninstall: false,
      preventsForceStop: false,
      emergencyUnlockCooldownPenaltyMinutes: 0,
    ),
    StrictnessTier.frictionProtected: StrictnessProfile(
      tier: StrictnessTier.frictionProtected,
      title: 'Friction-Protected Mode',
      description: 'Requires intentional friction: solve math equations or type a commitment oath.',
      allowsEmergencyUnlock: true,
      requiresFrictionChallenge: true,
      challengeTypesAllowed: [
        FrictionChallengeType.mindfulOathTyping,
        FrictionChallengeType.mentalMathEquations,
        FrictionChallengeType.cooldownWaitDelay,
      ],
      maxEmergencyUnlocksPerDay: 2,
      rebootResistant: true,
      preventsAppUninstall: false,
      preventsForceStop: false,
      emergencyUnlockCooldownPenaltyMinutes: 30,
    ),
    StrictnessTier.strictUnbreakable: StrictnessProfile(
      tier: StrictnessTier.strictUnbreakable,
      title: 'Strict Unbreakable Mode',
      description: 'Zero bypass. Timers and schedules cannot be stopped or cancelled by any means until they expire.',
      allowsEmergencyUnlock: false,
      requiresFrictionChallenge: false,
      challengeTypesAllowed: [],
      maxEmergencyUnlocksPerDay: 0,
      rebootResistant: true,
      preventsAppUninstall: true,
      preventsForceStop: true,
      emergencyUnlockCooldownPenaltyMinutes: 0,
    ),
    StrictnessTier.hardcoreDeviceAdmin: StrictnessProfile(
      tier: StrictnessTier.hardcoreDeviceAdmin,
      title: 'Hardcore Kiosk Mode',
      description: 'Device Administrator locked. OS settings are masked and package removal is blocked.',
      allowsEmergencyUnlock: false,
      requiresFrictionChallenge: false,
      challengeTypesAllowed: [],
      maxEmergencyUnlocksPerDay: 0,
      rebootResistant: true,
      preventsAppUninstall: true,
      preventsForceStop: true,
      emergencyUnlockCooldownPenaltyMinutes: 0,
    ),
  };

  static StrictnessProfile of(StrictnessTier tier) {
    return profiles[tier] ?? profiles[StrictnessTier.strictUnbreakable]!;
  }
}
