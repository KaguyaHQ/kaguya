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
