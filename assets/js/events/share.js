import {isMobileOrTabletUA} from "../lib/device"
import {showKaguyaToast} from "../lib/toast"

document.addEventListener("click", async event => {
  if (!(event.target instanceof Element)) return
  const button = event.target.closest("[data-share-button]")
  if (!button) return

  const url = button.dataset.shareUrl || window.location.href
  const title = button.dataset.shareTitle || document.title

  if (isMobileOrTabletUA() && navigator.share) {
    try {
      await navigator.share({title, url})
      return
    } catch (error) {
      if (error?.name === "AbortError" || error?.name === "NotAllowedError") return
    }
  }

  if (!navigator.clipboard) {
    showKaguyaToast({variant: "error", message: "Could not copy link"})
    return
  }

  try {
    await navigator.clipboard.writeText(url)
    showKaguyaToast({variant: "success", message: "Link copied"})
  } catch (_error) {
    showKaguyaToast({variant: "error", message: "Could not copy link"})
  }
})
