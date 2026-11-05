const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
function element() {
  return { children: [], textContent: '', append(...nodes) { this.children.push(...nodes); }, replaceChildren(...nodes) { this.children = nodes; }, addEventListener() {}, setAttribute() {} };
}
test('OSS version registry takes priority over divergent website preview manifests', async () => {
  const nodes = new Map();
  const release = (version, build) => ({version, build, publishedAt: '2026-11-05T00:00:00Z', notes: ['更新'], downloads: [{platform: 'windows', arch: 'x64', url: `https://tbtparent-me.oss-cn-hangzhou.aliyuncs.com/Download/inkflow/releases/${version}/InkFlow.exe`}]});
  const document = {querySelectorAll: () => [], getElementById(id) { if (!nodes.has(id)) nodes.set(id, element()); return nodes.get(id); }, createElement: element};
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../website/app.js'), 'utf8'), {
    document, navigator: {platform: 'Win32'}, URL, AbortController, setTimeout, clearTimeout,
    fetch: async (url) => { const value = url.startsWith('./') ? release('9.0.0', 99) : release('0.1.1', 2); return {ok: true, json: async () => url.endsWith('releases.json') ? {releases: [value]} : value}; },
  });
  await new Promise(setImmediate);
  assert.match(nodes.get('release-status').textContent, /0\.1\.1/);
  const links = [];
  function visit(node) { if (node.href) links.push(node.href); for (const child of node.children || []) visit(child); }
  visit(nodes.get('downloads'));
  assert(links.some(url => url.includes('/0.1.1/')));
  assert(!links.some(url => url.includes('/0.1.0/')));
});
