/**
 * FocusDNS Extension Popup Controller
 * Manages reactive UI bindings, SVG circular timer rendering, session triggers,
 * and emergency friction challenges.
 */

'use strict';

document.addEventListener('DOMContentLoaded', () => {
  const CIRCLE_CIRCUMFERENCE = 326.72; // 2 * PI * 52

  // DOM Elements
  const timerDisplay = document.getElementById('timer-display');
  const modeDisplay = document.getElementById('mode-display');
  const timerBar = document.getElementById('timer-progress');
  const strictLockIndicator = document.getElementById('strict-lock-indicator');
  const connectionBadge = document.getElementById('connection-badge');

  const statDistractions = document.getElementById('stat-distractions');
  const statMinutes = document.getElementById('stat-minutes');
  const statCycle = document.getElementById('stat-cycle');

  const toggleYtShorts = document.getElementById('toggle-yt-shorts');
  const toggleIgReels = document.getElementById('toggle-ig-reels');
  const toggleRedditAll = document.getElementById('toggle-reddit-all');

  const btnEmergency = document.getElementById('btn-emergency');
  const emergencyModal = document.getElementById('emergency-modal');
  const btnCancelModal = document.getElementById('btn-cancel-modal');
  const btnSubmitOath = document.getElementById('btn-submit-oath');
  const oathInput = document.getElementById('oath-input');
  const emergencyReason = document.getElementById('emergency-reason');
  const linkOptions = document.getElementById('link-options');

  let activeState = null;
  let tickerInterval = null;

  /* =========================================================================
   * 1. RECURRING DATA SYNC & UI RENDER
   * ========================================================================= */

  function fetchLatestState() {
    chrome.runtime.sendMessage({ action: 'GET_STATUS' }, (response) => {
      if (chrome.runtime.lastError || !response || !response.state) {
        setOfflineState();
        return;
      }
      activeState = response.state;
      renderUI(activeState);
    });
  }

  function setOfflineState() {
    connectionBadge.textContent = 'Standalone';
    connectionBadge.className = 'badge badge-offline';
  }

  function renderUI(state) {
    // 1. Connection Badge
    if (state.isDaemonConnected || state.isCloudConnected) {
      connectionBadge.textContent = 'Synced';
      connectionBadge.className = 'badge badge-online';
    } else {
      connectionBadge.textContent = 'Standalone';
      connectionBadge.className = 'badge badge-offline';
    }

    // 2. Strict Lock Badge
    if (state.isStrictLockActive) {
      strictLockIndicator.classList.remove('hidden');
    } else {
      strictLockIndicator.classList.add('hidden');
    }

    // 3. Telemetry Stats
    statDistractions.textContent = state.dailyDistractionsBlocked || 0;
    statMinutes.textContent = `${state.minutesReclaimedToday || 0}m`;
    statCycle.textContent = `${state.currentCycle || 1}/${state.totalCycles || 4}`;

    // 4. Surgical Switches
    if (state.surgicalSettings) {
      toggleYtShorts.checked = !!state.surgicalSettings.youtube?.shorts;
      toggleIgReels.checked = !!state.surgicalSettings.instagram?.reels;
      toggleRedditAll.checked = !!state.surgicalSettings.reddit?.popular;
    }

    // 5. Timer & Progress Circle
    updateTimerVisuals(state);
  }

  function updateTimerVisuals(state) {
    let remaining = 0;
    let total = 0;
    let modeText = 'UNRESTRICTED';
    let strokeColor = '#00e699'; // Green

    if (state.currentMode === 'focus') {
      remaining = state.sessionRemainingSeconds || 0;
      total = state.sessionTotalSeconds || (25 * 60);
      modeText = state.isStrictLockActive ? 'STRICT FOCUS LOCK' : 'FOCUS SESSION';
      strokeColor = state.isStrictLockActive ? '#ff3b5c' : '#00e699';
    } else if (state.currentMode === 'break') {
      remaining = state.breakRemainingSeconds || 0;
      total = state.breakTotalSeconds || (5 * 60);
      modeText = 'MINDFUL BREAK';
      strokeColor = '#0095f6'; // Blue
    } else {
      remaining = 0;
      total = 1;
      modeText = 'STANDBY';
      strokeColor = '#60606e';
    }

    // Format MM:SS
    const mins = Math.floor(remaining / 60);
    const secs = remaining % 60;
    timerDisplay.textContent = `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
    modeDisplay.textContent = modeText;

    // SVG Circular progress
    const progress = total > 0 ? (total - remaining) / total : 0;
    const offset = CIRCLE_CIRCUMFERENCE * (1 - progress);
    timerBar.style.strokeDashoffset = offset;
    timerBar.style.stroke = strokeColor;
  }

  /* =========================================================================
   * 2. EVENT LISTENERS
   * ========================================================================= */

  // Quick session buttons (25m / 50m)
  document.querySelectorAll('.session-launcher button[data-duration]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const duration = parseInt(btn.getAttribute('data-duration'), 10);
      chrome.runtime.sendMessage({
        action: 'START_FOCUS_SESSION',
        payload: { durationMinutes: duration, isStrict: false }
      }, (res) => {
        fetchLatestState();
      });
    });
  });

  // Strict Lock button
  document.getElementById('btn-custom-strict').addEventListener('click', () => {
    chrome.runtime.sendMessage({
      action: 'START_FOCUS_SESSION',
      payload: { durationMinutes: 45, isStrict: true }
    }, (res) => {
      fetchLatestState();
    });
  });

  // Surgical toggles
  toggleYtShorts.addEventListener('change', () => {
    updateSurgicalSubfeatures({ youtube: { shorts: toggleYtShorts.checked } });
  });

  toggleIgReels.addEventListener('change', () => {
    updateSurgicalSubfeatures({ instagram: { reels: toggleIgReels.checked, explore: toggleIgReels.checked } });
  });

  toggleRedditAll.addEventListener('change', () => {
    updateSurgicalSubfeatures({ reddit: { popular: toggleRedditAll.checked, homeFeed: toggleRedditAll.checked } });
  });

  function updateSurgicalSubfeatures(patch) {
    chrome.runtime.sendMessage({
      action: 'UPDATE_SURGICAL_SETTINGS',
      payload: { settings: patch }
    }, () => {
      fetchLatestState();
    });
  }

  // Emergency Modal
  btnEmergency.addEventListener('click', () => {
    emergencyModal.classList.remove('hidden');
  });

  btnCancelModal.addEventListener('click', () => {
    emergencyModal.classList.add('hidden');
    oathInput.value = '';
    emergencyReason.value = '';
  });

  btnSubmitOath.addEventListener('click', () => {
    const text = oathInput.value.trim();
    const reason = emergencyReason.value.trim();

    if (reason.length > 5) {
      chrome.runtime.sendMessage({
        action: 'SUBMIT_EMERGENCY_REQUEST',
        payload: { reason }
      });
    }

    chrome.runtime.sendMessage({
      action: 'SUBMIT_OATH_CHALLENGE',
      payload: { solutionText: text }
    }, (res) => {
      if (res && res.status === 'OK') {
        emergencyModal.classList.add('hidden');
        fetchLatestState();
      } else {
        alert(res?.message || 'Verification failed. Pledge must match exact wording.');
      }
    });
  });

  // Options page link
  linkOptions.addEventListener('click', (e) => {
    e.preventDefault();
    chrome.runtime.openOptionsPage();
  });

  // State change notifications from service worker
  chrome.runtime.onMessage.addListener((msg) => {
    if (msg.action === 'STATE_CHANGED' && msg.state) {
      activeState = msg.state;
      renderUI(activeState);
    }
  });

  // Boot UI and continuous 1-second ticker
  fetchLatestState();
  tickerInterval = setInterval(fetchLatestState, 1000);
});
