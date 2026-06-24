/*
 * CoverTooltip — Letterboxd-style imperative tooltip for VN cover grids.
 *
 * Tracks the pointer, finds the nearest configured tooltip data attribute
 * inside the hook root, and shows a single floating tooltip after
 * `delayDuration`.
 * Subsequent hovers within `skipDelayDuration` show instantly ("warmth").
 * Scroll-aware: keeps the tooltip pinned to the original cover during a
 * scroll, then crossfades to the new cover when the scroll stops.
 *
 * Element data attributes (configured by `<.cover_tooltip_provider/>`):
 *   data-delay-duration       — initial show delay in ms (default 650)
 *   data-skip-delay-duration  — warmth window in ms       (default 1000)
 *   data-tooltip-attribute    — source attribute          (default data-cover-title)
 */
const CoverTooltip = {
  mounted() {
    const container = this.el
    const delayDuration = parseInt(container.dataset.delayDuration, 10) || 650
    const skipDelayDuration = parseInt(container.dataset.skipDelayDuration, 10) || 1000
    const dataAttribute = container.dataset.tooltipAttribute || "data-cover-title"

    const tip = document.createElement("div")
    tip.className = "cover-tooltip"
    container.appendChild(tip)

    const pointer = {x: 0, y: 0}
    let activeEl = null
    let pendingEl = null
    let visible = false
    let scrolling = false
    let lastClose = 0
    let showTimer
    let scrollTimer
    let lingerTimer
    let scrollMaxTimer
    let rafId = 0
    let lastScrollHide = 0

    const findCover = (x, y) => {
      const el = document.elementFromPoint(x, y)
      if (!el || !container.contains(el)) return null
      return el.closest(`[${dataAttribute}]`)
    }

    const findCoverFromEvent = e => {
      const el = e.target
      if (!el || !container.contains(el)) return null
      return el.closest(`[${dataAttribute}]`)
    }

    const positionTip = () => {
      if (!activeEl) return
      const rect = activeEl.getBoundingClientRect()
      const viewportWidth = document.documentElement.clientWidth
      const margin = 8
      const halfWidth = Math.ceil(tip.offsetWidth / 2)
      const centeredLeft = rect.left + rect.width / 2
      const minLeft = margin + halfWidth
      const maxLeft = viewportWidth - margin - halfWidth
      const left =
        minLeft > maxLeft
          ? viewportWidth / 2
          : Math.min(Math.max(centeredLeft, minLeft), maxLeft)

      tip.style.left = `${left}px`
      tip.style.top = `${rect.top - 4}px`
    }

    const revealTip = () => {
      void tip.offsetHeight
      tip.style.opacity = "1"
    }

    const show = (el, crossfade = false) => {
      clearTimeout(showTimer)
      clearTimeout(lingerTimer)
      pendingEl = null
      const title = el.getAttribute(dataAttribute)
      if (!title) return

      if (crossfade && visible) {
        tip.style.opacity = "0"
        setTimeout(() => {
          activeEl = el
          tip.textContent = title
          tip.style.display = "block"
          positionTip()
          revealTip()
        }, 150)
      } else {
        activeEl = el
        tip.textContent = title
        tip.style.display = "block"
        positionTip()
        revealTip()
      }
      visible = true
    }

    const hide = () => {
      clearTimeout(showTimer)
      clearTimeout(lingerTimer)
      clearTimeout(scrollMaxTimer)
      scrollMaxTimer = undefined
      if (visible) lastClose = Date.now()
      activeEl = null
      pendingEl = null
      tip.style.opacity = "0"
      visible = false
      setTimeout(() => { if (!visible) tip.style.display = "none" }, 150)
    }

    const queueShow = cover => {
      if (cover === activeEl && visible) return
      if (cover && cover === pendingEl) return

      clearTimeout(showTimer)
      clearTimeout(lingerTimer)
      pendingEl = null

      if (!cover) { hide(); return }

      if (visible ||
          Date.now() - lastClose < skipDelayDuration ||
          Date.now() - lastScrollHide < 3000) {
        show(cover)
      } else {
        pendingEl = cover
        showTimer = setTimeout(() => { pendingEl = null; show(cover) }, delayDuration)
      }
    }

    const handlePointerMove = e => {
      if (e.pointerType === "touch") return
      pointer.x = e.clientX
      pointer.y = e.clientY
      if (scrolling) return

      queueShow(findCover(e.clientX, e.clientY))
    }

    const handlePointerOver = e => {
      if (e.pointerType === "touch") return
      pointer.x = e.clientX
      pointer.y = e.clientY
      if (scrolling) return

      queueShow(findCoverFromEvent(e))
    }

    const handlePointerLeave = () => { if (!scrolling) hide() }

    const handleScroll = () => {
      scrolling = true
      clearTimeout(scrollTimer)
      clearTimeout(lingerTimer)
      clearTimeout(showTimer)
      pendingEl = null

      if (visible && activeEl) {
        cancelAnimationFrame(rafId)
        rafId = requestAnimationFrame(positionTip)
      }

      if (visible && !scrollMaxTimer) {
        scrollMaxTimer = setTimeout(() => {
          scrollMaxTimer = undefined
          if (visible) { lastScrollHide = Date.now(); hide() }
        }, 3500)
      }

      scrollTimer = setTimeout(() => {
        scrolling = false
        clearTimeout(scrollMaxTimer)
        scrollMaxTimer = undefined

        const cover = findCover(pointer.x, pointer.y)

        if (!visible) {
          if (cover && Date.now() - lastScrollHide < 3000) show(cover)
          return
        }

        if (cover === activeEl) return

        if (cover) {
          lingerTimer = setTimeout(() => show(cover, true), 100)
        } else {
          lingerTimer = setTimeout(() => { lastScrollHide = Date.now(); hide() }, 600)
        }
      }, 150)
    }

    container.addEventListener("pointermove", handlePointerMove, {passive: true})
    container.addEventListener("pointerover", handlePointerOver, {passive: true})
    container.addEventListener("pointerleave", handlePointerLeave)
    window.addEventListener("scroll", handleScroll, {capture: true, passive: true})

    this._cleanup = () => {
      container.removeEventListener("pointermove", handlePointerMove)
      container.removeEventListener("pointerover", handlePointerOver)
      container.removeEventListener("pointerleave", handlePointerLeave)
      window.removeEventListener("scroll", handleScroll, {capture: true})
      cancelAnimationFrame(rafId)
      clearTimeout(showTimer)
      clearTimeout(scrollTimer)
      clearTimeout(lingerTimer)
      clearTimeout(scrollMaxTimer)
      tip.remove()
    }
  },

  destroyed() { if (this._cleanup) this._cleanup() }
}

export default CoverTooltip
