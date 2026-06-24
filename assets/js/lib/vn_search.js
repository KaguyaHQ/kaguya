const RECENT_VN_SEARCHES_KEY = "recentSearches_visualNovels"

export const getRecentVnSearches = () => {
  try {
    return JSON.parse(localStorage.getItem(RECENT_VN_SEARCHES_KEY) || "[]")
  } catch (_error) {
    return []
  }
}

const saveRecentVnSearches = items => {
  try {
    localStorage.setItem(RECENT_VN_SEARCHES_KEY, JSON.stringify(items.slice(0, 10)))
  } catch (_error) {
  }
}

export const addRecentVnSearch = item => {
  if (!item?.id) return
  const recent = getRecentVnSearches().filter(entry => entry?.id !== item.id)
  saveRecentVnSearches([item, ...recent])
}

export const removeRecentVnSearch = id => {
  saveRecentVnSearches(getRecentVnSearches().filter(entry => entry?.id !== id))
}

const vnSearchImageUrl = item =>
  item?.image_url ||
  item?.imageUrl ||
  item?.images?.small ||
  item?.images?.medium ||
  item?.images?.large ||
  item?.images?.xl ||
  ""

const vnSearchProducerText = item => {
  const producers = item?.producers
  if (Array.isArray(producers)) {
    return producers
      .map(producer => typeof producer === "string" ? producer : producer?.name)
      .filter(Boolean)
      .join(", ")
  }
  return producers || ""
}

const vnSearchCoverSensitive = item =>
  item?.is_image_nsfw === true ||
  item?.isImageNsfw === true ||
  item?.is_image_suggestive === true ||
  item?.isImageSuggestive === true

const createVnSearchResultRow = ({item, compact, recent, selectOnly, onSelect, onRemove}) => {
  const wrapper = document.createElement("div")
  wrapper.className = "flex w-full flex-col"

  const row = document.createElement("div")
  row.className = [
    "bg-surface-menu-item-default text-foreground-primary lg:hover:bg-surface-menu-item-hover flex w-full flex-1 cursor-pointer items-start p-0 hover:bg-transparent",
    compact ? "h-[56px]" : "h-[96px]"
  ].join(" ")

  const link = document.createElement(selectOnly ? "button" : "a")
  if (selectOnly) {
    link.type = "button"
  } else {
    link.href = item.slug ? `/vn/${item.slug}` : "#"
    // Tell the LiveView JS client to intercept this click and do a client-side
    // navigation (same as <.link navigate>) instead of a full browser reload.
    if (item.slug) {
      link.setAttribute("data-phx-link", "redirect")
      link.setAttribute("data-phx-link-state", "push")
    }
  }
  link.className = [
    "flex h-full min-w-0 flex-1 items-start justify-between text-left bg-transparent",
    compact ? "gap-3 px-2 py-1.5" : "gap-5 px-4 py-2 sm:py-3"
  ].join(" ")
  link.addEventListener("click", event => {
    if (selectOnly || !item.slug) event.preventDefault()
    if (!selectOnly) addRecentVnSearch(item)
    onSelect?.(item)
  })

  const content = document.createElement("div")
  content.className = ["flex min-w-0 flex-1", compact ? "items-center gap-2.5" : "items-start gap-4"].join(" ")

  const coverFrame = document.createElement("div")
  coverFrame.className = [
    "bg-surface-elevated aspect-[1/1.5] overflow-hidden",
    compact ? "h-[40px] w-[27px] shrink-0 rounded-[2px]" : "h-[72px] w-[48px] rounded-[4px]"
  ].join(" ")

  const coverShadow = document.createElement("div")
  coverShadow.style.boxShadow = "0px 4px 10px rgba(0, 0, 0, 0.35)"

  const imageUrl = vnSearchImageUrl(item)
  if (imageUrl) {
    const img = document.createElement("img")
    img.src = imageUrl
    img.alt = ""
    img.loading = "lazy"
    img.decoding = "async"
    if (vnSearchCoverSensitive(item)) {
      img.dataset.nsfwBlur = "1"
      img.style.setProperty("--nsfw-blur-size", compact ? "40" : "72")
    }
    img.className = [
      "aspect-[1/1.5] object-cover object-center text-transparent",
      compact ? "h-[40px] w-[27px] rounded-[2px]" : "h-[72px] w-[48px] rounded-[4px]"
    ].join(" ")
    coverShadow.appendChild(img)
  } else {
    const fallback = document.createElement("div")
    fallback.className = [
      "flex aspect-[1/1.5] items-center justify-center border border-border-divider text-foreground-tertiary",
      compact ? "h-[40px] w-[27px] rounded-[2px] text-[9px]" : "h-[72px] w-[48px] rounded-[4px] text-xs"
    ].join(" ")
    fallback.textContent = "VN"
    coverShadow.appendChild(fallback)
  }

  coverFrame.appendChild(coverShadow)

  const copy = document.createElement("div")
  copy.className = ["flex min-w-0 flex-1 flex-col", compact ? "gap-0.5" : "mt-2 gap-2"].join(" ")

  const title = document.createElement("span")
  title.className = [
    "text-foreground-primary font-source-serif",
    compact ? "text-style-body2Medium truncate" : "text-style-body1Medium line-clamp-1"
  ].join(" ")
  title.textContent = item.title || "Untitled"
  copy.appendChild(title)

  const producers = vnSearchProducerText(item)
  if (producers) {
    const producer = document.createElement("span")
    producer.className = [
      "text-foreground-tertiary",
      compact ? "text-style-captionRegular truncate" : "text-style-body2Regular line-clamp-1"
    ].join(" ")
    producer.textContent = producers
    copy.appendChild(producer)
  }

  content.append(coverFrame, copy)
  link.appendChild(content)

  if (selectOnly) {
    const plus = document.createElement("span")
    plus.className = "text-foreground-secondary mt-2 mr-2 flex size-4 shrink-0 items-center justify-center"
    plus.setAttribute("aria-hidden", "true")
    plus.innerHTML = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12h14"/><path d="M12 5v14"/></svg>'
    link.appendChild(plus)
  }

  row.appendChild(link)

  if (recent) {
    const remove = document.createElement("button")
    remove.type = "button"
    remove.className = [
      "text-foreground-secondary flex shrink-0 items-center justify-center",
      compact ? "mr-1 size-8" : "mr-2 size-10"
    ].join(" ")
    remove.setAttribute("aria-label", `Remove ${item.title || "result"} from recent searches`)
    remove.innerHTML = '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" aria-hidden="true"><path d="M12 4L4 12M4 4L12 12" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>'
    remove.addEventListener("click", event => {
      event.preventDefault()
      event.stopPropagation()
      removeRecentVnSearch(item.id)
      onRemove?.()
    })
    row.classList.add("flex")
    row.appendChild(remove)
  }

  wrapper.appendChild(row)
  return wrapper
}

export const createVnSearchList = ({items, compact, recent = false, selectOnly = false, onSelect, onRemove}) => {
  const group = document.createElement("div")
  group.className = recent ? "[&>div]:divide-border-divider p-0 [&>div]:divide-y" : "p-0"

  items.filter(Boolean).forEach((item, index, arr) => {
    const row = createVnSearchResultRow({item, compact, recent, selectOnly, onSelect, onRemove})
    const itemRoot = row.firstElementChild
    if (!recent && index !== arr.length - 1) {
      itemRoot?.classList.add("border-b", "border-border-divider")
    }
    if (!recent && index === arr.length - 1) {
      itemRoot?.classList.add("border-b", "border-transparent")
    }
    group.appendChild(row)
  })

  return group
}
