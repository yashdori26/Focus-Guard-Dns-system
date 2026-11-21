import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_audit_models.dart';
import '../models/app_models.dart';
import '../services/app_audit_scanner_service.dart';
import 'deep_focus_state.dart';

class AppAuditState {
  final bool isScanning;
  final DeviceAuditReport? report;
  final Set<String> selectedPackages;
  final String activeFilter; // 'all', 'social', 'video', 'gaming', 'playstore'
  final String? errorMessage;

  const AppAuditState({
    this.isScanning = false,
    this.report,
    this.selectedPackages = const {},
    this.activeFilter = 'all',
    this.errorMessage,
  });

  AppAuditState copyWith({
    bool? isScanning,
    DeviceAuditReport? report,
    Set<String>? selectedPackages,
    String? activeFilter,
    String? errorMessage,
  }) {
    return AppAuditState(
      isScanning: isScanning ?? this.isScanning,
      report: report ?? this.report,
      selectedPackages: selectedPackages ?? this.selectedPackages,
      activeFilter: activeFilter ?? this.activeFilter,
      errorMessage: errorMessage,
    );
  }

  List<AuditedApp> get filteredApps {
    if (report == null) return [];
    var list = report!.playStoreUserApps;
    if (activeFilter == 'all') {
      return list;
    } else if (activeFilter == 'distractions') {
      return list.where((a) => a.isDistraction).toList();
    } else if (activeFilter == 'social') {
      return list.where((a) => a.category == 'social').toList();
    } else if (activeFilter == 'video') {
      return list.where((a) => a.category == 'video').toList();
    } else if (activeFilter == 'gaming') {
      return list.where((a) => a.category == 'gaming').toList();
    }
    return list;
  }
}

class AppAuditNotifier extends StateNotifier<AppAuditState> {
  final Ref _ref;

  AppAuditNotifier(this._ref) : super(const AppAuditState());

  /// Initiates comprehensive device application scan
  Future<void> runScan() async {
    state = state.copyWith(isScanning: true, errorMessage: null);
    try {
      final report = await AppAuditScannerService.scanDevice();
      // Pre-select all detected Play Store distracting apps
      final preSelected = report.playStoreDistractions.map((a) => a.packageName).toSet();
      state = state.copyWith(
        isScanning: false,
        report: report,
        selectedPackages: preSelected,
      );
    } catch (e) {
      state = state.copyWith(
        isScanning: false,
        errorMessage: 'Failed to complete device scan: $e',
      );
    }
  }

  void toggleAppSelection(String packageName) {
    final updated = Set<String>.from(state.selectedPackages);
    if (updated.contains(packageName)) {
      updated.remove(packageName);
    } else {
      updated.add(packageName);
    }
    state = state.copyWith(selectedPackages: updated);
  }

  void setFilter(String filter) {
    state = state.copyWith(activeFilter: filter);
  }

  void selectAll() {
    if (state.report == null) return;
    final allPkgs = state.filteredApps.map((a) => a.packageName).toSet();
    state = state.copyWith(selectedPackages: allPkgs);
  }

  void deselectAll() {
    state = state.copyWith(selectedPackages: const {});
  }

  /// 1-Tap Block All Selected Distractions
  int oneTapBlockSelectedDistractions() {
    if (state.report == null || state.selectedPackages.isEmpty) return 0;

    final blockedItems = <BlockedItem>[];
    for (final app in state.report!.apps) {
      if (state.selectedPackages.contains(app.packageName)) {
        final iconLetter = app.appName.trim().isNotEmpty ? app.appName.trim()[0].toUpperCase() : 'A';
        blockedItems.add(
          BlockedItem(
            id: app.packageName,
            name: app.appName,
            icon: iconLetter,
            color: app.categoryColor,
            packages: [app.packageName],
          ),
        );
      }
    }

    if (blockedItems.isNotEmpty) {
      _ref.read(deepFocusProvider.notifier).addWebsitesBulk(blockedItems);
    }

    return blockedItems.length;
  }
}

final appAuditProvider = StateNotifierProvider<AppAuditNotifier, AppAuditState>((ref) {
  return AppAuditNotifier(ref);
});
