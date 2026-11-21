/**
 * FocusDNS Browser Extension - Background Service Worker (Manifest V3)
 * Handles declarativeNetRequest dynamic rules, live WebSocket synchronization with
 * the mobile app and cloud daemon, strict tamper-proof timer enforcement, and
 * cross-device state arbitration.
 */

'use strict';

const CONFIG = {
  DEFAULT_WS_LOCAL_URL: 'ws://localhost:5354/sync',
  DEFAULT_WS_CLOUD_URL: 'ws://localhost:8080/api/v1/ws',
  DEFAULT_HTTP_ENDPOINT: 'http://localhost:8080/api/v1',
  HEARTBEAT_INTERVAL_MS: 15000,
  RECONNECT_BASE_MS: 1500,
  RECONNECT_MAX_MS: 30000,
  ALARM_SESSION_TICK: 'focusdns_session_tick',
  ALARM_TELEMETRY_SYNC: 'focusdns_telemetry_sync',
  RULE_PRIORITY_STRICT: 100,
  RULE_PRIORITY_NORMAL: 50,
  RULE_PRIORITY_WHITELIST: 200,
};

// Internal Reactive State
const state = {
  isProtectionActive: true,
  isStrictLockActive: false,
  strictLockedUntil: null,
  currentMode: 'focus', // 'focus', 'break', 'unrestricted'
  activeSessionDurationMinutes: 0,
  sessionRemainingSeconds: 0,
  sessionTotalSeconds: 0,
  breakRemainingSeconds: 0,
  breakTotalSeconds: 0,
  currentCycle: 1,
  totalCycles: 4,
  pairedDeviceId: null,
  userId: null,
  accountabilityPartnerEmail: null,
  isDaemonConnected: false,
  isCloudConnected: false,
  dailyDistractionsBlocked: 0,
  minutesReclaimedToday: 0,
  surgicalSettings: {
    instagram: { feed: true, reels: true, explore: true, stories: false, dms: false },
    youtube: { homepage: true, shorts: true, recommendations: true, comments: false, search: false },
    reddit: { homeFeed: true, popular: true, infiniteScroll: true, subreddits: false, chat: false },
    twitter: { forYou: true, trends: true, following: false, dms: false },
    linkedin: { feed: true, news: true, messages: false, jobs: false },
    tiktok: { fyp: true, live: true, messages: false }
  },
  customBlockedDomains: [],
  customWhitelistedDomains: []
};

let localWebSocket = null;
let cloudWebSocket = null;
let reconnectTimer = null;
let reconnectAttempts = 0;

/* =========================================================================
 * 1. LIFECYCLE & INITIALIZATION
 * ========================================================================= */

chrome.runtime.onInstalled.addListener(async (details) => {
  console.info('[FocusDNS] Extension installed/updated:', details.reason);
  await initializeStorage();
  await refreshDynamicRules();
  setupAlarms();
  connectWebSockets();
});

chrome.runtime.onStartup.addListener(async () => {
  console.info('[FocusDNS] Extension starting up...');
  await restoreStateFromStorage();
  await refreshDynamicRules();
  setupAlarms();
  connectWebSockets();
});

async function initializeStorage() {
  const stored = await chrome.storage.local.get([
    'isProtectionActive',
    'isStrictLockActive',
    'strictLockedUntil',
    'currentMode',
    'sessionRemainingSeconds',
    'surgicalSettings',
    'dailyDistractionsBlocked',
    'minutesReclaimedToday',
    'pairedDeviceId',
    'userId',
    'customBlockedDomains',
    'customWhitelistedDomains'
  ]);

  if (stored.isProtectionActive !== undefined) state.isProtectionActive = stored.isProtectionActive;
  if (stored.isStrictLockActive !== undefined) state.isStrictLockActive = stored.isStrictLockActive;
  if (stored.strictLockedUntil !== undefined) state.strictLockedUntil = stored.strictLockedUntil;
  if (stored.currentMode) state.currentMode = stored.currentMode;
  if (stored.surgicalSettings) state.surgicalSettings = { ...state.surgicalSettings, ...stored.surgicalSettings };
  if (stored.dailyDistractionsBlocked) state.dailyDistractionsBlocked = stored.dailyDistractionsBlocked;
  if (stored.minutesReclaimedToday) state.minutesReclaimedToday = stored.minutesReclaimedToday;
  if (stored.pairedDeviceId) state.pairedDeviceId = stored.pairedDeviceId;
  if (stored.userId) state.userId = stored.userId;
  if (stored.customBlockedDomains) state.customBlockedDomains = stored.customBlockedDomains;
  if (stored.customWhitelistedDomains) state.customWhitelistedDomains = stored.customWhitelistedDomains;

  await saveStateToStorage();
}

