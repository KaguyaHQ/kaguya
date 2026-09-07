import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import test from "node:test"

globalThis.window = Object.assign(new EventTarget(), {
  location: {href: "http://localhost/character/example/edit"},
  history: {state: {}, pushState() {}},
  confirm: () => false
})
globalThis.document = new EventTarget()
const source = await readFile(new URL("../../assets/js/hooks/unsaved_changes.js", import.meta.url))
const Hook = (await import(`data:text/javascript;base64,${source.toString("base64")}`)).default

function setup(t) {
  const name = {name: "character[name]", type: "text", value: "Original", hasAttribute: () => false}
  const search = {name: "appearance_query", type: "search", value: "", hasAttribute: () => true}
  const fields = [name, search]
  const el = Object.assign(new EventTarget(), {
    dataset: {dirty: "false"},
    querySelectorAll: () => fields,
    contains: field => fields.includes(field)
  })
  const guard = {...Hook, el}
  guard.mounted()
  t.after(() => guard.destroyed())
  return {guard, name, search, fields}
}

test("typing protects pending edits immediately and restoring the value clears the warning", t => {
  const {guard, name} = setup(t)
  name.value = "Corrected"
  guard._onInput({target: name})
  assert.equal(guard._isDirty(), true)
  name.value = "Original"
  guard._onInput({target: name})
  assert.equal(guard._isDirty(), false)
})

test("searching for an appearance alone is not an unsaved edit", t => {
  const {guard, search} = setup(t)
  search.value = "Clannad"
  guard._onInput({target: search})
  guard.updated()
  assert.equal(guard._isDirty(), false)
})

test("server-side relationship changes stay protected until reverted", t => {
  const {guard} = setup(t)
  guard.el.dataset.dirty = "true"
  guard.updated()
  assert.equal(guard._isDirty(), true)
  guard.el.dataset.dirty = "false"
  guard.updated()
  assert.equal(guard._isDirty(), false)
})

test("canceling navigation preserves the guard; new-tab help does not interrupt editing", t => {
  const {guard, name} = setup(t)
  name.value = "Unsaved"
  guard._onInput({target: name})
  const confirm = t.mock.method(window, "confirm", () => false)
  const link = {
    href: "http://localhost/help/characters", target: "_blank", dataset: {},
    hasAttribute: () => false, getAttribute: () => "/help/characters"
  }
  let prevented = false
  const event = {
    button: 0, target: {closest: () => link},
    preventDefault() { prevented = true }, stopImmediatePropagation() {}
  }
  guard._onClick(event)
  assert.equal(confirm.mock.callCount(), 0)
  link.target = ""
  guard._onClick(event)
  assert.equal(prevented, true)
  assert.equal(guard._isDirty(), true)
})

test("confirming a link departure does not prompt a second time on unload", t => {
  const {guard, name} = setup(t)
  name.value = "Unsaved"
  guard._onInput({target: name})
  t.mock.method(window, "confirm", () => true)
  const link = {
    href: "https://example.com", target: "", dataset: {},
    hasAttribute: () => false, getAttribute: () => "https://example.com"
  }
  guard._onClick({button: 0, target: {closest: () => link}})
  let warned = false
  guard._onBeforeUnload({preventDefault() { warned = true }})
  assert.equal(warned, false)
})
