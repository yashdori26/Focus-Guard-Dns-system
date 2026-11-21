/**
 * FocusDNS Extension Options Controller
 */

'use strict';

document.addEventListener('DOMContentLoaded', async () => {
  const inputUserId = document.getElementById('input-user-id');
  const inputDeviceId = document.getElementById('input-device-id');
  const inputDaemonUrl = document.getElementById('input-daemon-url');
  const inputWhitelist = document.getElementById('input-whitelist');
  const inputBlacklist = document.getElementById('input-blacklist');
  const inputPartnerEmail = document.getElementById('input-partner-email');
  const btnSave = document.getElementById('btn-save');
  const toast = document.getElementById('toast');

  // Load existing settings
  const stored = await chrome.storage.local.get([
    'userId',
    'pairedDeviceId',
    'customWhitelistedDomains',
    'customBlockedDomains',
    'accountabilityPartnerEmail',
    'daemonUrl'
  ]);

  if (stored.userId) inputUserId.value = stored.userId;
  if (stored.pairedDeviceId) inputDeviceId.value = stored.pairedDeviceId;
  if (stored.daemonUrl) inputDaemonUrl.value = stored.daemonUrl;
  if (stored.accountabilityPartnerEmail) inputPartnerEmail.value = stored.accountabilityPartnerEmail;
  if (stored.customWhitelistedDomains) inputWhitelist.value = stored.customWhitelistedDomains.join('\n');
  if (stored.customBlockedDomains) inputBlacklist.value = stored.customBlockedDomains.join('\n');

  btnSave.addEventListener('click', async () => {
    const whitelist = inputWhitelist.value.split('\n').map(s => s.trim().toLowerCase()).filter(Boolean);
    const blacklist = inputBlacklist.value.split('\n').map(s => s.trim().toLowerCase()).filter(Boolean);

    await chrome.storage.local.set({
      userId: inputUserId.value.trim(),
      pairedDeviceId: inputDeviceId.value.trim(),
      daemonUrl: inputDaemonUrl.value.trim(),
      accountabilityPartnerEmail: inputPartnerEmail.value.trim(),
      customWhitelistedDomains: whitelist,
      customBlockedDomains: blacklist
    });

    // Notify background worker
    chrome.runtime.sendMessage({
      action: 'PAIR_DEVICE',
      payload: {
        userId: inputUserId.value.trim(),
        deviceId: inputDeviceId.value.trim()
      }
    });

    chrome.runtime.sendMessage({
      action: 'POLICY_UPDATE',
      customBlockedDomains: blacklist,
      customWhitelistedDomains: whitelist
    });

    showToast();
  });

  function showToast() {
    toast.classList.remove('hidden');
    setTimeout(() => {
      toast.classList.add('hidden');
    }, 2500);
  }
});
