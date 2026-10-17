(function () {
  'use strict';

  const VERSION_URL = 'app-version.json';
  const CHECK_INTERVAL_MS = 60 * 1000;
  const embeddedVersion = document
    .querySelector('meta[name="gudex-build-version"]')
    ?.getAttribute('content');
  let currentVersion = embeddedVersion && !embeddedVersion.startsWith('__')
    ? embeddedVersion
    : null;
  let checking = false;
  let dismissedVersion = null;

  function versionUrl() {
    const url = new URL(VERSION_URL, document.baseURI);
    url.searchParams.set('check', Date.now().toString());
    return url.toString();
  }

  async function fetchVersion() {
    const response = await fetch(versionUrl(), {
      cache: 'no-store',
      headers: { 'Cache-Control': 'no-cache' },
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const payload = await response.json();
    return typeof payload.version === 'string' ? payload.version.trim() : '';
  }

  function showUpdate(version) {
    if (document.getElementById('gudex-update-notice')) return;
    if (dismissedVersion === version) return;

    const notice = document.createElement('section');
    notice.id = 'gudex-update-notice';
    notice.setAttribute('role', 'status');
    notice.setAttribute('aria-live', 'polite');
    notice.innerHTML = `
      <div class="gudex-update-copy">
        <strong>Nueva versión disponible</strong>
        <span>Actualiza Gudex para aplicar las últimas mejoras.</span>
      </div>
      <div class="gudex-update-actions">
        <button type="button" data-action="later">Después</button>
        <button type="button" data-action="update">Actualizar</button>
      </div>
    `;

    notice.querySelector('[data-action="later"]').addEventListener('click', () => {
      dismissedVersion = version;
      notice.remove();
    });
    notice.querySelector('[data-action="update"]').addEventListener('click', () => {
      notice.querySelector('[data-action="update"]').textContent = 'Actualizando…';
      const destination = new URL(window.location.href);
      destination.searchParams.set('_update', version);
      window.location.replace(destination.toString());
    });
    document.body.appendChild(notice);
  }

  async function checkForUpdate() {
    if (checking || !navigator.onLine) return;
    checking = true;
    try {
      const latestVersion = await fetchVersion();
      if (!latestVersion) return;
      if (currentVersion === null) {
        currentVersion = latestVersion;
        return;
      }
      if (latestVersion !== currentVersion) showUpdate(latestVersion);
    } catch (error) {
      console.debug('No se pudo comprobar una actualización de Gudex.', error);
    } finally {
      checking = false;
    }
  }

  window.addEventListener('load', checkForUpdate);
  window.addEventListener('focus', checkForUpdate);
  window.addEventListener('online', checkForUpdate);
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') checkForUpdate();
  });
  window.setInterval(checkForUpdate, CHECK_INTERVAL_MS);
})();