async function restoreStateFromStorage() {
  await initializeStorage();
  checkStrictLockExpiry();
}

async function saveStateToStorage() {
  await chrome.storage.local.set({
    isProtectionActive: state.isProtectionActive,
    isStrictLockActive: state.isStrictLockActive,
    strictLockedUntil: state.strictLockedUntil,
    currentMode: state.currentMode,
    sessionRemainingSeconds: state.sessionRemainingSeconds,
    surgicalSettings: state.surgicalSettings,
    dailyDistractionsBlocked: state.dailyDistractionsBlocked,
    minutesReclaimedToday: state.minutesReclaimedToday,
    pairedDeviceId: state.pairedDeviceId,
    userId: state.userId,
    customBlockedDomains: state.customBlockedDomains,
    customWhitelistedDomains: state.customWhitelistedDomains
  });
}

function setupAlarms() {
  chrome.alarms.create(CONFIG.ALARM_SESSION_TICK, { periodInMinutes: 0.05 }); // ~3 seconds
  chrome.alarms.create(CONFIG.ALARM_TELEMETRY_SYNC, { periodInMinutes: 2.0 });
}

chrome.alarms.onAlarm.addListener(async (alarm) => {
  if (alarm.name === CONFIG.ALARM_SESSION_TICK) {
    handleSessionTick();
  } else if (alarm.name === CONFIG.ALARM_TELEMETRY_SYNC) {
    await syncTelemetryToDaemon();
  }
});

/* =========================================================================
 * 2. SESSION TIMERS & STRICT LOCK ARBITRATION
 * ========================================================================= */

function handleSessionTick() {
  const now = Date.now();

  // Strict Lock Evaluation
  if (state.isStrictLockActive && state.strictLockedUntil) {
    if (now >= state.strictLockedUntil) {
      console.info('[FocusDNS] Strict lock period has elapsed.');
      state.isStrictLockActive = false;
      state.strictLockedUntil = null;
      broadcastStateChange('STRICT_LOCK_RELEASED');
    }
  }

  // Session countdown
  if (state.currentMode === 'focus' && state.sessionRemainingSeconds > 0) {
    state.sessionRemainingSeconds = Math.max(0, state.sessionRemainingSeconds - 3);
    if (state.sessionRemainingSeconds === 0) {
      onFocusSessionCompleted();
    }
  } else if (state.currentMode === 'break' && state.breakRemainingSeconds > 0) {
    state.breakRemainingSeconds = Math.max(0, state.breakRemainingSeconds - 3);
    if (state.breakRemainingSeconds === 0) {
      onBreakSessionCompleted();
    }
  }

  saveStateToStorage();
}

function onFocusSessionCompleted() {
  console.info('[FocusDNS] Focus session completed. Transitioning to Break mode.');
  state.minutesReclaimedToday += Math.round(state.sessionTotalSeconds / 60);
  
  if (state.currentCycle < state.totalCycles) {
    state.currentMode = 'break';
    state.breakTotalSeconds = 5 * 60; // 5 min break
    state.breakRemainingSeconds = state.breakTotalSeconds;
    notifyUser('Focus Session Completed! ☕', 'Take a 5-minute mindful break. Relax your eyes.');
  } else {
    state.currentMode = 'unrestricted';
    state.currentCycle = 1;
    notifyUser('Goal Reached! 🏆', 'All focus cycles finished! Great deep work today.');
  }

  refreshDynamicRules();
  broadcastStateChange('MODE_TRANSITION');
}

function onBreakSessionCompleted() {
  console.info('[FocusDNS] Break session completed. Resuming Focus session.');
  state.currentCycle += 1;
  state.currentMode = 'focus';
  state.sessionTotalSeconds = 25 * 60; // Next Pomodoro
  state.sessionRemainingSeconds = state.sessionTotalSeconds;
  
  notifyUser('Break Over 🎯', 'Time for Cycle ' + state.currentCycle + ' of ' + state.totalCycles + '. Distractions blocked.');
  refreshDynamicRules();
  broadcastStateChange('MODE_TRANSITION');
}

