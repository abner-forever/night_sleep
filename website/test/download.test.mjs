import { test } from 'node:test'
import assert from 'node:assert/strict'
import { createDownloadClient, selectLatestDownload, selectReleaseHistory, RELEASES_URL, STABLE_RELEASE_URL } from '../src/config/download.mjs'

function release(version = '0.49.0-beta.1', overrides = {}) {
  const tag = `v${version}`
  const name = `night-sleep-${version}-android.apk`
  return {
    tag_name: tag, draft: false, prerelease: version.includes('-'),
    published_at: '2026-10-20T00:00:00Z',
    assets: [{ name, state: 'uploaded', digest: `sha256:${'a'.repeat(64)}`,
      size: 60000000,
      browser_download_url: `https://github.com/abner-forever/night_sleep/releases/download/${tag}/${name}`,
    }], ...overrides,
  }
}
const response = (releases) => ({ ok: true, json: async () => releases })

test('识别真实 Beta Release 的版本、链接、体积和 GitHub SHA-256', () => {
  const item = release()
  const download = selectLatestDownload([item], 'beta')
  assert.equal(download.url, item.assets[0].browser_download_url)
  assert.equal(download.version, '0.49.0-beta.1')
  assert.equal(download.channel, 'beta')
  assert.equal(download.sha256, 'a'.repeat(64))
  assert.equal(download.size, 60000000)
})

test('按版本排序，包含 prerelease，忽略草稿、无 APK、未上传或校验信息无效的附件', () => {
  const invalid = (asset) => release('9.0.0', { assets: [{ ...release('9.0.0').assets[0], ...asset }] })
  const bad = [null, {}, release('9.0.0', { draft: true }), release('9.0.0', { assets: [] }),
    release('9.0.0', { published_at: null }), release('9.0.0', { assets: {} }),
    invalid({ digest: null }), invalid({ state: 'new' }), invalid({ size: 0 }),
    invalid({ browser_download_url: 'https://evil.example/app.apk' }),
    invalid({ browser_download_url: 'https://github.com/other/repo/releases/download/v9.0.0/app.apk' }),
    invalid({ browser_download_url: `${release('9.0.0').assets[0].browser_download_url}?redirect=1` }),
  ]
  assert.equal(selectLatestDownload(bad), null)
  assert.equal(selectLatestDownload([...bad, release(), release('0.49.0-beta.10'), release('0.49.0-beta.2')], 'beta').version, '0.49.0-beta.10')
  assert.equal(selectLatestDownload([release('0.49.0-beta.10'), release('0.49.0')]).channel, 'stable')
  assert.equal(selectLatestDownload([release('0.49.0'), release('0.50.0-beta.1')]).version, '0.49.0')
  assert.equal(selectLatestDownload([release()]), null)
  assert.equal(selectLatestDownload([release('0.49.0', { prerelease: true })]), null)
})

test('兼容已公开的首个 preview 包，但 Beta 版本必须使用版本化文件名', () => {
  const preview = release('0.49.0-preview.1')
  preview.assets[0].name = 'night-sleep-preview.apk'
  preview.assets[0].browser_download_url = 'https://github.com/abner-forever/night_sleep/releases/download/v0.49.0-preview.1/night-sleep-preview.apk'
  assert.equal(selectLatestDownload([preview], 'beta').version, '0.49.0-preview.1')
  assert.equal(selectLatestDownload([preview, release()], 'beta').version, '0.49.0-beta.1')
  assert.equal(selectLatestDownload([release('0.49.0-beta.1', { assets: preview.assets })], 'beta'), null)
})

test('历史版本按版本倒序，且与下载入口同样只收带 APK 与 SHA-256 的发布', () => {
  const bad = [null, {}, release('9.0.0', { draft: true }), release('9.0.0', { assets: [] }),
    release('9.0.0', { assets: [{ ...release('9.0.0').assets[0], digest: null }] })]
  const history = selectReleaseHistory([
    release('0.49.0'), release('0.50.0-beta.2'), release('0.50.0-beta.10'),
    release('0.49.0-beta.1'), ...bad,
  ])
  assert.deepEqual(history.map((item) => item.version),
    ['0.50.0-beta.10', '0.50.0-beta.2', '0.49.0', '0.49.0-beta.1'])
  assert.equal(history[0].publishedAt, '2026-10-20T00:00:00Z')
  assert.deepEqual(selectReleaseHistory(null), [])
})

