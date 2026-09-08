import assert from 'node:assert/strict'
import {readFile} from 'node:fs/promises'
import test from 'node:test'

const source = await readFile(new URL('../../assets/js/hooks/gallery.js', import.meta.url))
const Gallery = (await import(`data:text/javascript;base64,${source.toString('base64')}`)).default

test('a horizontal swipe forwards one navigation click and cancels the synthetic touch click', () => {
  let next = 0
  globalThis.Element = class {}
  globalThis.HTMLElement = class extends Element {}
  globalThis.document = new EventTarget()
  globalThis.requestAnimationFrame = () => {}
  const stage = new Element()
  stage.closest = selector => selector === '[data-media-stage]' ? stage : null
  const button = new HTMLElement()
  button.closest = () => null
  const root = Object.assign(new EventTarget(), {
    querySelector: selector => selector === '[data-modal-next]' ? button : null
  })
  button.click = () => {
    const click = new Event('click', {cancelable: true})
    Object.defineProperty(click, 'target', {value: button})
    root.dispatchEvent(click)
    if (!click.defaultPrevented && !click.cancelBubble) next++
  }
  const hook = {...Gallery, el: root}
  hook.mounted()
  try {
    hook._onTouchStart({target: stage, changedTouches: [{clientX: 300, clientY: 100}]})
    let prevented = false
    hook._onTouchEnd({changedTouches: [{clientX: 100, clientY: 110}], preventDefault() {prevented = true}})
    assert.equal(next, 1)
    assert.equal(prevented, true)
    hook._onTouchStart({target: stage, changedTouches: [{clientX: 300, clientY: 100}]})
    hook._onTouchEnd({changedTouches: [{clientX: 290, clientY: 250}], preventDefault() {assert.fail('vertical scrolling must not navigate')}})
    assert.equal(next, 1)
  } finally {hook.destroyed()}
})
