import 'package:flutter/foundation.dart';
import '../per_app_database.dart';

/// Comprehensive definition of a managed application in the catalog.
@immutable
class AppDefinition {
  final String id;
  final String name;
  final String primaryPackage;
  final List<String> secondaryPackages;
  final List<String> networkDomains;
  final List<String> cdnDomains;
  final AppCategory category;
  final DopamineRiskRating riskRating;
  final int dopamineScore; // 1 to 100
  final int defaultAllocatedLockMinutes;
  final int defaultDailyQuotaMinutes;
  final String iconGlyph;
  final String themeColorHex;
  final String description;
  final String? recommendedProductiveSwapId;
  final bool isExtremeTrap;

  const AppDefinition({
    required this.id,
    required this.name,
    required this.primaryPackage,
    this.secondaryPackages = const [],
    required this.networkDomains,
    this.cdnDomains = const [],
    required this.category,
    this.riskRating = DopamineRiskRating.high,
    this.dopamineScore = 80,
    this.defaultAllocatedLockMinutes = 120,
    this.defaultDailyQuotaMinutes = 30,
    required this.iconGlyph,
    this.themeColorHex = '#3B82F6',
    required this.description,
    this.recommendedProductiveSwapId,
    this.isExtremeTrap = false,
  });

  /// Converts this definition into an active ManagedAppRecord.
  ManagedAppRecord toManagedRecord({
    int? allocatedMinutes,
    int? remainingSeconds,
    bool isLocked = false,
    DateTime? targetEndTime,
  }) {
    return ManagedAppRecord(
      appId: id,
      appName: name,
      packageName: primaryPackage,
      secondaryPackages: secondaryPackages,
      networkDomains: [...networkDomains, ...cdnDomains],
      category: category,
      riskRating: riskRating,
      iconGlyph: iconGlyph,
      allocatedLockMinutes: allocatedMinutes ?? defaultAllocatedLockMinutes,
      remainingLockSeconds: remainingSeconds ?? 0,
      targetEndTime: targetEndTime,
      isLocked: isLocked,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'primaryPackage': primaryPackage,
    'secondaryPackages': secondaryPackages,
    'networkDomains': networkDomains,
    'cdnDomains': cdnDomains,
    'category': category.name,
    'riskRating': riskRating.name,
    'dopamineScore': dopamineScore,
    'defaultAllocatedLockMinutes': defaultAllocatedLockMinutes,
    'defaultDailyQuotaMinutes': defaultDailyQuotaMinutes,
    'iconGlyph': iconGlyph,
    'themeColorHex': themeColorHex,
    'description': description,
    'recommendedProductiveSwapId': recommendedProductiveSwapId,
    'isExtremeTrap': isExtremeTrap,
  };

  factory AppDefinition.fromJson(Map<String, dynamic> json) {
    return AppDefinition(
      id: json['id'] as String,
      name: json['name'] as String,
      primaryPackage: json['primaryPackage'] as String,
      secondaryPackages: (json['secondaryPackages'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      networkDomains: (json['networkDomains'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      cdnDomains: (json['cdnDomains'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      category: AppCategory.values.byName(json['category'] as String? ?? 'social'),
      riskRating: DopamineRiskRating.values.byName(json['riskRating'] as String? ?? 'high'),
      dopamineScore: (json['dopamineScore'] as num?)?.toInt() ?? 80,
      defaultAllocatedLockMinutes: (json['defaultAllocatedLockMinutes'] as num?)?.toInt() ?? 120,
      defaultDailyQuotaMinutes: (json['defaultDailyQuotaMinutes'] as num?)?.toInt() ?? 30,
      iconGlyph: json['iconGlyph'] as String? ?? '📱',
      themeColorHex: json['themeColorHex'] as String? ?? '#3B82F6',
      description: json['description'] as String? ?? '',
      recommendedProductiveSwapId: json['recommendedProductiveSwapId'] as String?,
      isExtremeTrap: json['isExtremeTrap'] as bool? ?? false,
    );
  }
}
