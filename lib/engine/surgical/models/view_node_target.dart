import 'package:flutter/foundation.dart';

/// Action performed by the accessibility sentinel when a matching sub-feature view is encountered.
enum ViewInterceptionAction {
  /// Silently navigates backwards to the previous screen.
  navigateBack,

  /// Navigates directly to the root home screen.
  navigateToHome,

  /// Redirects the user directly to the app's messaging or chat tab.
  redirectToDirectMessages,

  /// Presents a floating mindful interstitial nudge overlay.
  showMindfulNudge,

  /// Closes the application completely (dispatches GLOBAL_ACTION_HOME).
  killToHome,
}

/// Target criteria for identifying native Android view hierarchy nodes.
@immutable
class ViewNodeTarget {
  final String targetId;
  final String packageName;
  final List<String> resourceIdPatterns;
  final List<String> contentDescriptionPatterns;
  final List<String> textPatterns;
  final List<String> classNamePatterns;
  final ViewInterceptionAction defaultAction;
  final String description;

  const ViewNodeTarget({
    required this.targetId,
    required this.packageName,
    this.resourceIdPatterns = const [],
    this.contentDescriptionPatterns = const [],
    this.textPatterns = const [],
    this.classNamePatterns = const [],
    this.defaultAction = ViewInterceptionAction.navigateBack,
    required this.description,
  });

  bool matches({
    required String pkg,
    String? resourceId,
    String? contentDescription,
    String? text,
    String? className,
  }) {
    if (pkg != packageName) return false;

    if (resourceId != null && resourceIdPatterns.isNotEmpty) {
      final resLower = resourceId.toLowerCase();
      if (resourceIdPatterns.any((p) => resLower.contains(p.toLowerCase()))) {
        return true;
      }
    }

    if (contentDescription != null && contentDescriptionPatterns.isNotEmpty) {
      final descLower = contentDescription.toLowerCase();
      if (contentDescriptionPatterns.any((p) => descLower.contains(p.toLowerCase()))) {
        return true;
      }
    }

    if (text != null && textPatterns.isNotEmpty) {
      final textLower = text.toLowerCase();
      if (textPatterns.any((p) => textLower.contains(p.toLowerCase()))) {
        return true;
      }
    }

    if (className != null && classNamePatterns.isNotEmpty) {
      final classLower = className.toLowerCase();
      if (classNamePatterns.any((p) => classLower.contains(p.toLowerCase()))) {
        return true;
      }
    }

    return false;
  }

  Map<String, dynamic> toJson() => {
        'targetId': targetId,
        'packageName': packageName,
        'resourceIdPatterns': resourceIdPatterns,
        'contentDescriptionPatterns': contentDescriptionPatterns,
        'textPatterns': textPatterns,
        'classNamePatterns': classNamePatterns,
        'defaultAction': defaultAction.name,
        'description': description,
      };

  factory ViewNodeTarget.fromJson(Map<String, dynamic> json) => ViewNodeTarget(
        targetId: json['targetId'] as String,
        packageName: json['packageName'] as String,
        resourceIdPatterns: List<String>.from(json['resourceIdPatterns'] as List? ?? []),
        contentDescriptionPatterns: List<String>.from(json['contentDescriptionPatterns'] as List? ?? []),
        textPatterns: List<String>.from(json['textPatterns'] as List? ?? []),
        classNamePatterns: List<String>.from(json['classNamePatterns'] as List? ?? []),
        defaultAction: ViewInterceptionAction.values.firstWhere(
          (a) => a.name == json['defaultAction'],
          orElse: () => ViewInterceptionAction.navigateBack,
        ),
        description: json['description'] as String? ?? '',
      );
}
