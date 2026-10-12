import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import test from "node:test"

const source = await readFile(new URL("../../assets/js/hooks/turnstile.js", import.meta.url))
const {default: Hook, loadTurnstile} = await import(`data:text/javascript;base64,${source.toString("base64")}`)

function setup() {
  let callbacks
  const removed = []
  globalThis.window = {turnstile: {
    render: (_container, opts) => { callbacks = opts; return "widget-1" },
    remove: id => removed.push(id)
  }}
  const button = {disabled: true, dataset: {}}
  const input = {value: ""}
  const status = {textContent: ""}
  const retry = Object.assign(new EventTarget(), {hidden: true})
  const form = Object.assign(new EventTarget(), {querySelectorAll: () => [button]})
  const elements = {
    "input[name='cf-turnstile-response']": input,
    "[role='status']": status,
    "[data-turnstile-retry]": retry,
    "[data-turnstile-container]": {}
  }
  const el = {dataset: {siteKey: "public-key", action: "email_login"},
    closest: () => form, querySelector: selector => elements[selector]}
  const hook = {...Hook, el}
  hook.mounted()
  return {hook, input, status, retry, button, form, removed, callbacks: () => callbacks}
}

test("verification enables submission; expiry clears the token and enables retry", async () => {
  const s = setup()
  await Promise.resolve()
  s.callbacks().callback("token")
  assert.equal(s.input.value, "token")
  assert.equal(s.button.disabled, false)
  s.callbacks()["expired-callback"]()
  assert.equal(s.input.value, "")
  assert.equal(s.button.disabled, true)
  assert.equal(s.retry.hidden, false)
  s.hook.destroyed()
})

test("a LiveView patch and successful challenge cannot override a resend cooldown", async () => {
  const s = setup()
  await Promise.resolve()
  s.button.dataset.cooldown = "true"
  s.callbacks().callback("token")
  s.hook.updated()
  assert.equal(s.button.disabled, true)
  delete s.button.dataset.cooldown
  s.hook.updated()
  assert.equal(s.button.disabled, false)
  s.hook.destroyed()
})

test("submitting without verification is blocked and verified submission disables the button", async () => {
  const s = setup()
  await Promise.resolve()
  const event = new Event("submit", {cancelable: true})
  s.form.dispatchEvent(event)
  assert.equal(event.defaultPrevented, true)
  s.callbacks().callback("token")
  const verified = new Event("submit", {cancelable: true})
  s.form.dispatchEvent(verified)
  assert.equal(verified.defaultPrevented, false)
  assert.equal(s.button.disabled, true)
  s.hook.destroyed()
})

test("SDK errors clear the token and retry replaces the widget", async () => {
  const s = setup()
  await Promise.resolve()
  s.callbacks().callback("token")
  s.callbacks()["error-callback"]()
  assert.equal(s.input.value, "")
  assert.equal(s.button.disabled, true)
  await s.hook.renderWidget()
  assert.deepEqual(s.removed, ["widget-1"])
  s.hook.destroyed()
})

test("destruction removes the widget and submit listener and ignores later callbacks", async () => {
  const s = setup()
  await Promise.resolve()
  s.callbacks().callback("token")
  s.hook.destroyed()
  assert.equal(s.input.value, "token")
  assert.deepEqual(s.removed, ["widget-1"])
  const event = new Event("submit", {cancelable: true})
  s.form.dispatchEvent(event)
  assert.equal(event.defaultPrevented, false)
  s.callbacks().callback("late-token")
  assert.equal(s.input.value, "token")
})

test("the SDK loads once and can be retried after a network failure", async () => {
  globalThis.window = {}
  const scripts = []
  globalThis.document = {
    createElement: () => ({remove() { this.removed = true }}),
    head: {appendChild: script => scripts.push(script)}
  }
  const first = loadTurnstile()
  assert.equal(loadTurnstile(), first)
  assert.equal(scripts.length, 1)
  scripts[0].onerror()
  await assert.rejects(first)
  const retry = loadTurnstile()
  assert.equal(scripts.length, 2)
  const sdk = {ready: callback => callback()}
  window.turnstile = sdk
  scripts[1].onload()
  assert.equal(await retry, sdk)
})
