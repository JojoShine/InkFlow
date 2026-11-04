(() => {
  'use strict';
  const RELEASE_BASE = 'https://tbtparent-me.oss-cn-hangzhou.aliyuncs.com/Download/inkflow/';
  const themes = {
    paper: '温暖书房 · 暖纸与细纤维',
    forest: '雾林晨光 · 晨雾与松绿',
    pixel: '像素原野 · 草木与晨光',
    sakura: '樱下手札 · 水彩与樱花',
  };
  document.querySelectorAll('[data-theme]').forEach(button => {
    button.addEventListener('click', () => {
      document.querySelectorAll('[data-theme]').forEach(item => {
        item.setAttribute('aria-pressed', String(item === button));
      });
      document.getElementById('theme-stage').dataset.current = button.dataset.theme;
      document.getElementById('theme-status').textContent = themes[button.dataset.theme];
    });
  });

  const platformNames = { macos: 'macOS', windows: 'Windows' };
  const architectureNames = { arm64: 'ARM64', x64: 'x64' };
  const detectedPlatform = /Mac/i.test(navigator.platform || '') ? 'macos'
    : /Win/i.test(navigator.platform || '') ? 'windows' : null;
  const platformOrder = detectedPlatform === 'windows' ? ['windows', 'macos'] : ['macos', 'windows'];
  const node = (tag, text, className) => {
    const element = document.createElement(tag);
    if (text !== undefined) element.textContent = text;
    if (className) element.className = className;
    return element;
  };
  function safeDownload(item) {
    if (!item || !Object.hasOwn(platformNames, item.platform) || !Object.hasOwn(architectureNames, item.arch) || typeof item.url !== 'string') return false;
    try {
      const url = new URL(item.url);
      const base = new URL(RELEASE_BASE);
      const path = decodeURIComponent(url.pathname);
      return url.protocol === 'https:' && url.origin === base.origin && !url.username && !url.password
        && url.pathname.startsWith(base.pathname) && path.startsWith(base.pathname)
        && !path.includes('..') && !path.includes('\\') && !url.search && !url.hash
        && (item.platform === 'macos' ? /\.(zip|dmg)$/i : /\.(exe|zip)$/i).test(path);
    } catch { return false; }
  }
  function normalizeRelease(data) {
    if (!data || typeof data.version !== 'string' || !data.version.trim() || !Array.isArray(data.downloads)
      || !Array.isArray(data.notes) || !data.notes.every(note => typeof note === 'string')
      || !['string', 'number'].includes(typeof data.build) || typeof data.publishedAt !== 'string'
      || !Number.isFinite(Date.parse(data.publishedAt))) return null;
    return { ...data, downloads: data.downloads.filter(safeDownload) };
  }
  async function fetchManifest(file, normalize) {
    for (const source of [`./${file}`, `${RELEASE_BASE}${file}`]) {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 6500);
      try {
        const response = await fetch(source, { signal: controller.signal, cache: 'no-cache', credentials: 'omit' });
        if (!response.ok) continue;
        const value = normalize(await response.json());
        if (value) return value;
      } catch { /* Try the release bucket if the same-origin manifest is unavailable. */ }
      finally { clearTimeout(timeout); }
    }
    return null;
  }
  function readableSize(value) {
    if (typeof value === 'number' && Number.isFinite(value) && value > 0) return `${(value / 1048576).toFixed(1)} MB`;
    return typeof value === 'string' && value.trim() ? value : '';
  }
  function dateLabel(value) {
    return new Date(value).toLocaleDateString('zh-CN', { year: 'numeric', month: 'long', day: 'numeric' });
  }
  function packageLabel(item) {
    const architecture = item.platform === 'macos'
      ? (item.arch === 'arm64' ? 'Apple 芯片' : 'Intel 芯片')
      : architectureNames[item.arch];
    return `${platformNames[item.platform]} · ${architecture}`;
  }
  function notesList(notes) {
    const list = node('ul');
    notes.forEach(note => list.append(node('li', note)));
    return list;
  }
  function renderDownloads(release) {
    const container = document.getElementById('downloads');
    container.replaceChildren();
    platformOrder.forEach(platform => {
      const packages = release ? release.downloads.filter(item => item.platform === platform) : [];
      if (!packages.length) {
        const card = node('div', undefined, 'download-item');
        const label = node('div');
        label.append(node('h3', platformNames[platform]), node('p', platform === 'macos' ? 'Apple 芯片 / Intel 芯片' : 'x64 / ARM64'));
        card.append(label, node('span', release ? '暂不可用' : '尚未发布', 'unavailable'));
        container.append(card);
      }
      packages.forEach(item => {
        const card = node('div', undefined, 'download-item');
        const label = node('div');
        const size = readableSize(item.size);
        label.append(node('h3', packageLabel(item)), node('p', [`v${release.version}`, size].filter(Boolean).join(' · ')));
        if (typeof item.sha256 === 'string' && /^[a-f\d]{64}$/i.test(item.sha256)) {
          const checksum = node('details', undefined, 'checksum');
          checksum.append(node('summary', 'SHA-256 校验值'), node('code', item.sha256));
          label.append(checksum);
        }
        const link = node('a', '下载安装包 ↗', 'button primary');
        link.href = item.url;
        link.setAttribute('aria-label', `下载 ${packageLabel(item)} v${release.version}`);
        card.append(label, link);
        container.append(card);
      });
    });
  }
  function renderLatest(release) {
    document.getElementById('release-status').textContent = release
      ? `最新版本 v${release.version} · ${dateLabel(release.publishedAt)} · 构建 ${release.build}`
      : '暂未获取到发布清单。当前没有可用的下载地址，请稍后重新检查。';
    renderDownloads(release);
    const notes = document.getElementById('latest-notes');
    notes.replaceChildren();
    if (release && release.notes.length) notes.append(node('h3', '这个版本更新了什么'), notesList(release.notes));
  }
  function renderHistory(releases) {
    const container = document.getElementById('release-history');
    container.replaceChildren();
    if (!releases || !releases.length) {
      container.append(node('p', '暂未获取到历史更新。发布后，版本说明会出现在这里。', 'empty-message'));
      return;
    }
    releases.forEach(release => {
      const entry = node('details', undefined, 'release-entry');
      const summary = node('summary', `InkFlow ${release.version}`);
      const time = node('time', dateLabel(release.publishedAt));
      time.dateTime = release.publishedAt;
      summary.append(time);
      entry.append(summary, notesList(release.notes));
      const links = node('div', undefined, 'history-downloads');
      release.downloads.forEach(item => {
        const link = node('a', `${packageLabel(item)} ↗`);
        link.href = item.url;
        links.append(link);
      });
      if (!release.downloads.length) links.append(node('span', '此版本暂无可用安装包'));
      entry.append(links);
      container.append(entry);
    });
  }
  async function refresh() {
    const button = document.getElementById('refresh-releases');
    button.disabled = true;
    document.getElementById('release-status').textContent = '正在查看可用版本…';
    const latestTask = fetchManifest('latest.json', normalizeRelease).then(renderLatest);
    const historyTask = fetchManifest('releases.json', data => {
      if (!data || !Array.isArray(data.releases)) return null;
      const releases = data.releases.map(normalizeRelease);
      if (releases.some(release => !release)) return null;
      return releases.sort((a, b) => Date.parse(b.publishedAt) - Date.parse(a.publishedAt));
    }).then(renderHistory);
    await Promise.all([latestTask, historyTask]);
    button.disabled = false;
  }
  document.getElementById('refresh-releases').addEventListener('click', refresh);
  refresh();
})();