function checkStrictLockExpiry() {
  if (state.isStrictLockActive && state.strictLockedUntil) {
    if (Date.now() >= state.strictLockedUntil) {
      state.isStrictLockActive = false;
      state.strictLockedUntil = null;
      saveStateToStorage();
    }
  }
}

/* =========================================================================
 * 3. DECLARATIVE NET REQUEST RULE GENERATOR
 * ========================================================================= */

async function refreshDynamicRules() {
  const currentRules = await chrome.declarativeNetRequest.getDynamicRules();
  const ruleIdsToRemove = currentRules.map((r) => r.id);
  const newRules = [];
  let ruleIdCounter = 1000;

  // Custom Whitelist overrides (Highest priority)
  for (const domain of state.customWhitelistedDomains) {
    newRules.push({
      id: ruleIdCounter++,
      priority: CONFIG.RULE_PRIORITY_WHITELIST,
      action: { type: 'allow' },
      condition: {
        urlFilter: `||${domain}`,
        resourceTypes: ['main_frame', 'sub_frame', 'xmlhttprequest', 'media', 'websocket']
      }
    });
  }

  // Active Protection rules
  if (state.isProtectionActive) {
    // 1. YouTube Shorts redirect/block
    if (state.surgicalSettings.youtube.shorts) {
      newRules.push({
        id: ruleIdCounter++,
        priority: CONFIG.RULE_PRIORITY_STRICT,
        action: {
          type: 'redirect',
          redirect: { url: 'https://www.youtube.com/feed/subscriptions' }
        },
        condition: {
          urlFilter: '||youtube.com/shorts/*',
          resourceTypes: ['main_frame']
        }
      });
    }

    // 2. Instagram Reels redirect/block
    if (state.surgicalSettings.instagram.reels) {
      newRules.push({
        id: ruleIdCounter++,
        priority: CONFIG.RULE_PRIORITY_STRICT,
        action: {
          type: 'redirect',
          redirect: { url: 'https://www.instagram.com/direct/inbox/' }
        },
        condition: {
          urlFilter: '||instagram.com/reels/*',
          resourceTypes: ['main_frame']
        }
      });
      newRules.push({
        id: ruleIdCounter++,
        priority: CONFIG.RULE_PRIORITY_STRICT,
        action: {
          type: 'redirect',
          redirect: { url: 'https://www.instagram.com/direct/inbox/' }
        },
        condition: {
          urlFilter: '||instagram.com/explore/*',
          resourceTypes: ['main_frame']
        }
      });
    }

    // 3. Reddit popular / r/all blocking in focus mode
    if (state.surgicalSettings.reddit.popular && state.currentMode === 'focus') {
      newRules.push({
        id: ruleIdCounter++,
        priority: CONFIG.RULE_PRIORITY_NORMAL,
        action: {
          type: 'redirect',
          redirect: { url: 'https://www.reddit.com/r/programming/' }
        },
        condition: {
          urlFilter: '||reddit.com/r/all/*',
          resourceTypes: ['main_frame']
        }
      });
      newRules.push({
        id: ruleIdCounter++,
        priority: CONFIG.RULE_PRIORITY_NORMAL,
        action: {
          type: 'redirect',
          redirect: { url: 'https://www.reddit.com/r/programming/' }
        },
        condition: {
          urlFilter: '||reddit.com/r/popular/*',
          resourceTypes: ['main_frame']
        }
      });
    }

    // 4. Custom Blocked Domains
    for (const domain of state.customBlockedDomains) {
      newRules.push({
        id: ruleIdCounter++,
        priority: CONFIG.RULE_PRIORITY_STRICT,
        action: { type: 'block' },
        condition: {
          urlFilter: `||${domain}`,
          resourceTypes: ['main_frame', 'sub_frame', 'xmlhttprequest', 'media', 'websocket']
        }
      });
    }

    // 5. Hard Block TikTok during Focus Sessions
    if (state.currentMode === 'focus' && state.surgicalSettings.tiktok.fyp) {
      newRules.push({
        id: ruleIdCounter++,
        priority: CONFIG.RULE_PRIORITY_STRICT,
        action: { type: 'block' },
        condition: {
          urlFilter: '||tiktok.com/*',
          resourceTypes: ['main_frame', 'xmlhttprequest', 'media']
        }
      });
    }
  }

  try {
    await chrome.declarativeNetRequest.updateDynamicRules({
      removeRuleIds: ruleIdsToRemove,
      addRules: newRules
    });
    console.info(`[FocusDNS] Updated ${newRules.length} dynamic declarativeNetRequest rules.`);
  } catch (err) {
    console.error('[FocusDNS] Failed to update dynamic DNR rules:', err);
  }
}

