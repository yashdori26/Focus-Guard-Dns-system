/**
 * FocusDNS Enterprise Web Admin - Fleet Controller & Real-Time Orchestrator
 * Manages cross-device fleet state, WebSocket communication, remote focus lock triggers,
 * and accountability partner emergency approvals.
 */

'use strict';

class FleetController {
  constructor() {
    this.ws = null;
    this.connected = false;
    this.reconnectAttempts = 0;
    this.devices = new Map();
    this.pendingEmergencyRequests = [];
    this.currentUserId = localStorage.getItem('focusdns_admin_user_id') || 'usr_enterprise_default';
    this.partnerEmail = localStorage.getItem('focusdns_partner_email') || 'partner@focusdns.app';

    this.domElements = {
      fleetContainer: document.getElementById('fleet-device-grid'),
      onlineDeviceCount: document.getElementById('stat-online-devices'),
      totalDeviceCount: document.getElementById('stat-total-devices'),
      fleetStatusBadge: document.getElementById('fleet-ws-status'),
      emergencyBadge: document.getElementById('emergency-pending-count'),
      emergencyModal: document.getElementById('admin-emergency-modal'),
      emergencyList: document.getElementById('emergency-request-list'),
      btnTriggerFleetLock: document.getElementById('btn-fleet-lock'),
      btnTriggerFleetBreak: document.getElementById('btn-fleet-break'),
      inputLockDuration: document.getElementById('fleet-lock-duration')
    };

    this.init();
  }

  init() {
    this.bindEvents();
    this.connectWebSocket();
    this.pollDevicesHttpFallback();
  }

  bindEvents() {
    if (this.domElements.btnTriggerFleetLock) {
      this.domElements.btnTriggerFleetLock.addEventListener('click', () => {
        const duration = parseInt(this.domElements.inputLockDuration?.value || '45', 10);
        this.dispatchFleetLock(duration, true);
      });
    }

    if (this.domElements.btnTriggerFleetBreak) {
      this.domElements.btnTriggerFleetBreak.addEventListener('click', () => {
        this.dispatchFleetBreak(5);
      });
    }

    // Modal close
    const btnCloseModal = document.getElementById('btn-close-emergency-modal');
    if (btnCloseModal && this.domElements.emergencyModal) {
      btnCloseModal.addEventListener('click', () => {
        this.domElements.emergencyModal.classList.add('hidden');
      });
    }
  }

  /* =========================================================================
   * 1. WEBSOCKET REAL-TIME FLEET BRIDGE
   * ========================================================================= */

  connectWebSocket() {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const host = window.location.host || 'localhost:5354';
    const wsUrl = `${protocol}//${host}/api/v1/fleet/ws?userId=${this.currentUserId}`;

    try {
      this.ws = new WebSocket(wsUrl);

      this.ws.onopen = () => {
        console.info('[FleetController] WebSocket connected to Fleet Gateway.');
        this.connected = true;
        this.reconnectAttempts = 0;
        this.updateStatusBadge(true);
        this.requestFleetSnapshot();
      };

      this.ws.onmessage = (event) => {
        try {
          const msg = JSON.parse(event.data);
          this.handleIncomingMessage(msg);
        } catch (e) {
          console.error('[FleetController] Malformed WS payload:', e);
        }
      };

      this.ws.onclose = () => {
        this.connected = false;
        this.updateStatusBadge(false);
        this.scheduleReconnect();
      };

      this.ws.onerror = (err) => {
        console.warn('[FleetController] WebSocket error. Using HTTP polling fallback.');
      };
    } catch (e) {
      this.updateStatusBadge(false);
      this.scheduleReconnect();
    }
  }

  scheduleReconnect() {
    const delay = Math.min(1500 * Math.pow(1.5, this.reconnectAttempts++), 30000);
    setTimeout(() => {
      this.connectWebSocket();
    }, delay);
  }

  updateStatusBadge(isOnline) {
    if (!this.domElements.fleetStatusBadge) return;
    if (isOnline) {
      this.domElements.fleetStatusBadge.textContent = 'FLEET LIVE';
      this.domElements.fleetStatusBadge.className = 'status-pill status-live';
    } else {
      this.domElements.fleetStatusBadge.textContent = 'OFFLINE / RECONNECTING';
      this.domElements.fleetStatusBadge.className = 'status-pill status-offline';
    }
  }

