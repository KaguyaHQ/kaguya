const revealSpoiler = el => {
  if (!el || el.classList.contains("revealed")) return
  el.classList.add("revealed")
  el.removeAttribute("aria-hidden")
  el.removeAttribute("aria-label")
  el.removeAttribute("role")
  el.removeAttribute("tabindex")
}

document.addEventListener("click", event => {
  const spoiler = event.target.closest?.("[data-spoiler]")
  if (!spoiler) return
  event.preventDefault()
  revealSpoiler(spoiler)
})

document.addEventListener("keydown", event => {
  const active = document.activeElement
  if (!active?.hasAttribute?.("data-spoiler")) return
  if (event.key === "Enter" || event.key === " " || event.key === "Spacebar") {
    event.preventDefault()
    revealSpoiler(active)
  }
})
