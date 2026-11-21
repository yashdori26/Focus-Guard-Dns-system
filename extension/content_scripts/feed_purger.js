/**
 * FocusDNS - Enterprise Content Purger & Surgical DOM Decoupler
 * Runs at document_start to surgically eliminate doomscroll feeds, algorithmic
 * recommendations, Shorts, and Reels while keeping essential communication
 * (DMs, messaging, technical subreddits, educational video lectures) functional.
 */

'use strict';

(function () {
  const HOSTNAME = window.location.hostname.toLowerCase();
  const PATHNAME = window.location.pathname.toLowerCase();

  let isPurgingActive = true;
  let surgicalSettings = {
    instagram: { feed: true, reels: true, explore: true },
    youtube: { homepage: true, shorts: true, recommendations: true },
    reddit: { homeFeed: true, popular: true, infiniteScroll: true },
    twitter: { forYou: true, trends: true },
    linkedin: { feed: true, news: true },
    tiktok: { fyp: true }
  };

  let distractionCounter = 0;
  let observer = null;
  let isMutationPending = false;

  /* =========================================================================
   * 1. INITIALIZATION & BACKGROUND SETTINGS SYNC
   * ========================================================================= */

  function init() {
    // Request active settings from background service worker
    chrome.runtime.sendMessage({ action: 'GET_STATUS' }, (response) => {
      if (chrome.runtime.lastError || !response || !response.state) {
        console.warn('[FocusDNS Purger] Background worker offline. Using safe defaults.');
        startObserver();
        return;
      }

      isPurgingActive = response.state.isProtectionActive;
      if (response.state.surgicalSettings) {
        surgicalSettings = response.state.surgicalSettings;
      }

      if (isPurgingActive) {
        applyEarlyPathRedirects();
        startObserver();
      }
    });

    // Listen for runtime updates
    chrome.runtime.onMessage.addListener((msg) => {
      if (msg.action === 'STATE_CHANGED' && msg.state) {
        isPurgingActive = msg.state.isProtectionActive;
        if (msg.state.surgicalSettings) {
          surgicalSettings = msg.state.surgicalSettings;
        }
        if (isPurgingActive) {
          executeSurgicalDissection();
        }
      }
    });
  }

  /* =========================================================================
   * 2. EARLY PATH-LEVEL REDIRECTS (Zero-Latency Navigation Shield)
   * ========================================================================= */

  function applyEarlyPathRedirects() {
    // YouTube Shorts -> Subscription feed or Watch
    if (HOSTNAME.includes('youtube.com') && PATHNAME.startsWith('/shorts/') && surgicalSettings.youtube.shorts) {
      console.info('[FocusDNS] YouTube Shorts intercepted. Redirecting to intentional Subscriptions.');
      window.location.replace('https://www.youtube.com/feed/subscriptions');
      return;
    }

    // Instagram Reels / Explore -> Direct Messages
    if (HOSTNAME.includes('instagram.com') && surgicalSettings.instagram.reels) {
      if (PATHNAME.startsWith('/reels/') || PATHNAME.startsWith('/explore/')) {
        console.info('[FocusDNS] Instagram Reels/Explore intercepted. Redirecting to Direct Messages.');
        window.location.replace('https://www.instagram.com/direct/inbox/');
        return;
      }
    }

    // Reddit Popular / All -> Technical community or Search
    if (HOSTNAME.includes('reddit.com') && surgicalSettings.reddit.popular) {
      if (PATHNAME === '/r/all' || PATHNAME === '/r/all/' || PATHNAME === '/r/popular' || PATHNAME === '/r/popular/') {
        console.info('[FocusDNS] Reddit All/Popular intercepted. Redirecting to r/programming.');
        window.location.replace('https://www.reddit.com/r/programming/');
        return;
      }
    }
  }

  /* =========================================================================
   * 3. DOM MUTATION OBSERVER & SURGICAL DISSECTION ENGINE
   * ========================================================================= */

  function startObserver() {
    if (observer) observer.disconnect();

    executeSurgicalDissection();

    observer = new MutationObserver(() => {
      if (!isMutationPending) {
        isMutationPending = true;
        window.requestAnimationFrame(() => {
          executeSurgicalDissection();
          isMutationPending = false;
        });
      }
    });

    observer.observe(document.documentElement, {
      childList: true,
      subtree: true
    });
  }

  function executeSurgicalDissection() {
    if (!isPurgingActive) return;

    if (HOSTNAME.includes('youtube.com')) {
      dissectYouTube();
    } else if (HOSTNAME.includes('instagram.com')) {
      dissectInstagram();
    } else if (HOSTNAME.includes('reddit.com')) {
      dissectReddit();
    } else if (HOSTNAME.includes('twitter.com') || HOSTNAME.includes('x.com')) {
      dissectTwitterX();
    } else if (HOSTNAME.includes('linkedin.com')) {
      dissectLinkedIn();
    } else if (HOSTNAME.includes('tiktok.com')) {
      dissectTikTok();
    }
  }

  /* =========================================================================
   * 4. PLATFORM-SPECIFIC SURGICAL PURGERS
   * ========================================================================= */

  /**
   * YouTube: Purges Shorts, Homepage Browse Grid, and Recommendations Sidebar.
   * Keeps Search Bar, Lectures, Course Videos, and Active Player intact.
   */
  function dissectYouTube() {
    // 1. Shorts items anywhere in feeds
    if (surgicalSettings.youtube.shorts) {
      const shortsSelectors = [
        'ytd-rich-shelf-renderer[is-shorts]',
        'ytd-reel-shelf-renderer',
        'ytd-rich-item-renderer:has(a[href*="/shorts/"])',
        'ytd-grid-video-renderer:has(a[href*="/shorts/"])',
        'ytd-video-renderer:has(a[href*="/shorts/"])',
        'a#endpoint[title="Shorts"]',
        'ytd-mini-guide-entry-renderer[aria-label="Shorts"]'
      ];

      for (const sel of shortsSelectors) {
        document.querySelectorAll(sel).forEach((el) => {
          removeAndCount(el, 'YouTube Shorts shelf/link');
        });
      }
    }

    // 2. Homepage Feed replacement (Leave intentional search intact)
    if (surgicalSettings.youtube.homepage && (PATHNAME === '/' || PATHNAME === '')) {
      const browseFeed = document.querySelector('ytd-browse[page-subtype="home"] #contents');
      if (browseFeed && !document.getElementById('focusdns-yt-mindful-banner')) {
        browseFeed.style.display = 'none';
        injectYouTubeMindfulBanner(browseFeed.parentElement);
      }
    }

    // 3. Watch page recommendations sidebar
    if (surgicalSettings.youtube.recommendations && PATHNAME.includes('/watch')) {
      const related = document.querySelector('#related');
      if (related && related.style.display !== 'none') {
        related.style.display = 'none';
        injectMindfulSidebar(related.parentElement);
      }

      // Hide comments section if distracted
      const comments = document.querySelector('#comments');
      if (comments && comments.getAttribute('data-focusdns-muted') !== 'true') {
        comments.setAttribute('data-focusdns-muted', 'true');
        comments.style.opacity = '0.15';
        comments.style.filter = 'blur(4px)';
        comments.style.transition = 'opacity 0.3s ease';
        comments.addEventListener('mouseenter', () => { comments.style.opacity = '1'; comments.style.filter = 'none'; });
        comments.addEventListener('mouseleave', () => { comments.style.opacity = '0.15'; comments.style.filter = 'blur(4px)'; });
      }
    }
  }

  /**
   * Instagram: Purges algorithmic Home Feed, Reels, and Explore.
   * Keeps Direct Messages (/direct/inbox/), Story tray, and Profile intact.
   */
  function dissectInstagram() {
    // 1. Navigation items for Reels & Explore
    if (surgicalSettings.instagram.reels || surgicalSettings.instagram.explore) {
      const navLinks = document.querySelectorAll('a[href*="/reels/"], a[href*="/explore/"]');
      navLinks.forEach((el) => {
        const parent = el.closest('div[role="listitem"]') || el.parentElement;
        if (parent) removeAndCount(parent, 'Instagram Reels/Explore Nav Tab');
      });
    }

    // 2. Main Feed infinite scroll on homepage
    if (surgicalSettings.instagram.feed && (PATHNAME === '/' || PATHNAME === '')) {
      // Find the main feed articles while skipping stories header
      const articles = document.querySelectorAll('article');
      articles.forEach((art) => {
        // Only target feed posts, not profile grid
        if (art.closest('main[role="main"]')) {
          removeAndCount(art, 'Instagram Algorithmic Feed Post');
        }
      });

      // Inject mindful hub if not already present
      const mainContent = document.querySelector('main[role="main"] section');
      if (mainContent && !document.getElementById('focusdns-ig-mindful-hub')) {
        injectInstagramMindfulHub(mainContent);
      }
    }
  }

  /**
   * Reddit: Purges r/all, r/popular, and Home Feed infinite scroll.
   * Keeps Search, Technical Subreddits (r/FlutterDev, r/programming), and Chat intact.
   */
  function dissectReddit() {
    // 1. Home feed infinite scroll
    if (surgicalSettings.reddit.homeFeed && (PATHNAME === '/' || PATHNAME === '')) {
      const feedContainer = document.querySelector('shreddit-feed, #main-content');
      if (feedContainer && !document.getElementById('focusdns-reddit-hub')) {
        feedContainer.style.display = 'none';
        injectRedditMindfulHub(feedContainer.parentElement);
      }
    }

    // 2. Promoted posts and trending carousels
    const promoted = document.querySelectorAll('shreddit-ad-post, [data-testid="ad-post-container"], aside[aria-label="Popular Communities"]');
    promoted.forEach((el) => removeAndCount(el, 'Reddit Promoted/Carousel'));
  }

  /**
   * X / Twitter: Purges "For You" algorithmic timeline, Trends sidebar.
   * Keeps "Following" timeline, Search, and Direct Messages (/messages) intact.
   */
  function dissectTwitterX() {
    if (surgicalSettings.twitter.forYou) {
      // Find "For you" timeline tab
      const forYouTab = document.querySelector('[role="tablist"] [role="tab"]:first-child');
      if (forYouTab && forYouTab.textContent.toLowerCase().includes('for you')) {
        const followingTab = document.querySelector('[role="tablist"] [role="tab"]:nth-child(2)');
        if (followingTab && forYouTab.getAttribute('aria-selected') === 'true') {
          // Auto switch to Following tab
          followingTab.click();
        }
        forYouTab.style.display = 'none';
      }
    }

    if (surgicalSettings.twitter.trends) {
      const trendsSidebar = document.querySelector('[aria-label="Timeline: Trending now"], [data-testid="sidebarColumn"]');
      if (trendsSidebar) {
        trendsSidebar.style.display = 'none';
      }
    }
  }

  /**
   * LinkedIn: Purges clickbait feed posts and infinite scroll.
   * Keeps Messaging (/messaging/), Notifications, and Job Portal intact.
   */
  function dissectLinkedIn() {
    if (surgicalSettings.linkedin.feed && (PATHNAME === '/feed/' || PATHNAME === '/feed' || PATHNAME === '/')) {
      const feedPosts = document.querySelectorAll('.feed-shared-update-v2, div[data-finite-scroll-hotkey-item]');
      feedPosts.forEach((p) => removeAndCount(p, 'LinkedIn Algorithmic Feed Post'));

      const newsSidebar = document.querySelector('.feed-right-rail, #feed-news-module');
      if (newsSidebar) newsSidebar.style.display = 'none';

      const feedContainer = document.querySelector('.scaffold-layout__main');
      if (feedContainer && !document.getElementById('focusdns-linkedin-hub')) {
        injectLinkedInMindfulHub(feedContainer);
      }
    }
  }

  /**
   * TikTok: Intercepts FYP and replaces with Mindful Interstitial.
   */
  function dissectTikTok() {
    if (surgicalSettings.tiktok.fyp) {
      const fypFeed = document.querySelector('[data-e2e="recommend-list-item-container"], #main-content-homepage_hot');
      if (fypFeed) {
        fypFeed.innerHTML = `
          <div style="padding: 40px; text-align: center; color: white; background: #121214; border-radius: 16px; margin: 20px;">
            <h2 style="font-size: 24px; color: #ff3b5c; margin-bottom: 12px;">TikTok FYP Severed</h2>
            <p style="color: #a0a0a8; max-width: 500px; margin: 0 auto 20px auto;">
              Infinite vertical doomscrolling is disabled by FocusDNS. Direct messaging remains active.
            </p>
            <a href="https://www.tiktok.com/messages" style="display: inline-block; padding: 12px 24px; background: #2f80ed; color: white; text-decoration: none; border-radius: 8px; font-weight: bold;">
              Open Direct Messages 💬
            </a>
          </div>
        `;
      }
    }
  }

  /* =========================================================================
   * 5. HELPER REMOVAL & TELEMETRY DISPATCHER
   * ========================================================================= */

  function removeAndCount(element, label) {
    if (!element || element.getAttribute('data-focusdns-purged') === 'true') return;
    element.setAttribute('data-focusdns-purged', 'true');
    element.remove();
    distractionCounter++;

    // Throttled notification to background worker
    if (distractionCounter % 5 === 1) {
      chrome.runtime.sendMessage({ action: 'CONTENT_SCRIPT_DISTRACTION_REMOVED', label: label }).catch(() => {});
    }
  }

  /* =========================================================================
   * 6. MINDFUL UI INJECTIONS (Search-Only & Intentional Hubs)
   * ========================================================================= */

  function injectYouTubeMindfulBanner(container) {
    if (!container) return;
    const banner = document.createElement('div');
    banner.id = 'focusdns-yt-mindful-banner';
    banner.style.cssText = `
      padding: 48px 24px;
      margin: 32px auto;
      max-width: 760px;
      background: linear-gradient(135deg, rgba(20,20,22,0.95), rgba(30,30,36,0.95));
      border: 1px solid rgba(255,255,255,0.08);
      border-radius: 20px;
      text-align: center;
      color: #f0f0f5;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      box-shadow: 0 12px 36px rgba(0,0,0,0.4);
    `;

    banner.innerHTML = `
      <div style="display: inline-flex; align-items: center; justify-content: center; width: 56px; height: 56px; border-radius: 28px; background: rgba(0, 230, 153, 0.12); margin-bottom: 16px;">
        <span style="font-size: 28px;">🎯</span>
      </div>
      <h2 style="font-size: 24px; font-weight: 700; margin: 0 0 10px 0; color: #ffffff;">Intentional YouTube Mode Active</h2>
      <p style="color: #9aa0a6; font-size: 14px; line-height: 1.6; max-width: 520px; margin: 0 auto 24px auto;">
        The algorithmic home feed and Shorts have been severed to protect your focus. Use the top search bar for specific lectures, tutorials, and courses.
      </p>
      <div style="display: flex; gap: 12px; justify-content: center; flex-wrap: wrap;">
        <a href="https://www.youtube.com/feed/subscriptions" style="padding: 10px 20px; background: rgba(255,255,255,0.08); color: #fff; text-decoration: none; border-radius: 10px; font-size: 13px; font-weight: 600; border: 1px solid rgba(255,255,255,0.1);">
          Subscriptions Feed 📺
        </a>
        <a href="https://www.youtube.com/feed/library" style="padding: 10px 20px; background: rgba(255,255,255,0.08); color: #fff; text-decoration: none; border-radius: 10px; font-size: 13px; font-weight: 600; border: 1px solid rgba(255,255,255,0.1);">
          Saved Playlists & History 📚
        </a>
      </div>
    `;

    container.prepend(banner);
  }

  function injectInstagramMindfulHub(container) {
    if (!container) return;
    const hub = document.createElement('div');
    hub.id = 'focusdns-ig-mindful-hub';
    hub.style.cssText = `
      padding: 48px 24px;
      margin: 40px auto;
      max-width: 600px;
      background: #121214;
      border: 1px solid #26262a;
      border-radius: 18px;
      text-align: center;
      color: #f0f0f5;
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
    `;

    hub.innerHTML = `
      <div style="font-size: 32px; margin-bottom: 12px;">💬</div>
      <h2 style="font-size: 22px; font-weight: 700; margin: 0 0 8px 0; color: #fff;">Communication Mode Engaged</h2>
      <p style="color: #8e8e93; font-size: 14px; margin: 0 auto 24px auto; max-width: 440px;">
        Algorithmic feed, Reels, and Explore are severed. Your Direct Messages and family Stories remain fully active.
      </p>
      <a href="https://www.instagram.com/direct/inbox/" style="display: inline-block; padding: 12px 28px; background: #0095f6; color: white; text-decoration: none; border-radius: 10px; font-weight: 600; font-size: 14px;">
        Open Direct Messages ✉️
      </a>
    `;

    container.prepend(hub);
  }

  function injectRedditMindfulHub(container) {
    if (!container) return;
    const hub = document.createElement('div');
    hub.id = 'focusdns-reddit-hub';
    hub.style.cssText = `
      padding: 40px 20px;
      margin: 30px auto;
      max-width: 640px;
      background: #1a1a1b;
      border: 1px solid #343536;
      border-radius: 16px;
      text-align: center;
      color: #d7dadc;
    `;

    hub.innerHTML = `
      <h3 style="font-size: 20px; color: #ff4500; margin-bottom: 10px;">Reddit Home Infinite Feed Muted</h3>
      <p style="color: #818384; font-size: 13px; margin-bottom: 20px;">
        Visit your specific technical, scientific, and community subreddits directly without doomscrolling r/all.
      </p>
      <div style="display: flex; gap: 8px; justify-content: center; flex-wrap: wrap;">
        <a href="https://www.reddit.com/r/programming/" style="padding: 8px 16px; background: #272729; color: #d7dadc; text-decoration: none; border-radius: 8px; font-size: 13px;">r/programming</a>
        <a href="https://www.reddit.com/r/FlutterDev/" style="padding: 8px 16px; background: #272729; color: #d7dadc; text-decoration: none; border-radius: 8px; font-size: 13px;">r/FlutterDev</a>
        <a href="https://www.reddit.com/r/learnprogramming/" style="padding: 8px 16px; background: #272729; color: #d7dadc; text-decoration: none; border-radius: 8px; font-size: 13px;">r/learnprogramming</a>
      </div>
    `;

    container.prepend(hub);
  }

  function injectLinkedInMindfulHub(container) {
    if (!container) return;
    const hub = document.createElement('div');
    hub.id = 'focusdns-linkedin-hub';
    hub.style.cssText = `
      padding: 40px;
      margin: 20px 0;
      background: #1b1f23;
      border: 1px solid rgba(255,255,255,0.1);
      border-radius: 12px;
      text-align: center;
      color: #fff;
    `;

    hub.innerHTML = `
      <h3 style="font-size: 20px; margin-bottom: 8px; color: #0a66c2;">Intentional Professional Mode</h3>
      <p style="color: #9aa0a6; font-size: 13px; margin-bottom: 20px;">
        News feed clickbait muted. Direct messaging and jobs network remain active.
      </p>
      <a href="https://www.linkedin.com/messaging/" style="padding: 10px 22px; background: #0a66c2; color: #fff; text-decoration: none; border-radius: 8px; font-weight: 600;">
        Open LinkedIn Messaging 💬
      </a>
    `;

    container.prepend(hub);
  }

  function injectMindfulSidebar(container) {
    if (!container || document.getElementById('focusdns-sidebar-placeholder')) return;
    const placeholder = document.createElement('div');
    placeholder.id = 'focusdns-sidebar-placeholder';
    placeholder.style.cssText = `
      padding: 24px 16px;
      background: rgba(255,255,255,0.03);
      border: 1px dashed rgba(255,255,255,0.1);
      border-radius: 12px;
      text-align: center;
      color: #888;
      font-size: 13px;
      margin-top: 16px;
    `;
    placeholder.innerHTML = '⚡ Related clickbait recommendations hidden by FocusDNS.';
    container.appendChild(placeholder);
  }

  // Execute initialization
  init();
})();
