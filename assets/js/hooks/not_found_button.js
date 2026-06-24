// NotFoundButton — positions the "Return home" anchor over the moon in the
// 404 background image.
//
// Ports the natural-coordinate math from
// `../personal/legacy-next-app/src/components/shared/NotFoundPage.tsx`. The image is
// `object-fit: cover` with `object-position: 54.5% top`, so we reproduce
// the same transform here to know where the moon ends up on screen.
//
// Two entry points share one implementation:
//   * `NotFoundButton` — a LiveView hook used when the page is rendered
//     inside a LiveView (state == :not_found).
//   * `bootstrapStaticNotFound()` — wires up the same logic on
//     DOMContentLoaded for the controller-rendered 404 page, which has
//     no LiveView socket.

const BUTTON_X_DEFAULT = 0.535
const BUTTON_Y_DEFAULT = 0.245
const OBJECT_POSITION_X_DEFAULT = 0.545

function readNumber(el, key, fallback) {
  const raw = el?.dataset?.[key]
  if (raw == null || raw === "") return fallback
  const n = Number(raw)
  return Number.isFinite(n) ? n : fallback
}

function place(root) {
  const img = root.querySelector("[data-not-found-img]")
  const wrapper = root.querySelector("[data-not-found-button]")
  if (!img || !wrapper) return
  const cw = root.clientWidth
  const ch = root.clientHeight
  if (!img.naturalWidth || !cw || !ch) return

  const buttonX = readNumber(root, "buttonX", BUTTON_X_DEFAULT)
  const buttonY = readNumber(root, "buttonY", BUTTON_Y_DEFAULT)
  const objectPositionX = readNumber(root, "objectPositionX", OBJECT_POSITION_X_DEFAULT)

  const {naturalWidth, naturalHeight} = img
  const scale = Math.max(cw / naturalWidth, ch / naturalHeight)
  const displayedW = naturalWidth * scale
  const displayedH = naturalHeight * scale
  const offsetX = (cw - displayedW) * objectPositionX

  wrapper.style.left = `${offsetX + buttonX * displayedW}px`
  wrapper.style.top = `${buttonY * displayedH}px`
  wrapper.style.opacity = "1"
}

function attach(root) {
  if (!root || root.dataset.notFoundBound === "1") return () => {}
  root.dataset.notFoundBound = "1"

  const img = root.querySelector("[data-not-found-img]")
  const update = () => place(root)

  if (img?.complete && img.naturalWidth) {
    update()
  } else if (img) {
    img.addEventListener("load", update)
  }
  window.addEventListener("resize", update)

  return () => {
    delete root.dataset.notFoundBound
    img?.removeEventListener("load", update)
    window.removeEventListener("resize", update)
  }
}

export const NotFoundButton = {
  mounted() {
    this._cleanup = attach(this.el)
  },
  updated() {
    place(this.el)
  },
  destroyed() {
    this._cleanup?.()
  }
}

// Controller-rendered 404: no LiveView socket, so wire up via DOM events.
export function bootstrapStaticNotFound() {
  const init = () => {
    document.querySelectorAll("[data-not-found-img]").forEach(img => {
      // Walk up to the root container (the one with the data attrs).
      let root = img.closest("[data-button-x]")
      if (!root) return
      attach(root)
    })
  }
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init, {once: true})
  } else {
    init()
  }
}

export default NotFoundButton
