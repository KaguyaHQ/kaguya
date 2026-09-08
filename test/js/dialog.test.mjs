import assert from 'node:assert/strict'
import {readFile} from 'node:fs/promises'
import test from 'node:test'

const source = await readFile(new URL('../../assets/js/lib/dialog_controller.js', import.meta.url))
const {createDialogController} = await import(`data:text/javascript;base64,${source.toString('base64')}`)

function setup(t) {
  const trigger = {isConnected: true, focus() { document.activeElement = this }}
  globalThis.document = {documentElement: {dataset: {}}, body: {dataset: {}}, activeElement: trigger}
  const controllers = []
  t.after(() => controllers.reverse().forEach(controller => controller.destroy()))
  function dialog() {
    const el = Object.assign(new EventTarget(), {
      dataset: {}, isConnected: true, open: false,
      showModal() { this.open = true; document.activeElement = this },
      close() { this.open = false },
      focus() { document.activeElement = this },
      closest(selector) { return selector === 'dialog' ? this : null },
      querySelector() { return null },
      getBoundingClientRect() { return {left: 100, right: 300, top: 100, bottom: 300} }
    })
    let closes = 0
    const controller = createDialogController(el, () => closes++)
    controllers.push(controller)
    const fire = (type, x = 150, y = 150) => {
      const event = Object.assign(new Event(type, {cancelable: true}), {clientX: x, clientY: y})
      el.dispatchEvent(event)
      return event
    }
    return {el, controller, fire, closes: () => closes}
  }
  return {dialog, trigger}
}

test('nested dialogs retain scroll lock until the last closes and restore invoking focus', t => {
  const {dialog, trigger} = setup(t)
  const parent = dialog(); const child = dialog()
  parent.controller.open(); child.controller.open()
  child.controller.close()
  assert.equal(document.activeElement, parent.el)
  assert.ok('modalScrollLocked' in document.documentElement.dataset)
  parent.controller.close()
  assert.equal(document.activeElement, trigger)
  assert.equal(document.documentElement.dataset.modalScrollLocked, undefined)
})

test('cancel policy blocks Escape and backdrop dismissal but allows explicit close', t => {
  const {dialog} = setup(t); const d = dialog()
  d.el.dataset.dismissable = 'false'; d.controller.open()
  assert.equal(d.fire('cancel').defaultPrevented, true)
  d.fire('pointerdown', 0, 0); d.fire('click', 0, 0)
  assert.equal(d.el.open, true)
  d.controller.close()
  assert.equal(d.closes(), 1)
})

test('native close and repeated close requests notify once', t => {
  const {dialog} = setup(t); const d = dialog()
  d.controller.open(); d.controller.close(); d.fire('close'); d.controller.close()
  assert.equal(d.closes(), 1)
  d.controller.open(); d.el.close(); d.fire('close')
  assert.equal(d.closes(), 2)
  assert.equal(document.body.dataset.modalScrollLocked, undefined)
})

test('panel padding and a drag ending on the backdrop do not dismiss', t => {
  const {dialog} = setup(t); const d = dialog(); d.controller.open()
  d.fire('pointerdown'); d.fire('click')
  d.fire('pointerdown'); d.fire('click', 0, 0)
  assert.equal(d.closes(), 0)
  d.fire('pointerdown', 0, 0); d.fire('click', 0, 0)
  assert.equal(d.closes(), 1)
})

test('destroy releases locks without sending a server close event', t => {
  const {dialog} = setup(t); const d = dialog(); d.controller.open()
  d.controller.destroy(); d.fire('close')
  assert.equal(d.closes(), 0)
  assert.equal(document.documentElement.dataset.modalScrollLocked, undefined)
})