/* =========================================================================
 * 4. WEBSOCKET SYNCHRONIZATION (LOCAL DAEMON & CLOUD)
 * ========================================================================= */

function connectWebSockets() {
  connectLocalDaemon();
  connectCloudGateway();
}

function connectLocalDaemon() {
  if (localWebSocket && (localWebSocket.readyState === WebSocket.OPEN || localWebSocket.readyState === WebSocket.CONNECTING)) {
    return;
  }

  try {
    localWebSocket = new WebSocket(CONFIG.DEFAULT_WS_LOCAL_URL);

    localWebSocket.onopen = () => {
      console.info('[FocusDNS] Connected to local FocusDNS daemon.');
      state.isDaemonConnected = true;
      reconnectAttempts = 0;
      broadcastStateChange('DAEMON_CONNECTED');
      sendWebSocketMessage(localWebSocket, {
        type: 'HANDSHAKE',
        clientType: 'CHROME_EXTENSION',
        version: '2.0.0',
        deviceId: state.pairedDeviceId
      });
    };

    localWebSocket.onmessage = (event) => {
      try {
        const message = JSON.parse(event.data);
        handleIncomingSyncMessage(message);
      } catch (e) {
        console.error('[FocusDNS] Malformed WS message:', e);
      }
    };

    localWebSocket.onclose = () => {
      state.isDaemonConnected = false;
      broadcastStateChange('DAEMON_DISCONNECTED');
      scheduleReconnect();
    };

    localWebSocket.onerror = (err) => {
      console.warn('[FocusDNS] Local daemon WS error (daemon may not be running).');
    };
  } catch (e) {
    console.warn('[FocusDNS] WebSocket connection initiation failed.');
    scheduleReconnect();
  }
}

function connectCloudGateway() {
  if (!state.userId) return; // Only connect if user paired account

  try {
    cloudWebSocket = new WebSocket(`${CONFIG.DEFAULT_WS_CLOUD_URL}?token=${state.userId}`);

    cloudWebSocket.onopen = () => {
      console.info('[FocusDNS] Connected to cloud fleet gateway.');
      state.isCloudConnected = true;
      broadcastStateChange('CLOUD_CONNECTED');
    };

    cloudWebSocket.onmessage = (event) => {
      try {
        const message = JSON.parse(event.data);
        handleIncomingSyncMessage(message);
      } catch (e) {
        console.error('[FocusDNS] Malformed cloud WS message:', e);
      }
    };

    cloudWebSocket.onclose = () => {
      state.isCloudConnected = false;
      broadcastStateChange('CLOUD_DISCONNECTED');
    };
  } catch (e) {
    console.warn('[FocusDNS] Cloud WS failed to initialize.');
  }
}

function scheduleReconnect() {
  if (reconnectTimer) clearTimeout(reconnectTimer);
  const delay = Math.min(CONFIG.RECONNECT_BASE_MS * Math.pow(1.5, reconnectAttempts++), CONFIG.RECONNECT_MAX_MS);
  reconnectTimer = setTimeout(() => {
    connectLocalDaemon();
  }, delay);
}

function sendWebSocketMessage(ws, payload) {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(payload));
  }
}

