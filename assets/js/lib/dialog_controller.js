// Native showModal owns stacking, background inertness and focus containment.
// This lifecycle is shared by LiveView dialogs and the client-owned image cropper.
const locks = new Set()

export function createDialogController(el, onClose = () => {}) {
  let active = false
  let previousFocus = null
  let pointerStartedOutside = false
  const release = () => {
    if (!active) return
    active = false
    locks.delete(el)
    if (!locks.size) {
      delete document.documentElement.dataset.modalScrollLocked
      delete document.body.dataset.modalScrollLocked
    }
    if (previousFocus?.isConnected) previousFocus.focus({preventScroll: true})
  }
  const open = () => {
    if (active || !el.isConnected) return
    previousFocus = document.activeElement
    el.showModal()
    active = true
    locks.add(el)
    document.documentElement.dataset.modalScrollLocked = ''
    document.body.dataset.modalScrollLocked = ''
    el.querySelector('[data-dialog-initial-focus]')?.focus({preventScroll: true})
  }
  const close = () => {
    if (!active) return
    el.close()
    release()
    onClose()
  }
  const cancel = event => {
    event.preventDefault()
    event.stopPropagation()
    if (el.dataset.dismissable !== 'false') close()
  }
  const outside = event => {
    if (event.target !== el) return false
    if (el.dataset.viewport === 'true') return true
    const rect = el.getBoundingClientRect()
    return event.clientX < rect.left || event.clientX > rect.right ||
      event.clientY < rect.top || event.clientY > rect.bottom
  }
  const pointerdown = event => { pointerStartedOutside = outside(event) }
  const click = event => {
    if (event.target.closest('dialog') !== el) return
    const control = event.target.closest('[data-dialog-close]')
    if (control && !control.disabled) close()
    else if (pointerStartedOutside && outside(event) && el.dataset.dismissable !== 'false') close()
    pointerStartedOutside = false
  }
  const nativeClose = () => {
    if (!active || el.open) return
    release()
    onClose()
  }
  el.addEventListener('cancel', cancel)
  el.addEventListener('close', nativeClose)
  el.addEventListener('pointerdown', pointerdown)
  el.addEventListener('click', click)
  // A mobile-only sheet must stop blocking the page when its breakpoint hides it.
  const resize = typeof ResizeObserver === 'undefined' ? null : new ResizeObserver(() => {
    if (active && getComputedStyle(el).display === 'none') close()
  })
  resize?.observe(el)
  return {
    open,
    close,
    destroy() {
      resize?.disconnect()
      el.removeEventListener('cancel', cancel)
      el.removeEventListener('close', nativeClose)
      el.removeEventListener('pointerdown', pointerdown)
      el.removeEventListener('click', click)
      if (el.open) el.close()
      release()
    }
  }
}