test('版本历史随缓存一起返回，缓存命中时不必重新请求', async () => {
  let time = 1, calls = 0
  const releases = [release('0.50.0-beta.2'), release('0.50.0-beta.1'), release('0.49.0')]
  const client = createDownloadClient({ now: () => time, fetcher: async (url) => {
    calls++
    return response(url === STABLE_RELEASE_URL ? release('0.49.0') : releases)
  } })
  const first = await client.load()
  assert.deepEqual(first.history.map((item) => item.version),
    ['0.50.0-beta.2', '0.50.0-beta.1', '0.49.0'])
  const cached = await client.load()
  assert.deepEqual(cached.history, first.history)
  assert.equal(calls, 2)
})

test('并发合并、五分钟缓存，发布新版本后重新请求即可更新，无需改官网', async () => {
  let time = 1, calls = 0, latest = release()
  const client = createDownloadClient({ now: () => time, fetcher: async (url) => {
    calls++
    if (url === STABLE_RELEASE_URL) return response(release('0.48.0'))
    assert.equal(url, RELEASES_URL)
    return response([latest])
  } })
  const [first, same] = await Promise.all([client.load(), client.load()])
  assert.deepEqual(first, same)
  assert.equal(calls, 2)
  latest = release('0.49.0-beta.2')
  assert.equal((await client.load()).beta.version, '0.49.0-beta.1')
  time += 300001
  assert.equal((await client.load()).beta.version, '0.49.0-beta.2')
  assert.equal((await client.load()).download.version, '0.48.0')
  assert.equal(calls, 4)
  await client.load({ refresh: true })
  assert.equal(calls, 6)
})

test('限流或断网时提示失败，只回退一天内缓存，空发布列表会清除旧版本', async () => {
  let time = 1, mode = 'ok'
  const client = createDownloadClient({ now: () => time, fetcher: async (url) => {
    if (mode === 'fail') return { ok: false, status: 403 }
    if (url === STABLE_RELEASE_URL) return mode === 'empty' ? { ok: false, status: 404 } : response(release('0.48.0'))
    return response(mode === 'empty' ? [] : [release()])
  } })
  await client.load()
  mode = 'fail'
  time += 300001
  const cached = await client.load()
  assert(cached.failed && cached.stale && cached.download)
  time += 86400001
  assert.equal((await client.load()).download, null)
  mode = 'ok'
  await client.load({ refresh: true })
  mode = 'empty'
  assert.equal((await client.load({ refresh: true })).download, null)
  mode = 'fail'
  assert.equal((await client.load({ refresh: true })).download, null)
})

test('损坏或禁用的本地缓存不影响真实接口加载', async () => {
  for (const storage of [
    { getItem: () => '{', setItem: () => { throw Error('disabled') } },
    { getItem: () => JSON.stringify({ time: 1, releases: {} }) },
  ]) {
    const client = createDownloadClient({ storage, fetcher: async (url) => response(url === STABLE_RELEASE_URL ? release('0.48.0') : [release()]) })
    assert.equal((await client.load()).download.version, '0.48.0')
    assert.equal((await client.load()).beta.version, '0.49.0-beta.1')
  }
})

test('正式版从 latest 独立获取，避免连续 Beta 发布把正式版挤出列表', async () => {
  const releases = Array.from({ length: 30 }, (_, index) => release(`0.50.0-beta.${index + 1}`))
  const client = createDownloadClient({ fetcher: async (url) => response(url === STABLE_RELEASE_URL ? release('0.49.0') : releases) })
  const result = await client.load()
  assert.equal(result.download.version, '0.49.0')
  assert.equal(result.beta.version, '0.50.0-beta.30')
})

test('没有正式版时保持空状态，Beta 仅出现在独立入口', async () => {
  const client = createDownloadClient({ fetcher: async (url) => url === STABLE_RELEASE_URL
    ? { ok: false, status: 404 } : response([release()]) })
  const result = await client.load()
  assert.equal(result.download, null)
  assert.equal(result.beta.version, '0.49.0-beta.1')
  assert.equal(result.failed, false)
})

test('任一渠道网络失败不影响另一渠道，失败缓存不会被另一渠道续期', async () => {
  let time = 1, failStable = false
  const client = createDownloadClient({ now: () => time, fetcher: async (url) => {
    if (url === STABLE_RELEASE_URL) return failStable ? { ok: false, status: 503 } : response(release('0.49.0'))
    return response([release('0.50.0-beta.1')])
  } })
  await client.load()
  failStable = true
  time += 300001
  let result = await client.load()
  assert.equal(result.download.version, '0.49.0')
  assert.equal(result.stableFailed, true)
  assert.equal(result.betaFailed, false)
  time += 86400001
  result = await client.load()
  assert.equal(result.download, null)
  assert.equal(result.beta.version, '0.50.0-beta.1')
})
