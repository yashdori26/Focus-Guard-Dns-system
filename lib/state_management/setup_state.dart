import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backend/api_client.dart';

class SetupState {
  final String profileId;
  final String linkedIp;
  final String? currentClientIp;
  final String dohUrl;
  final String dotHostname;
  final List<String> ipv4Endpoints;
  final List<String> ipv6Endpoints;
  final bool isLoading;
  final bool isUpdatingIp;
  final String? errorMessage;

  const SetupState({
    required this.profileId,
    required this.linkedIp,
    this.currentClientIp,
    required this.dohUrl,
    required this.dotHostname,
    required this.ipv4Endpoints,
    required this.ipv6Endpoints,
    this.isLoading = false,
    this.isUpdatingIp = false,
    this.errorMessage,
  });

  bool get isMatched =>
      currentClientIp != null &&
      currentClientIp!.isNotEmpty &&
      currentClientIp == linkedIp;

  SetupState copyWith({
    String? profileId,
    String? linkedIp,
    String? currentClientIp,
    String? dohUrl,
    String? dotHostname,
    List<String>? ipv4Endpoints,
    List<String>? ipv6Endpoints,
    bool? isLoading,
    bool? isUpdatingIp,
    String? errorMessage,
  }) {
    return SetupState(
      profileId: profileId ?? this.profileId,
      linkedIp: linkedIp ?? this.linkedIp,
      currentClientIp: currentClientIp ?? this.currentClientIp,
      dohUrl: dohUrl ?? this.dohUrl,
      dotHostname: dotHostname ?? this.dotHostname,
      ipv4Endpoints: ipv4Endpoints ?? this.ipv4Endpoints,
      ipv6Endpoints: ipv6Endpoints ?? this.ipv6Endpoints,
      isLoading: isLoading ?? this.isLoading,
      isUpdatingIp: isUpdatingIp ?? this.isUpdatingIp,
      errorMessage: errorMessage,
    );
  }
}

class SetupNotifier extends StateNotifier<SetupState> {
  final FocusDnsApiClient _client;

  SetupNotifier({FocusDnsApiClient? client})
      : _client = client ?? FocusDnsApiClient(),
        super(const SetupState(
          profileId: 'a1b2c3',
          linkedIp: 'No IP linked',
          currentClientIp: null,
          dohUrl: 'https://dns.focusdns.net/dns-query/a1b2c3',
          dotHostname: 'a1b2c3.dns.focusdns.net',
          ipv4Endpoints: ['45.90.28.140', '45.90.30.140'],
          ipv6Endpoints: ['2a07:a8c0::a1b2:c3', '2a07:a8c1::a1b2:c3'],
          isLoading: false,
          isUpdatingIp: false,
        )) {
    loadSetupDetails();
  }

  Future<void> loadSetupDetails() async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final results = await Future.wait([
        _client.getSetupDetails(),
        _client.detectClientIp(),
      ]);

      final details = results[0] as Map<String, dynamic>;
      final detectedIp = results[1] as String?;

      final serverLinkedIp = details['linked_ip']?.toString();
      final serverProfileId = details['profile_id']?.toString() ?? state.profileId;
      final serverClientIp = details['client_ip']?.toString() ?? detectedIp ?? state.currentClientIp;
      final serverDoh = details['doh_endpoint']?.toString() ?? state.dohUrl;
      final serverDot = details['dot_endpoint']?.toString() ?? state.dotHostname;

      List<String> ipv4 = state.ipv4Endpoints;
      if (details['ipv4_endpoints'] is List) {
        final list = (details['ipv4_endpoints'] as List).map((e) => e.toString()).toList();
        if (list.isNotEmpty) ipv4 = list;
      }

      List<String> ipv6 = state.ipv6Endpoints;
      if (details['ipv6_endpoints'] is List) {
        final list = (details['ipv6_endpoints'] as List).map((e) => e.toString()).toList();
        if (list.isNotEmpty) ipv6 = list;
      }

      state = state.copyWith(
        profileId: serverProfileId,
        linkedIp: (serverLinkedIp != null && serverLinkedIp.isNotEmpty) ? serverLinkedIp : state.linkedIp,
        currentClientIp: serverClientIp,
        dohUrl: serverDoh,
        dotHostname: serverDot,
        ipv4Endpoints: ipv4,
        ipv6Endpoints: ipv6,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> refresh() async => loadSetupDetails();

  Future<bool> updateLinkedIp([String? targetIp]) async {
    state = state.copyWith(isUpdatingIp: true, errorMessage: null);

    final ipToLink = targetIp ?? state.currentClientIp;
    try {
      final newLinkedIp = await _client.linkIp(ipToLink);
      if (newLinkedIp != null && newLinkedIp.isNotEmpty) {
        state = state.copyWith(
          linkedIp: newLinkedIp,
          currentClientIp: (ipToLink != null && ipToLink.isNotEmpty) ? ipToLink : state.currentClientIp,
          isUpdatingIp: false,
        );
        return true;
      } else if (ipToLink != null && ipToLink.isNotEmpty) {
        // Fallback update in offline / test mode
        state = state.copyWith(
          linkedIp: ipToLink,
          isUpdatingIp: false,
        );
        return true;
      }
    } catch (e) {
      state = state.copyWith(isUpdatingIp: false, errorMessage: e.toString());
      return false;
    }

    state = state.copyWith(isUpdatingIp: false);
    return false;
  }
}

final apiClientProvider = Provider<FocusDnsApiClient>((ref) {
  return FocusDnsApiClient();
});

final setupProvider = StateNotifierProvider<SetupNotifier, SetupState>((ref) {
  return SetupNotifier(client: ref.watch(apiClientProvider));
});
