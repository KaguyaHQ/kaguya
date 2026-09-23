import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import test from "node:test"

async function loadHook(name) {
  const source = await readFile(new URL(`../../assets/js/hooks/${name}.js`, import.meta.url))
  const namedSource = `${source}\n//# sourceURL=${name}.js`
  return (await import(`data:text/javascript;base64,${Buffer.from(namedSource).toString("base64")}`)).default
}

const MarkdownEditor = await loadHook("markdown_editor")
const DraftClear = await loadHook("draft_clear")

function setup(t) {
  t.mock.timers.enable({apis: ["setTimeout"]})
  // Node 20's experimental timer mock throws on clearTimeout(null/undefined),
  // unlike browsers. Preserve the browser's harmless no-op for absent timers.
  const clearTimer = globalThis.clearTimeout
  t.mock.method(globalThis, "clearTimeout", id => {
    if (id != null) clearTimer(id)
  })
  const storage = new Map()
  const previousWindow = globalThis.window
  globalThis.window = Object.assign(new EventTarget(), {
    localStorage: {
      getItem: key => storage.get(key) ?? null,
      setItem: (key, value) => storage.set(key, value),
      removeItem: key => storage.delete(key)
    }
  })
  t.after(() => { globalThis.window = previousWindow })

  const textarea = Object.assign(new EventTarget(), {value: "My unsaved review"})
  const el = Object.assign(new EventTarget(), {
    dataset: {draftKey: "review:one"},
    querySelector: () => null
  })
  const editor = {
    ...MarkdownEditor, el, textarea,
    handleEvent() {}, _bindTextarea() {}, _sync() {}, _restoreDraft() {}
  }
  editor.mounted()
  const button = Object.assign(new EventTarget(), {dataset: {draftKey: "review:one"}})
  const clear = {...DraftClear, el: button}
  clear.mounted()
  t.after(() => clear.destroyed())
  return {editor, storage, discard: () => button.dispatchEvent(new Event("click"))}
}

for (const elapsed of [0, 400]) {
  test(`deleting a draft after ${elapsed}ms prevents resurrection on teardown`, t => {
    const {editor, storage, discard} = setup(t)
    editor._onInput()
    t.mock.timers.tick(elapsed)
    discard()
    t.mock.timers.tick(400)
    editor.destroyed()
    assert.equal(storage.has("review:one"), false)
  })
}

test("ordinary dismissal flushes the last unsaved keystrokes", t => {
  const {editor, storage} = setup(t)
  editor._onInput()
  editor.destroyed()
  assert.equal(storage.get("review:one"), "My unsaved review")
})

test("clearing a different review leaves the current draft intact", t => {
  const {editor, storage} = setup(t)
  editor._onInput()
  window.dispatchEvent(new CustomEvent("kaguya:markdown-draft-clear", {detail: {key: "review:two"}}))
  editor.destroyed()
  assert.equal(storage.get("review:one"), "My unsaved review")
})

test("typing after a cleared draft starts saving again", t => {
  const {editor, storage, discard} = setup(t)
  editor._onInput()
  discard()
  editor.textarea.value = "Further edits after a failed delete"
  editor._onInput()
  editor.destroyed()
  assert.equal(storage.get("review:one"), "Further edits after a failed delete")
})

function composer(t, collapsible = true) {
  const previousWindow = globalThis.window
  globalThis.window = new EventTarget()
  const actions = {style: {display: ""}}
  const submit = {disabled: true}
  const textarea = Object.assign(new EventTarget(), {
    value: "", style: {}, scrollHeight: 0, blur() {}
  })
  const el = Object.assign(new EventTarget(), {
    dataset: {collapsible: String(collapsible)},
    querySelector(selector) {
      if (selector === "textarea") return textarea
      if (selector === "[data-markdown-editor-actions]") return actions
      return submit
    }
  })
  const editor = {...MarkdownEditor, el, handleEvent() {}}
  editor.mounted()
  t.after(() => {
    editor.destroyed()
    globalThis.window = previousWindow
  })
  return {editor, el, textarea, actions, submit}
}

test("top-level composer opens, cancels, stays collapsed after a patch, and reopens", t => {
  const {editor, el, textarea, actions, submit} = composer(t)
  assert.equal(actions.style.display, "none")
  el.dispatchEvent(new Event("focusin"))
  assert.equal(actions.style.display, "")
  textarea.value = "Discard this draft"
  textarea.dispatchEvent(new Event("input"))
  assert.equal(submit.disabled, false)
  el.dispatchEvent(new Event("kaguya:reply-input-cancel"))
  assert.equal(textarea.value, "")
  assert.equal(submit.disabled, true)
  assert.equal(actions.style.display, "none")
  actions.style.display = ""
  editor.updated()
  assert.equal(actions.style.display, "none")
  el.dispatchEvent(new Event("focusin"))
  assert.equal(actions.style.display, "")
})

test("a patch preserves an open draft and reply/edit actions do not collapse", t => {
  const {editor, el, textarea, actions} = composer(t, false)
  textarea.value = "Keep this draft"
  editor.updated()
  assert.equal(textarea.value, "Keep this draft")
  assert.equal(actions.style.display, "")
  el.dispatchEvent(new Event("kaguya:reply-input-cancel"))
  assert.equal(textarea.value, "")
  assert.equal(actions.style.display, "")
})
