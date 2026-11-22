// `[[` VN link autocomplete for markdown textareas. Typing `[[title` searches
// visual novels; choosing one replaces the trigger with `[Title](/vn/slug)`,
// which user content renders as a cover card when it sits on its own line.
//
// The panel is a server-rendered `popover="manual"` element (phx-update="ignore")
// so it escapes the composer's overflow clipping and any open dialog.

import {placePanel, supportsNativePopover} from "../hooks/anchored_popover"
import {createVnSearchList} from "./vn_search"

const TRIGGER = /\[\[([^[\]\n]{0,60})$/
const SEARCH_DELAY_MS = 150
const MAX_RESULTS = 6
// Inline, because the shared result rows already carry their own bg classes.
const ACTIVE_BACKGROUND = "rgb(var(--surface-menu-item-hover))"

const escapeLabel = title => title.replace(/([[\]\\])/g, "\\$1")

const MIRRORED_STYLES = [
  "boxSizing", "width", "borderTopWidth", "borderRightWidth", "borderBottomWidth", "borderLeftWidth",
  "paddingTop", "paddingRight", "paddingBottom", "paddingLeft", "fontFamily", "fontSize", "fontWeight",
  "fontStyle", "letterSpacing", "lineHeight", "textTransform", "wordSpacing", "tabSize"
]

// Viewport rect of the caret's line, spanning the textarea's width, so the
// panel opens just under the line being typed rather than under a tall box.
const caretLineRect = textarea => {
  const style = getComputedStyle(textarea)
  const mirror = document.createElement("div")
  MIRRORED_STYLES.forEach(prop => { mirror.style[prop] = style[prop] })
  Object.assign(mirror.style, {
    position: "absolute", visibility: "hidden", top: "0", left: "-9999px",
    whiteSpace: "pre-wrap", overflowWrap: "break-word"
  })
  mirror.textContent = textarea.value.slice(0, textarea.selectionStart)
  const marker = document.createElement("span")
  marker.textContent = "\u200b"
  mirror.appendChild(marker)
  document.body.appendChild(mirror)
  const lineTop = marker.offsetTop
  const lineHeight = marker.offsetHeight
  mirror.remove()

  const box = textarea.getBoundingClientRect()
  const top = Math.min(box.top + lineTop - textarea.scrollTop, box.bottom - lineHeight)
  return {left: box.left, right: box.right, width: box.width, top, bottom: top + lineHeight, height: lineHeight}
}

export function attachVnLinkAutocomplete(textarea, panel) {
  if (!textarea || !panel) return () => {}

  const native = supportsNativePopover(panel)
  let match = null
  let items = []
  let active = 0
  let timer = null
  let controller = null
  let lastQuery = null
  let searchFailed = false
  let requestId = 0
  // Offset of a `[[` the user dismissed with Escape; it stays quiet until a
  // new trigger is typed.
  let dismissedAt = null

  const isOpen = () => (native ? panel.matches(":popover-open") : !panel.hidden)

  const options = () => Array.from(panel.querySelectorAll("[role=option]"))

  const place = () => {
    if (!isOpen()) return
    panel.style.width = `${Math.min(textarea.offsetWidth, 420)}px`
    const anchor = {getBoundingClientRect: () => caretLineRect(textarea)}
    placePanel(panel, anchor, {placement: "bottom", align: "start", sideOffset: 4, alignOffset: 0})
    panel.style.visibility = "visible"
  }

  const show = () => {
    if (!isOpen()) {
      if (native) panel.showPopover()
      else panel.hidden = false
      textarea.setAttribute("aria-expanded", "true")
    }
    place()
  }

  const close = () => {
    requestId++
    clearTimeout(timer)
    controller?.abort()
    match = null
    items = []
    lastQuery = null
    searchFailed = false
    if (isOpen()) {
      if (native) panel.hidePopover()
      else panel.hidden = true
    }
    panel.style.visibility = "hidden"
    textarea.setAttribute("aria-expanded", "false")
    textarea.removeAttribute("aria-activedescendant")
  }

  const message = text => {
    const note = document.createElement("p")
    note.className = "text-foreground-tertiary text-style-body2Regular px-3 py-3"
    note.textContent = text
    return note
  }

  const highlight = index => {
    const rows = options()
    if (rows.length === 0) return
    active = (index + rows.length) % rows.length
    rows.forEach((row, i) => {
      const selected = i === active
      row.setAttribute("aria-selected", String(selected))
      row.parentElement.style.backgroundColor = selected ? ACTIVE_BACKGROUND : ""
      if (selected) {
        textarea.setAttribute("aria-activedescendant", row.id)
        row.scrollIntoView({block: "nearest"})
      }
    })
  }

  const insert = item => {
    if (!match || !item?.slug) return close()
    const end = textarea.selectionStart
    const start = end - match[0].length
    textarea.setRangeText(`[${escapeLabel(item.title || item.slug)}](/vn/${item.slug})`, start, end, "end")
    close()
    textarea.focus()
    textarea.dispatchEvent(new Event("input", {bubbles: true}))
  }

  const render = () => {
    const heading = document.createElement("p")
    heading.className = "text-foreground-tertiary text-style-captionMedium px-3 pt-2.5 pb-1"
    heading.textContent = "Link a visual novel"

    let body
    if (match[1].trim() === "") {
      body = message("Type a title to search")
    } else if (searchFailed) {
      body = message("Search is temporarily unavailable.")
      body.setAttribute("role", "status")
      const retry = document.createElement("button")
      retry.type = "button"
      retry.id = `${panel.id}-retry`
      retry.tabIndex = -1
      retry.className = "text-foreground-link ml-2 rounded underline underline-offset-2"
      retry.textContent = "Try again"
      retry.title = "Retry search (Enter)"
      retry.addEventListener("click", () => {
        if (match) search(match[1].trim())
      })
      body.appendChild(retry)
    } else if (items.length === 0) {
      body = message(lastQuery === null ? "Searching…" : "No visual novels found")
    } else {
      body = createVnSearchList({items, compact: true, selectOnly: true, onSelect: insert})
      body.setAttribute("role", "listbox")
      body.id = `${panel.id}-listbox`
      body.querySelectorAll("button").forEach((button, i) => {
        button.id = `${panel.id}-option-${i}`
        button.setAttribute("role", "option")
        button.tabIndex = -1
      })
      textarea.setAttribute("aria-controls", body.id)
    }

    panel.replaceChildren(heading, body)
    show()
    if (items.length > 0) highlight(Math.min(active, items.length - 1))
  }

  const search = query => {
    const currentRequest = ++requestId
    clearTimeout(timer)
    controller?.abort()
    items = []
    lastQuery = null
    searchFailed = false
    render()
    timer = setTimeout(async () => {
      controller = new AbortController()
      try {
        const params = new URLSearchParams({q: query, page_size: String(MAX_RESULTS)})
        const response = await fetch(`/search/visual-novels?${params}`, {
          headers: {"x-requested-with": "XMLHttpRequest"},
          signal: controller.signal
        })
        if (!response.ok) throw new Error(`search failed: ${response.status}`)
        const data = await response.json()
        if (currentRequest !== requestId || !match || match[1].trim() !== query) return
        items = (data.items || []).slice(0, MAX_RESULTS)
        lastQuery = query
        active = 0
        render()
      } catch (error) {
        if (error.name === "AbortError" || currentRequest !== requestId || !match) return
        items = []
        lastQuery = query
        searchFailed = true
        render()
      }
    }, SEARCH_DELAY_MS)
  }

  const onInput = () => {
    const caret = textarea.selectionStart
    if (caret !== textarea.selectionEnd) return close()

    const next = textarea.value.slice(0, caret).match(TRIGGER)
    if (!next) {
      dismissedAt = null
      return close()
    }
    if (next.index === dismissedAt) return

    const queryChanged = !match || match[1] !== next[1]
    match = next
    if (!queryChanged && isOpen() && !searchFailed) return

    if (next[1].trim() === "") {
      requestId++
      clearTimeout(timer)
      controller?.abort()
      items = []
      lastQuery = null
      searchFailed = false
      render()
    } else {
      search(next[1].trim())
    }
  }

  const onKeyDown = event => {
    if (!isOpen()) return

    if (event.key === "Escape") {
      // Keep Escape from also closing the surrounding dialog.
      event.preventDefault()
      event.stopPropagation()
      dismissedAt = match?.index ?? null
      close()
    } else if (searchFailed && event.key === "Enter" && !event.metaKey && !event.ctrlKey) {
      event.preventDefault()
      event.stopPropagation()
      search(match[1].trim())
    } else if (items.length > 0 && event.key === "ArrowDown") {
      event.preventDefault()
      highlight(active + 1)
    } else if (items.length > 0 && event.key === "ArrowUp") {
      event.preventDefault()
      highlight(active - 1)
    } else if (items.length > 0 && (event.key === "Enter" || event.key === "Tab") && !event.metaKey && !event.ctrlKey) {
      event.preventDefault()
      event.stopPropagation()
      insert(items[active])
    }
  }

  // Keep focus in the textarea while picking with the pointer.
  const onPanelPointerDown = event => event.preventDefault()
  const onBlur = () => close()
  const onReposition = () => place()

  textarea.setAttribute("aria-autocomplete", "list")
  textarea.setAttribute("aria-expanded", "false")
  textarea.addEventListener("input", onInput)
  textarea.addEventListener("click", onInput)
  textarea.addEventListener("keydown", onKeyDown)
  textarea.addEventListener("blur", onBlur)
  panel.addEventListener("pointerdown", onPanelPointerDown)
  window.addEventListener("resize", onReposition, {passive: true})
  window.addEventListener("scroll", onReposition, {capture: true, passive: true})

  return () => {
    close()
    textarea.removeEventListener("input", onInput)
    textarea.removeEventListener("click", onInput)
    textarea.removeEventListener("keydown", onKeyDown)
    textarea.removeEventListener("blur", onBlur)
    panel.removeEventListener("pointerdown", onPanelPointerDown)
    window.removeEventListener("resize", onReposition)
    window.removeEventListener("scroll", onReposition, {capture: true})
  }
}
