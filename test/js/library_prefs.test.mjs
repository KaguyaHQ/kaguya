import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import test from "node:test"

const source = await readFile(new URL("../../assets/js/hooks/library_prefs.js", import.meta.url))
const LibraryPrefs = (await import(`data:text/javascript;base64,${source.toString("base64")}`)).default

function setup(t, owner, loggedIn = true) {
  const storage = new Map([["fadeReadLibrary", "true"], ["showDatesLibrary", "true"]])
  const original = globalThis.localStorage
  globalThis.localStorage = {
    getItem: key => storage.get(key) ?? null,
    setItem: (key, value) => storage.set(key, value)
  }
  t.after(() => { globalThis.localStorage = original })
  const listeners = new Map()
  const el = {
    dataset: {isOwner: String(owner), isLoggedIn: String(loggedIn), fadeRead: "false", showDates: "false"},
    addEventListener: (name, fn) => listeners.set(name, fn),
    removeEventListener: name => listeners.delete(name)
  }
  const events = []
  const hook = {...LibraryPrefs, el, pushEvent: (name, payload) => events.push([name, payload.value])}
  hook.mounted()
  t.after(() => hook.destroyed())
  const click = selector => listeners.get("click")({target: {closest: candidate => selector === candidate}})
  return {hook, storage, events, click}
}

for (const [owner, loggedIn, event] of [[true, true, "set_show_dates"], [false, true, "set_fade_read"], [false, false, null]]) {
  test(`library patches preserve preferences for owner=${owner}, signedIn=${loggedIn}`, t => {
    const {hook, storage, events} = setup(t, owner, loggedIn)
    assert.deepEqual(events, event ? [[event, true]] : [])
    hook.updated() // An unrelated patch can arrive before the restore is acknowledged.
    assert.equal(storage.get("fadeReadLibrary"), "true")
    assert.equal(storage.get("showDatesLibrary"), "true")
    assert.deepEqual(events, event ? [[event, true]] : [])
  })
}

test("rapid toggles use the latest choice and persist only that preference", t => {
  const {hook, storage, events, click} = setup(t, true)
  click("[data-show-dates-toggle]")
  hook.updated()
  click("[data-show-dates-toggle]")
  assert.deepEqual(events, [["set_show_dates", true], ["set_show_dates", false], ["set_show_dates", true]])
  assert.equal(storage.get("showDatesLibrary"), "true")
  assert.equal(storage.get("fadeReadLibrary"), "true")
})

test("changing profile ownership restores the newly applicable preference", t => {
  const {hook, events} = setup(t, true)
  hook.el.dataset.isOwner = "false"
  hook.updated()
  assert.deepEqual(events, [["set_show_dates", true], ["set_fade_read", true]])
})
