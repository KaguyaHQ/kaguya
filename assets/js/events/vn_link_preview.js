// Hover preview for inline VN links in user content. The renderer tags links
// to known VNs with `data-vn-preview` (cover URL) and `data-vn-preview-title`;
// hovering or focusing one shows the cover in a small floating panel. Touch
// skips it, since a tap follows the link.

import {placePanel} from "../hooks/anchored_popover"

const SELECTOR = "a[data-vn-preview]"
const SHOW_DELAY_MS = 350
// Moving straight from one link to the next skips the delay.
const WARM_MS = 600

let panel = null
let activeLink = null
let showTimer = null
let lastHidden = 0

const ensurePanel = () => {
  if (panel?.isConnected) return panel
  panel = document.createElement("div")
  panel.setAttribute("aria-hidden", "true")
  panel.className =
    "bg-surface-menu-item-default border-border-divider pointer-events-none fixed z-50 w-[132px] rounded-lg border p-1.5 shadow-xl transition-opacity duration-150"
  Object.assign(panel.style, {left: "0", top: "0", opacity: "0", display: "none"})

  const img = document.createElement("img")
  img.alt = ""
  img.width = 120
  img.height = 170
  img.className = "h-[170px] w-[120px] rounded object-cover"
  img.style.setProperty("--nsfw-blur-size", "120")

  const title = document.createElement("p")
  title.className = "text-foreground-primary text-style-captionMedium mt-1.5 line-clamp-2 px-0.5"

  panel.append(img, title)
  document.body.appendChild(panel)
  return panel
}

const show = link => {
  clearTimeout(showTimer)
  const el = ensurePanel()
  const [img, title] = el.children

  if (img.getAttribute("src") !== link.dataset.vnPreview) img.src = link.dataset.vnPreview
  if (link.dataset.vnPreviewNsfw === "1") img.dataset.nsfwBlur = "1"
  else delete img.dataset.nsfwBlur
  title.textContent = link.dataset.vnPreviewTitle || ""

  activeLink = link
  el.style.display = "block"
  placePanel(el, link, {placement: "top", align: "start", sideOffset: 6, alignOffset: 0})
  el.style.opacity = "1"
}

const hide = () => {
  clearTimeout(showTimer)
  if (!activeLink) return
  activeLink = null
  lastHidden = Date.now()
  if (!panel) return
  panel.style.opacity = "0"
  setTimeout(() => { if (!activeLink && panel) panel.style.display = "none" }, 150)
}

const queue = link => {
  if (link === activeLink) return
  clearTimeout(showTimer)
  if (activeLink || Date.now() - lastHidden < WARM_MS) show(link)
  else showTimer = setTimeout(() => show(link), SHOW_DELAY_MS)
}

document.addEventListener("pointerover", event => {
  if (event.pointerType === "touch") return
  const link = event.target.closest?.(SELECTOR)
  if (link) queue(link)
})

document.addEventListener("pointerout", event => {
  const link = event.target.closest?.(SELECTOR)
  if (!link || link.contains(event.relatedTarget)) return
  hide()
})

document.addEventListener("focusin", event => {
  const link = event.target.closest?.(SELECTOR)
  if (link && link.matches(":focus-visible")) queue(link)
})

document.addEventListener("focusout", event => {
  if (event.target.closest?.(SELECTOR)) hide()
})

document.addEventListener("keydown", event => { if (event.key === "Escape") hide() })
window.addEventListener("scroll", hide, {capture: true, passive: true})
// LiveView patches can remove the hovered link without a pointerout.
window.addEventListener("phx:page-loading-start", hide)
