// Client storage for the user's content-preference toggles. Uses these
// localStorage keys + html data-* attribute contract.
//
//   * kaguya_nsfw_preference           → data-nsfw-show
//   * kaguya_show_nsfw_screenshots     → data-screenshot-nsfw
//   * kaguya_show_brutal_screenshots   → data-screenshot-brutal
//
// The settings LiveView pushes `phx:kaguya:content-pref` after a toggle
// so the bare <html> attributes (read by the pre-paint init script in
// root.html.heex on the next hard reload) and the localStorage values
// (used cross-tab) stay in sync with the server's user record.

const STORAGE_KEYS = {
  nsfw_cover: "kaguya_nsfw_preference",
  nsfw_screenshot: "kaguya_show_nsfw_screenshots",
  brutal_screenshot: "kaguya_show_brutal_screenshots",
}

const DATASET_KEYS = {
  nsfw_cover: "nsfwShow",
  nsfw_screenshot: "screenshotNsfw",
  brutal_screenshot: "screenshotBrutal",
}

function setPref(kind, enabled) {
  const storageKey = STORAGE_KEYS[kind]
  const datasetKey = DATASET_KEYS[kind]
  if (!storageKey || !datasetKey) return

  try {
    localStorage.setItem(storageKey, String(!!enabled))
  } catch (_) {}

  const root = document.documentElement
  if (enabled) {
    root.dataset[datasetKey] = "1"
  } else {
    delete root.dataset[datasetKey]
  }
}

window.addEventListener("phx:kaguya:content-pref", ({detail}) => {
  if (!detail || typeof detail !== "object") return
  if ("nsfw_cover" in detail) setPref("nsfw_cover", detail.nsfw_cover)
  if ("nsfw_screenshot" in detail) setPref("nsfw_screenshot", detail.nsfw_screenshot)
  if ("brutal_screenshot" in detail) setPref("brutal_screenshot", detail.brutal_screenshot)
})
