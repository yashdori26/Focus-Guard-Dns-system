import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backend/blocker_service.dart';
import '../models/app_models.dart';

import '../backend/vpn_service.dart';
import '../services/app_storage_service.dart';

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
  static const Map<String, List<String>> _appDomains = {
    'youtube': [
      'youtube.com',
      'youtu.be',
      'googlevideo.com',
      'ytimg.com',
      'youtubei.googleapis.com',
      'yt3.ggpht.com',
      'yt4.ggpht.com',
      'youtube-nocookie.com',
      'youtubekids.com',
      'yt.be',
      'gvt1.com',
      'wide-youtube.l.google.com',
    ],
    'instagram': [
      'instagram.com',
      'cdninstagram.com',
      'ig.me',
      'fbcdn.net',
      'facebook.com',
      'facebook.net',
      'fbsbx.com',
      'meta.com',
      'threads.net',
      'threads.com',
      'igsonar.com',
      'tfbnw.net',
      'accountkit.com',
    ],
    'facebook': [
      'facebook.com',
      'fb.com',
      'fbcdn.net',
      'fbsbx.com',
      'messenger.com',
      'm.me',
      'meta.com',
      'facebook.net',
      'tfbnw.net',
      'fb.watch',
      'workplace.com',
    ],
    'tiktok': [
      'tiktok.com',
      'tiktokv.com',
      'tiktokcdn.com',
      'tiktokcdn-eu.com',
      'tiktokcdn-us.com',
      'byteoversea.com',
      'byteoversea.net',
      'ibytedtos.com',
      'ibyteimg.com',
      'musical.ly',
      'bytedance.com',
      'bytedapm.com',
      'bytefcdn.com',
      'ttwstatic.com',
      'snssdk.com',
      'sgpstatp.com',
    ],
    'snapchat': [
      'snapchat.com',
      'sc-cdn.net',
      'snap-dev.net',
      'snapkit.com',
      'sc-analytics.com',
      'snapads.com',
      'bitmoji.com',
      'feelprivacy.com',
      'story.snapchat.com',
    ],
    'twitter': [
      'twitter.com',
      'x.com',
      'twimg.com',
      't.co',
      'periscope.tv',
      'pscp.tv',
      'tweetdeck.com',
      'cms-twdigitalassets.com',
    ],
    'x': [
      'twitter.com',
      'x.com',
      'twimg.com',
      't.co',
      'periscope.tv',
      'pscp.tv',
      'tweetdeck.com',
      'cms-twdigitalassets.com',
    ],
    'reddit': [
      'reddit.com',
      'redd.it',
      'redditmedia.com',
      'redditstatic.com',
      'redditmail.com',
      'preview.redd.it',
      'v.redd.it',
      'i.redd.it',
    ],
    'whatsapp': [
      'whatsapp.com',
      'whatsapp.net',
      'wa.me',
      'whatsapp.org',
    ],
    'telegram': [
      'telegram.org',
      'telegram.me',
      't.me',
      'tdesktop.com',
      'telesco.pe',
    ],
    'spotify': [
      'spotify.com',
      'scdn.co',
      'spoti.fi',
      'spotifycdn.com',
      'spotifycdn.net',
      'audio-ak-spotify-com.akamaized.net',
    ],
    'netflix': [
      'netflix.com',
      'nflxvideo.net',
      'nflximg.net',
      'nflxext.com',
      'nflxso.net',
    ],
    'primevideo': [
      'primevideo.com',
      'amazonvideo.com',
      'aiv-cdn.net',
      'aiv-delivery.net',
      'pv-cdn.net',
    ],
    'amazon': [
      'primevideo.com',
      'amazonvideo.com',
      'aiv-cdn.net',
      'aiv-delivery.net',
      'pv-cdn.net',
    ],
    'hotstar': [
      'disneyplus.com',
      'disney-plus.net',
      'dssott.com',
      'bamgrid.com',
      'hotstar.com',
      'hotstar.net',
    ],
    'disney': [
      'disneyplus.com',
      'disney-plus.net',
      'dssott.com',
      'bamgrid.com',
      'hotstar.com',
      'hotstar.net',
    ],
    'twitch': [
      'twitch.tv',
      'ttvnw.net',
      'jtvnw.net',
    ],
    'discord': [
      'discord.com',
      'discord.gg',
      'discordapp.com',
      'discordapp.net',
      'discord.media',
      'discordstatus.com',
    ],
    'roblox': [
      'roblox.com',
      'rbxcdn.com',
      'robloxlabs.com',
    ],
    'pinterest': [
      'pinterest.com',
      'pinimg.com',
    ],
    'linkedin': [
      'linkedin.com',
      'licdn.com',
    ],
    'steam': [
      'steampowered.com',
      'steamcommunity.com',
      'steamstatic.com',
    ],
    'xbox': [
      'xbox.com',
      'xboxlive.com',
    ],
  };

  static const Map<String, List<String>> _categoryDomains = {
    'porn': [
      'pornhub.com',
      'xvideos.com',
      'xnxx.com',
      'xhamster.com',
      'stripchat.com',
      'chaturbate.com',
      'onlyfans.com',
      'redtube.com',
      'youporn.com',
      'spankbang.com',
      'erome.com',
      'livejasmin.com',
      'camsoda.com',
      'brazzers.com',
      'beeg.com',
      'eporner.com',
      'hqporner.com',
      'txxx.com',
      'tube8.com',
      'adultfriendfinder.com',
      'bonga.com',
      'bongacams.com',
      'fapello.com',
      'cam4.com',
      'rule34.xxx',
      'gelbooru.com',
      'danbooru.donmai.us',
      'e-hentai.org',
      'nhentai.net',
      'tnaflix.com',
      'redgifs.com',
    ],
    'social': [
      'facebook.com',
      'fbcdn.net',
      'instagram.com',
      'cdninstagram.com',
      'tiktok.com',
      'tiktokv.com',
      'twitter.com',
      'x.com',
      'twimg.com',
      'reddit.com',
      'redd.it',
      'redditmedia.com',
      'snapchat.com',
      'pinterest.com',
      'linkedin.com',
      'threads.net',
      'tumblr.com',
    ],
    'gaming': [
      'roblox.com',
      'rbxcdn.com',
      'epicgames.com',
      'steampowered.com',
      'steamcommunity.com',
      'ea.com',
      'riotgames.com',
      'playstation.com',
      'playstation.net',
      'xboxlive.com',
      'xbox.com',
      'blizzard.com',
      'battle.net',
      'supercell.com',
    ],
    'dating': [
      'tinder.com',
      'bumble.com',
      'hinge.co',
      'match.com',
      'okcupid.com',
      'badoo.com',
      'grindr.com',
      'pure.app',
      'pof.com',
      'zoosk.com',
    ],
    'gambling': [
      'bet365.com',
      'pokerstars.com',
      'draftkings.com',
      'fanduel.com',
      'betfair.com',
      '888poker.com',
      'stake.com',
      'bovada.lv',
      'casino.com',
      '1xbet.com',
    ],
    'piracy': [
      'thepiratebay.org',
      '1337x.to',
      'rarbg.to',
      'yts.mx',
      'fitgirl-repacks.site',
      'torrentz2.eu',
      'fmovies.to',
      'fmoviesz.to',
      'nyaa.si',
      'rutracker.org',
    ],
    'video': [
      'youtube.com',
      'googlevideo.com',
      'ytimg.com',
      'youtubei.googleapis.com',
      'netflix.com',
      'nflxvideo.net',
      'disneyplus.com',
      'hulu.com',
      'primevideo.com',
      'twitch.tv',
      'ttvnw.net',
      'vimeo.com',
      'kick.com',
    ],
  };

  static const Map<String, List<String>> _categoryPackages = {
    'social': [
      'com.instagram.android',
      'com.zhiliaoapp.musically',
      'com.ss.android.ugc.trill',
      'com.facebook.katana',
      'com.twitter.android',
      'com.snapchat.android',
      'com.reddit.frontpage',
      'com.pinterest',
    ],
    'gaming': [
      'com.roblox.client',
      'com.epicgames.portal',
      'com.valvesoftware.android.steam.community',
      'com.supercell.clashofclans',
      'com.supercell.brawlstars',
      'com.dts.freefireth',
      'com.tencent.ig',
    ],
    'dating': [
      'com.tinder',
      'com.bumble.app',
      'co.hinge.app',
      'com.okcupid.okcupid',
      'com.grindr.android',
      'com.badoo.mobile',
    ],
    'video': [
      'com.google.android.youtube',
      'com.netflix.mediaclient',
      'tv.twitch.android.app',
    ],
    'gambling': [
      'com.winzo.gold',
      'com.mpl.androidapp',
      'com.rummycircle.android',
      'com.dream11.app',
      'com.myteam11.app',
    ],
    'piracy': [
      'com.bittorrent.client',
      'com.utorrent.client',
    ],
    'porn': [
      'org.torproject.torbrowser',
      'org.torproject.torbrowser_alpha',
    ],
  };

  DeepFocusNotifier()
      : super(const DeepFocusState(
          websites: [],
          categories: [],
        )) {
    _initPersistenceAndSync();
  }

  Future<void> _initPersistenceAndSync() async {
    final savedWebsites = await AppStorageService.loadBlockedWebsites();
    final savedCategories = await AppStorageService.loadBlockedCategories();

    if (!mounted) return;

    state = state.copyWith(
      websites: savedWebsites ?? const [],
      categories: savedCategories ?? const [],
    );
    syncWithBlocker();
  }

  void _persistState() {
    AppStorageService.saveBlockedWebsites(state.websites);
    AppStorageService.saveBlockedCategories(state.categories);
  }

  void syncWithBlocker() {
    final allPackages = <String>{};
    final allDomains = <String>{};

    for (final site in state.websites) {
      allPackages.addAll(site.packages);
      final siteId = site.id.toLowerCase();
      final siteName = site.name.toLowerCase();
      if (_appDomains.containsKey(siteId)) {
        allDomains.addAll(_appDomains[siteId]!);
      } else if (_appDomains.containsKey(siteName)) {
        allDomains.addAll(_appDomains[siteName]!);
      }
      for (final entry in _appDomains.entries) {
        if (siteId.contains(entry.key) || siteName.contains(entry.key)) {
          allDomains.addAll(entry.value);
        }
      }
      for (final pkg in site.packages) {
        final pkgLower = pkg.toLowerCase();
        if (_appDomains.containsKey(pkgLower)) {
          allDomains.addAll(_appDomains[pkgLower]!);
        }
        for (final entry in _appDomains.entries) {
          if (pkgLower.contains(entry.key)) {
            allDomains.addAll(entry.value);
          }
        }
      }
      if (site.id.contains('.') && !site.id.contains(' ') && !site.id.startsWith('com.')) {
        allDomains.add(site.id.toLowerCase());
      }
      if (site.name.contains('.') && !site.name.contains(' ') && !site.name.startsWith('com.')) {
        allDomains.add(site.name.toLowerCase());
      }
    }

    for (final cat in state.categories) {
      allPackages.addAll(cat.packages);
      final catId = cat.id.toLowerCase();
      if (_categoryDomains.containsKey(catId)) {
        allDomains.addAll(_categoryDomains[catId]!);
      }
      if (_categoryPackages.containsKey(catId)) {
        allPackages.addAll(_categoryPackages[catId]!);
      }
    }

    final categoryIds = state.categories.map((c) => c.id.toLowerCase()).toList();

    FocusDnsBlockerManager.setBlockedPackages(allPackages.toList(), source: 'deepfocus');
    FocusDnsBlockerManager.setBlockedCategories(categoryIds);
    FocusDnsVpnManager.updateDnsRules(source: 'deepfocus', 
      blockedDomains: allDomains.toList(),
      allowedDomains: [],
      blockedCategories: categoryIds,
    );
  }

  void addWebsite(BlockedItem item) {
    if (!state.websites.any((w) =>
        w.name.toLowerCase() == item.name.toLowerCase() ||
        (item.packages.isNotEmpty && w.packages.any((p) => item.packages.contains(p))))) {
      state = state.copyWith(websites: [...state.websites, item]);
      _persistState();
      syncWithBlocker();
    }
  }

  void addWebsitesBulk(List<BlockedItem> items) {
    final updated = List<BlockedItem>.from(state.websites);
    for (final item in items) {
      if (!updated.any((w) =>
          w.name.toLowerCase() == item.name.toLowerCase() ||
          (item.packages.isNotEmpty && w.packages.any((p) => item.packages.contains(p))))) {
        updated.add(item);
      }
    }
    state = state.copyWith(websites: updated);
    _persistState();
    syncWithBlocker();
  }

  void removeWebsite(String name) {
    state = state.copyWith(
      websites: state.websites.where((w) => w.name != name).toList(),
    );
    _persistState();
    syncWithBlocker();
  }

  void addCategory(BlockedItem item) {
    if (!state.categories.any((c) => c.name == item.name)) {
      state = state.copyWith(categories: [...state.categories, item]);
      _persistState();
      syncWithBlocker();
    }
  }

  void removeCategory(String name) {
    state = state.copyWith(
      categories: state.categories.where((c) => c.name != name).toList(),
    );
    _persistState();
    syncWithBlocker();
  }
}


final deepFocusProvider =
    StateNotifierProvider<DeepFocusNotifier, DeepFocusState>((ref) {
  return DeepFocusNotifier();
});
