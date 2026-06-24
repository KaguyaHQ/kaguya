// Click-to-reveal handler for blurred adult covers / character images.
// The blur itself is the affordance: clicking the image once swaps in the
// revealed state for the rest of the session. A second click no longer toggles
// it back (the revealed state is one-way).
//
// Implementation notes:
//
//  * Capture phase so we intercept the click before any wrapping <a> would
//    navigate or any phx-click would fire.
//  * If the global preference is "show NSFW" (html[data-nsfw-show="1"], set
//    by the pre-paint script from localStorage), nothing is blurred so the
//    overlay is skipped and the click flows through.
//  * Sets data-nsfw-revealed on the img itself rather than on a parent, so
//    multiple covers in a grid reveal independently.

document.addEventListener(
  "click",
  (event) => {
    try {
      if (document.documentElement.dataset.nsfwShow === "1") return

      const target = event.target
      // Bail fast on anything that isn't an Element (Window/Document/etc).
      if (!(target instanceof Element)) return

      const img = target.closest(
        "img[data-nsfw-blur='1'][data-nsfw-reveal='1']:not([data-nsfw-revealed='1'])",
      )
      if (!img) return

      img.setAttribute("data-nsfw-revealed", "1")
      event.preventDefault()
      event.stopPropagation()
    } catch (_error) {
      // Never let a reveal-handler bug consume the click — phx-click + native
      // links still need to work for everything that isn't an adult image.
    }
  },
  true,
)
