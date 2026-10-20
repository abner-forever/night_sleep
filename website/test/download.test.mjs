import { test } from 'node:test'
import assert from 'node:assert/strict'
import { createDownloadClient, selectLatestDownload, RELEASES_URL } from '../src/config/download.mjs'

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
  const download = selectLatestDownload([item])
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
  assert.equal(selectLatestDownload([...bad, release(), release('0.49.0-beta.10'), release('0.49.0-beta.2')]).version, '0.49.0-beta.10')
  assert.equal(selectLatestDownload([release('0.49.0-beta.10'), release('0.49.0')]).channel, 'stable')
  assert.equal(selectLatestDownload([release('0.49.0'), release('0.50.0-beta.1')]).version, '0.50.0-beta.1')
})

test('兼容已公开的首个 preview 包，但 Beta 版本必须使用版本化文件名', () => {
  const preview = release('0.49.0-preview.1')
  preview.assets[0].name = 'night-sleep-preview.apk'
  preview.assets[0].browser_download_url = 'https://github.com/abner-forever/night_sleep/releases/download/v0.49.0-preview.1/night-sleep-preview.apk'
  assert.equal(selectLatestDownload([preview]).version, '0.49.0-preview.1')
  assert.equal(selectLatestDownload([preview, release()]).version, '0.49.0-beta.1')
  assert.equal(selectLatestDownload([release('0.49.0-beta.1', { assets: preview.assets })]), null)
})

test('并发合并、五分钟缓存，发布新版本后重新请求即可更新，无需改官网', async () => {
  let time = 1, calls = 0, latest = release()
  const client = createDownloadClient({ now: () => time, fetcher: async (url) => {
    assert.equal(url, RELEASES_URL)
    calls++
    return response([latest])
  } })
  const [first, same] = await Promise.all([client.load(), client.load()])
  assert.deepEqual(first, same)
  assert.equal(calls, 1)
  latest = release('0.49.0-beta.2')
  assert.equal((await client.load()).download.version, '0.49.0-beta.1')
  time += 300001
  assert.equal((await client.load()).download.version, '0.49.0-beta.2')
  assert.equal(calls, 2)
  await client.load({ refresh: true })
  assert.equal(calls, 3)
})

test('限流或断网时提示失败，只回退一天内缓存，空发布列表会清除旧版本', async () => {
  let time = 1, mode = 'ok'
  const client = createDownloadClient({ now: () => time, fetcher: async () => {
    if (mode === 'fail') return { ok: false, status: 403 }
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
    const client = createDownloadClient({ storage, fetcher: async () => response([release()]) })
    assert.equal((await client.load()).download.version, '0.49.0-beta.1')
  }
})
