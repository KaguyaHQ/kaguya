import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import test from "node:test"

const source = await readFile(new URL("../../assets/js/hooks/resend_countdown.js", import.meta.url))
const Hook = (await import(`data:text/javascript;base64,${source.toString("base64")}`)).default

function setup(t, remaining = 60_000, verified = true) {
  const widget = {dataset: {verified: String(verified)}}
  const form = {querySelector: () => widget}
  const button = {disabled: true, textContent: "Resend", dataset: {cooldownMs: String(remaining)},
    closest: () => form}
  const hook = {...Hook, el: button}
  hook.mounted()
  t.after(() => hook.destroyed())
  return {hook, button, widget}
}

test("the first confirmation page shows the server cooldown", t => {
  const {button} = setup(t)
  assert.equal(button.textContent, "Resend available in 60 seconds")
  assert.equal(button.disabled, true)
  assert.equal(button.dataset.cooldown, "true")
})

test("cooldown expiry allows resend only after Turnstile verification", t => {
  const {hook, button, widget} = setup(t, 60_000, false)
  hook.until = Date.now() - 1
  hook.tick()
  assert.equal(button.textContent, "Resend")
  assert.equal(button.disabled, true)
  assert.equal(button.dataset.cooldown, undefined)
  widget.dataset.verified = "true"
  hook.tick()
  assert.equal(button.disabled, false)
})

test("refreshing uses the remaining server time rather than restarting a minute", t => {
  const {button} = setup(t, 12_000)
  assert.equal(button.textContent, "Resend available in 12 seconds")
})

test("unrelated LiveView patches do not restart the countdown", t => {
  const {hook, button} = setup(t)
  const initial = hook.until
  hook.updated()
  assert.equal(hook.until, initial)
  button.dataset.cooldownMs = "15000"
  hook.updated()
  assert.equal(button.textContent, "Resend available in 15 seconds")
})

test("a failed security check has no recipient cooldown to display", t => {
  const {button} = setup(t, 0, false)
  assert.equal(button.textContent, "Resend")
  assert.equal(button.dataset.cooldown, undefined)
  assert.equal(button.disabled, true)
})