  requestFleetSnapshot() {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify({ action: 'GET_FLEET_STATE', userId: this.currentUserId }));
    }
  }

  handleIncomingMessage(msg) {
    switch (msg.type) {
      case 'FLEET_SNAPSHOT':
        this.renderFleetSnapshot(msg.devices || []);
        break;

      case 'DEVICE_HEARTBEAT':
        this.updateDeviceNode(msg.device);
        break;

      case 'EMERGENCY_REQUEST_RECEIVED':
        this.onEmergencyRequestReceived(msg.request);
        break;

      case 'EMERGENCY_RELEASE_CONFIRMED':
        this.onEmergencyReleaseConfirmed(msg.requestId);
        break;
    }
  }

  /* =========================================================================
   * 2. FLEET DEVICE RENDERING & MANAGEMENT
   * ========================================================================= */

  renderFleetSnapshot(deviceList) {
    this.devices.clear();
    let onlineCount = 0;

    deviceList.forEach((dev) => {
      this.devices.set(dev.device_id, dev);
      if (dev.is_online) onlineCount++;
    });

    if (this.domElements.onlineDeviceCount) {
      this.domElements.onlineDeviceCount.textContent = onlineCount;
    }
    if (this.domElements.totalDeviceCount) {
      this.domElements.totalDeviceCount.textContent = this.devices.size;
    }

    this.renderDeviceCards();
  }

  updateDeviceNode(dev) {
    if (!dev) return;
    this.devices.set(dev.device_id, dev);
    this.renderDeviceCards();
  }

  renderDeviceCards() {
    if (!this.domElements.fleetContainer) return;

    if (this.devices.size === 0) {
      this.domElements.fleetContainer.innerHTML = `
        <div class="empty-fleet-card">
          <span style="font-size: 36px;">📱💻</span>
          <h3>No Devices Paired Yet</h3>
          <p>Pair your Android phone or Chrome extension using the QR code in Settings.</p>
        </div>
      `;
      return;
    }

    let html = '';
    this.devices.forEach((dev) => {
      const platformIcon = this.getPlatformIcon(dev.platform);
      const isOnline = dev.is_online;
      const mode = dev.active_mode || 'unrestricted';
      const isLocked = dev.is_strict_lock_active;

      let modeBadge = `<span class="badge badge-normal">STANDBY</span>`;
      if (isLocked) {
        modeBadge = `<span class="badge badge-strict">🔒 STRICT LOCK (${Math.ceil((dev.session_remaining_seconds || 0) / 60)}m)</span>`;
      } else if (mode === 'focus') {
        modeBadge = `<span class="badge badge-focus">🎯 FOCUSING</span>`;
      } else if (mode === 'break') {
        modeBadge = `<span class="badge badge-break">☕ MINDFUL BREAK</span>`;
      }

      html += `
        <div class="fleet-device-card ${isOnline ? 'card-online' : 'card-offline'}" data-id="${dev.device_id}">
          <div class="card-header">
            <div class="device-title">
              <span class="platform-icon">${platformIcon}</span>
              <div>
                <h4>${this.escapeHtml(dev.device_name || dev.device_id)}</h4>
                <small>${dev.platform.toUpperCase()} • v${dev.client_version || '2.0.0'}</small>
              </div>
            </div>
            <div class="pulse-indicator ${isOnline ? 'pulse-green' : 'pulse-gray'}"></div>
          </div>

          <div class="device-body">
            <div class="meta-row">
              <span>Status:</span>
              ${modeBadge}
            </div>
            <div class="meta-row">
              <span>Traps Severed:</span>
              <strong style="color: #00e699;">${dev.distractions_blocked_today || 0}</strong>
            </div>
            <div class="meta-row">
              <span>Time Saved:</span>
              <strong>${dev.minutes_reclaimed_today || 0} mins</strong>
            </div>
            ${dev.battery_percentage !== undefined && dev.battery_percentage !== null ? `
              <div class="meta-row">
                <span>Battery:</span>
                <span>${dev.battery_percentage}% ${dev.is_charging ? '⚡' : '🔋'}</span>
              </div>
            ` : ''}
          </div>

          <div class="card-actions">
            <button class="btn btn-sm btn-outline" onclick="fleetController.triggerSingleDeviceLock('${dev.device_id}', 30)">
              🔒 Lock 30m
            </button>
            <button class="btn btn-sm btn-outline-danger" onclick="fleetController.promptEmergencyRelease('${dev.device_id}')">
              Emergency Release
            </button>
          </div>
        </div>
      `;
    });

    this.domElements.fleetContainer.innerHTML = html;
  }

  getPlatformIcon(platform) {
    switch ((platform || '').toLowerCase()) {
      case 'android': return '🤖';
      case 'chrome_extension':
      case 'extension': return '🌐';
      case 'windows': return '🪟';
      case 'macos': return '🍎';
      case 'linux': return '🐧';
      default: return '💻';
    }
  }

  /* =========================================================================
   * 3. FLEET-WIDE COMMAND DISPATCHER
   * ========================================================================= */

  dispatchFleetLock(durationMinutes, isStrict) {
    if (!confirm(`Engage ${durationMinutes}-minute STRICT FOCUS LOCK across all ${this.devices.size} fleet devices?`)) {
      return;
    }

    const payload = {
      action: 'BROADCAST_FLEET_LOCK',
      userId: this.currentUserId,
      durationMinutes: durationMinutes,
      isStrict: isStrict,
      timestamp: Date.now()
    };

    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(payload));
      this.showNotification('Fleet Command Dispatched', `Strict Lock pushed to ${this.devices.size} devices.`);
    } else {
      // Fallback HTTP
      fetch('/api/v1/fleet/lock', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      }).then(() => {
        this.showNotification('Fleet Command Dispatched', `Strict Lock pushed.`);
      });
    }
  }

  dispatchFleetBreak(breakMinutes) {
    const payload = {
      action: 'BROADCAST_FLEET_BREAK',
      userId: this.currentUserId,
      breakMinutes: breakMinutes
    };

    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(payload));
      this.showNotification('Break Mode Activated', `All devices transitioned to ${breakMinutes}m break.`);
    }
  }

  triggerSingleDeviceLock(deviceId, durationMinutes) {
    const payload = {
      action: 'TRIGGER_DEVICE_LOCK',
      userId: this.currentUserId,
      deviceId: deviceId,
      durationMinutes: durationMinutes
    };
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(payload));
    }
  }

  /* =========================================================================
   * 4. ACCOUNTABILITY PARTNER EMERGENCY OVERRIDE VAULT
   * ========================================================================= */

  onEmergencyRequestReceived(request) {
    this.pendingEmergencyRequests.push(request);
    this.updateEmergencyBadge();
    this.showNotification('🚨 Emergency Unlock Requested', `Device ${request.device_id} requested unlock: "${request.reason}"`);
  }

  updateEmergencyBadge() {
    if (!this.domElements.emergencyBadge) return;
    const count = this.pendingEmergencyRequests.length;
    this.domElements.emergencyBadge.textContent = count;
    if (count > 0) {
      this.domElements.emergencyBadge.classList.remove('hidden');
    } else {
      this.domElements.emergencyBadge.classList.add('hidden');
    }
  }

  openEmergencyVault() {
    if (!this.domElements.emergencyModal) return;
    this.domElements.emergencyModal.classList.remove('hidden');
    this.renderEmergencyList();
  }

  renderEmergencyList() {
    if (!this.domElements.emergencyList) return;

    if (this.pendingEmergencyRequests.length === 0) {
      this.domElements.emergencyList.innerHTML = `
        <div style="text-align: center; padding: 24px; color: #888;">
          <p>No pending emergency unlock requests.</p>
        </div>
      `;
      return;
    }

    let html = '';
    this.pendingEmergencyRequests.forEach((req) => {
      html += `
        <div class="emergency-item">
          <div>
            <strong>Device: ${this.escapeHtml(req.device_id)}</strong>
            <p style="color: #ff9f1c; font-style: italic; margin: 4px 0;">"${this.escapeHtml(req.reason)}"</p>
            <small style="color: #666;">Requested: ${new Date(req.requested_at * 1000).toLocaleTimeString()}</small>
          </div>
          <div style="display: flex; gap: 8px;">
            <button class="btn btn-sm btn-accent" onclick="fleetController.approveEmergencyRequest('${req.request_id}')">
              Approve Unlock 🔓
            </button>
            <button class="btn btn-sm btn-outline-danger" onclick="fleetController.rejectEmergencyRequest('${req.request_id}')">
              Reject
            </button>
          </div>
        </div>
      `;
    });

    this.domElements.emergencyList.innerHTML = html;
  }

  approveEmergencyRequest(requestId) {
    const partnerPin = prompt('Enter your 4-digit Accountability Partner PIN to confirm:');
    if (!partnerPin) return;

    fetch('/api/v1/fleet/emergency/approve', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        requestId: requestId,
        partnerEmail: this.partnerEmail,
        partnerPin: partnerPin
      })
    }).then(res => res.json()).then(data => {
      if (data.status === 'OK') {
        alert('Emergency Unlock Approved. Fleet lock released.');
        this.pendingEmergencyRequests = this.pendingEmergencyRequests.filter(r => r.request_id !== requestId);
        this.updateEmergencyBadge();
        this.renderEmergencyList();
        this.requestFleetSnapshot();
      } else {
        alert('Approval failed: ' + (data.message || 'Invalid PIN'));
      }
    });
  }

  rejectEmergencyRequest(requestId) {
    this.pendingEmergencyRequests = this.pendingEmergencyRequests.filter(r => r.request_id !== requestId);
    this.updateEmergencyBadge();
    this.renderEmergencyList();
  }

  promptEmergencyRelease(deviceId) {
    this.openEmergencyVault();
  }

  /* =========================================================================
   * 5. UTILITIES & HTTP FALLBACK
   * ========================================================================= */

  pollDevicesHttpFallback() {
    setInterval(() => {
      if (!this.connected) {
        fetch(`/api/v1/fleet/devices?userId=${this.currentUserId}`)
          .then(r => r.json())
          .then(data => {
            if (data.devices) this.renderFleetSnapshot(data.devices);
          })
          .catch(() => {});
      }
    }, 10000);
  }

  showNotification(title, message) {
    const toast = document.createElement('div');
    toast.className = 'admin-toast';
    toast.innerHTML = `<strong>${this.escapeHtml(title)}</strong><br><small>${this.escapeHtml(message)}</small>`;
    document.body.appendChild(toast);
    setTimeout(() => {
      toast.remove();
    }, 4000);
  }

  escapeHtml(str) {
    if (!str) return '';
    return String(str).replace(/[&<>"']/g, (m) => ({
      '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
    })[m]);
  }
}

// Global instance attached to window for inline onclick handlers
let fleetController = null;
document.addEventListener('DOMContentLoaded', () => {
  fleetController = new FleetController();
  window.fleetController = fleetController;
});
