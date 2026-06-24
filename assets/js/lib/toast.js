const toastIcons = {
  success: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 6 9 17l-5-5" /></svg>',
  error: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="10" /><path d="m15 9-6 6" /><path d="m9 9 6 6" /></svg>',
  warning: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 9v4" /><path d="M12 17h.01" /><path d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0Z" /></svg>',
  info: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="10" /><path d="M12 16v-4" /><path d="M12 8h.01" /></svg>'
}

const normalizeToastVariant = variant => {
  if (["success", "error", "warning", "info"].includes(variant)) return variant
  if (variant === "info") return "success"
  return "success"
}

const ensureToastRoot = () => {
  let root = document.getElementById("kaguya-toast-root")
  if (root) return root

  root = document.createElement("div")
  root.id = "kaguya-toast-root"
  root.className = "kaguya-toast-root"
  root.setAttribute("aria-live", "polite")
  root.setAttribute("aria-atomic", "false")
  document.body.appendChild(root)
  return root
}

const dismissToast = toast => {
  if (!toast || toast.dataset.state === "closing") return
  toast.dataset.state = "closing"
  setTimeout(() => toast.remove(), 240)
}

export const wireToast = toast => {
  if (!toast || toast.dataset.toastWired === "true") return
  toast.dataset.toastWired = "true"

  const duration = parseInt(toast.dataset.duration, 10)
  const close = toast.querySelector("[data-kaguya-toast-close]")

  // Server-rendered toasts carry phx-click on close; LiveView handles
  // the click and drives DOM removal via clear_flash + phx-remove.
  // Client-only toasts (showKaguyaToast) need this JS dismiss handler.
  if (close && !close.hasAttribute("phx-click")) {
    close.addEventListener("click", () => dismissToast(toast))
  }

  if (duration > 0) {
    setTimeout(() => close?.click(), duration)
  }
}

export const showKaguyaToast = detail => {
  const message = detail?.message || detail?.title
  if (!message) return

  const variant = normalizeToastVariant(detail?.variant || "success")
  const root = ensureToastRoot()
  const toast = document.createElement("div")
  toast.dataset.kaguyaToast = ""
  toast.dataset.duration = String(detail?.duration || (variant === "error" || variant === "warning" ? 5000 : 3000))
  toast.className = `kaguya-toast kaguya-toast-${variant}`
  toast.setAttribute("role", variant === "error" ? "alert" : "status")

  const icon = document.createElement("span")
  icon.className = "kaguya-toast-icon"
  icon.innerHTML = toastIcons[variant] || toastIcons.success

  const copy = document.createElement("span")
  copy.className = "kaguya-toast-copy"

  const title = document.createElement("span")
  title.className = "kaguya-toast-title"
  title.textContent = message
  copy.appendChild(title)

  if (detail?.description) {
    const description = document.createElement("span")
    description.className = "kaguya-toast-description"
    description.textContent = detail.description
    copy.appendChild(description)
  }

  const close = document.createElement("button")
  close.type = "button"
  close.className = "kaguya-toast-close"
  close.dataset.kaguyaToastClose = ""
  close.setAttribute("aria-label", "Dismiss")
  close.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M18 6 6 18" /><path d="m6 6 12 12" /></svg>'

  toast.append(icon, copy, close)
  root.appendChild(toast)
  wireToast(toast)
}