function handleIncomingSyncMessage(msg) {
  console.info('[FocusDNS] Incoming sync message:', msg.type);

  switch (msg.type) {
    case 'SYNC_STATE':
    case 'LOCK_STATE_PUSH':
      if (msg.isStrictLockActive !== undefined) {
        state.isStrictLockActive = msg.isStrictLockActive;
        state.strictLockedUntil = msg.strictLockedUntil;
      }
      if (msg.currentMode) state.currentMode = msg.currentMode;
      if (msg.sessionRemainingSeconds !== undefined) state.sessionRemainingSeconds = msg.sessionRemainingSeconds;
      if (msg.surgicalSettings) state.surgicalSettings = { ...state.surgicalSettings, ...msg.surgicalSettings };
      saveStateToStorage();
      refreshDynamicRules();
      broadcastStateChange('REMOTE_SYNC');
      break;

    case 'TRIGGER_FOCUS_LOCK':
      state.isStrictLockActive = true;
      state.strictLockedUntil = Date.now() + (msg.durationMinutes * 60 * 1000);
      state.currentMode = 'focus';
      state.sessionTotalSeconds = msg.durationMinutes * 60;
      state.sessionRemainingSeconds = state.sessionTotalSeconds;
      saveStateToStorage();
      refreshDynamicRules();
      notifyUser('Strict Lock Engaged 🔒', `Locked for ${msg.durationMinutes} minutes. Social media feeds severed.`);
      broadcastStateChange('STRICT_LOCK_ENGAGED');
      break;

    case 'EMERGENCY_OVERRIDE_APPROVED':
      state.isStrictLockActive = false;
      state.strictLockedUntil = null;
      state.currentMode = 'unrestricted';
      saveStateToStorage();
      refreshDynamicRules();
      notifyUser('Emergency Override Granted 🔓', 'Your accountability partner approved your unblock request.');
      broadcastStateChange('EMERGENCY_OVERRIDE_APPROVED');
      break;

    case 'POLICY_UPDATE':
      if (msg.customBlockedDomains) state.customBlockedDomains = msg.customBlockedDomains;
      if (msg.customWhitelistedDomains) state.customWhitelistedDomains = msg.customWhitelistedDomains;
      saveStateToStorage();
      refreshDynamicRules();
      break;
  }
}

async function syncTelemetryToDaemon() {
  if (state.isDaemonConnected && localWebSocket) {
    sendWebSocketMessage(localWebSocket, {
      type: 'TELEMETRY_HEARTBEAT',
      client: 'CHROME_EXT',
      distractionsBlocked: state.dailyDistractionsBlocked,
      minutesReclaimed: state.minutesReclaimedToday,
      isStrictLockActive: state.isStrictLockActive,
      timestamp: Date.now()
    });
  }
}

/* =========================================================================
 * 5. NAVIGATION MONITOR & ANTI-TAMPER SENTINEL
 * ========================================================================= */

chrome.webNavigation.onBeforeNavigate.addListener((details) => {
  if (details.frameId !== 0) return; // Only evaluate top-level navigation

  const url = details.url.toLowerCase();

  // If user tries to open extensions manager while strictly locked, warn them
  if (state.isStrictLockActive && (url.includes('chrome://extensions') || url.includes('edge://extensions') || url.includes('about:addons'))) {
    console.warn('[FocusDNS Anti-Tamper] Attempt to manage extensions during strict lock.');
    // We cannot block chrome:// URLs via DNR, but we can log telemetry and notify
    notifyUser('Strict Focus Active ⚠️', 'Extensions management is audited during active focus lock.');
  }

  // Count distractions avoided on navigation to blocked social hubs
  if (state.isProtectionActive) {
    if (url.includes('instagram.com/reels') || url.includes('youtube.com/shorts') || url.includes('tiktok.com')) {
      state.dailyDistractionsBlocked++;
      saveStateToStorage();
      broadcastStateChange('DISTRACTION_BLOCKED');
    }
  }
});

/* =========================================================================
 * 6. MESSAGE BUS (POPUP & CONTENT SCRIPTS)
 * ========================================================================= */

chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  const { action, payload } = request;

  switch (action) {
    case 'GET_STATUS':
      sendResponse({ status: 'OK', state });
      return true;

    case 'START_FOCUS_SESSION':
      if (state.isStrictLockActive) {
        sendResponse({ status: 'ERROR', message: 'Strict lock is already active.' });
        return true;
      }
      const duration = payload.durationMinutes || 25;
      const isStrict = payload.isStrict || false;

      state.currentMode = 'focus';
      state.sessionTotalSeconds = duration * 60;
      state.sessionRemainingSeconds = state.sessionTotalSeconds;
      state.isStrictLockActive = isStrict;
      if (isStrict) {
        state.strictLockedUntil = Date.now() + (duration * 60 * 1000);
      }

      saveStateToStorage();
      refreshDynamicRules();
      broadcastStateChange('SESSION_STARTED');

      // Forward to local daemon
      if (state.isDaemonConnected) {
        sendWebSocketMessage(localWebSocket, {
          type: 'CLIENT_START_SESSION',
          durationMinutes: duration,
          isStrict: isStrict
        });
      }

      sendResponse({ status: 'OK', state });
      return true;

    case 'TOGGLE_PROTECTION':
      if (state.isStrictLockActive) {
        sendResponse({ status: 'FORBIDDEN', message: 'Cannot disable protection during Strict Lock!' });
        return true;
      }
      state.isProtectionActive = payload.enabled;
      saveStateToStorage();
      refreshDynamicRules();
      broadcastStateChange('PROTECTION_TOGGLED');
      sendResponse({ status: 'OK', isProtectionActive: state.isProtectionActive });
      return true;

    case 'UPDATE_SURGICAL_SETTINGS':
      state.surgicalSettings = { ...state.surgicalSettings, ...payload.settings };
      saveStateToStorage();
      refreshDynamicRules();
      broadcastStateChange('SURGICAL_SETTINGS_UPDATED');
      sendResponse({ status: 'OK' });
      return true;

    case 'SUBMIT_EMERGENCY_REQUEST':
      handleEmergencyUnlockRequest(payload.reason, payload.partnerEmail);
      sendResponse({ status: 'PENDING', message: 'Emergency request dispatched to partner.' });
      return true;

    case 'SUBMIT_OATH_CHALLENGE':
      // Option B Ironclad Lockout: Zero bypass or early unlock permitted during active strict focus
      if (state.isStrictLockActive && state.strictLockedUntil && Date.now() < state.strictLockedUntil) {
        sendResponse({ status: 'FORBIDDEN', message: 'Option B Ironclad Lockout active: zero bypass or early unlock permitted.' });
        return true;
      }
      if (payload.solutionText === 'I choose intentional focus over infinite distraction') {
        state.isStrictLockActive = false;
        state.strictLockedUntil = null;
        state.currentMode = 'unrestricted';
        saveStateToStorage();
        refreshDynamicRules();
        notifyUser('Oath Verified 🕊️', 'Lock released following friction pledge.');
        sendResponse({ status: 'OK' });
      } else {
        sendResponse({ status: 'FAILED', message: 'Pledge text did not match exact oath.' });
      }
      return true;

    case 'PAIR_DEVICE':
      state.pairedDeviceId = payload.deviceId;
      state.userId = payload.userId;
      saveStateToStorage();
      connectCloudGateway();
      sendResponse({ status: 'OK', paired: true });
      return true;

    case 'CONTENT_SCRIPT_DISTRACTION_REMOVED':
      state.dailyDistractionsBlocked++;
      saveStateToStorage();
      broadcastStateChange('DISTRACTION_BLOCKED');
      sendResponse({ status: 'OK', count: state.dailyDistractionsBlocked });
      return true;

    default:
      sendResponse({ status: 'UNKNOWN_ACTION' });
      return false;
  }
});

function handleEmergencyUnlockRequest(reason, partnerEmail) {
  console.info('[FocusDNS] Submitting emergency unlock request:', reason);
  const eventPayload = {
    type: 'EMERGENCY_UNLOCK_REQUESTED',
    deviceId: state.pairedDeviceId || 'browser_extension',
    reason: reason,
    partnerEmail: partnerEmail || state.accountabilityPartnerEmail,
    timestamp: Date.now()
  };

  if (state.isDaemonConnected) {
    sendWebSocketMessage(localWebSocket, eventPayload);
  }
  if (state.isCloudConnected) {
    sendWebSocketMessage(cloudWebSocket, eventPayload);
  }
}

function broadcastStateChange(reason) {
  chrome.runtime.sendMessage({ action: 'STATE_CHANGED', reason, state }).catch(() => {
    // Expected when no popup or options page is open
  });
}

function notifyUser(title, message) {
  chrome.notifications?.create({
    type: 'basic',
    iconUrl: 'icons/icon128.png',
    title: title,
    message: message,
    priority: 2
  });
}
