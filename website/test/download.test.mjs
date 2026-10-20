import { test } from 'node:test'
import assert from 'node:assert/strict'
import { parseDownload } from '../src/config/download.mjs'

const released = {
  available: true,
  url: 'https://github.com/abner-forever/night_sleep/releases/download/v0.49.0/night-sleep.apk',
  version: '0.49.0',
  sha256: 'a'.repeat(64),
  size: 60000000,
}
test('未发布、错误协议、缺失校验或无效响应均不开放下载', () => {
  for (const item of [
    null,
    {},
    { ...released, available: false },
    { ...released, url: 'javascript:alert(1)' },
    { ...released, url: 'https://example.com/pending' },
    { ...released, sha256: '' },
    { ...released, version: '' },
    { ...released, size: 0 },
  ]) {
    assert.equal(parseDownload(item), null)
  }
})
test('完整发布元数据生成有效 APK 下载信息', () => {
  assert.equal(parseDownload(released).url, released.url)
})
