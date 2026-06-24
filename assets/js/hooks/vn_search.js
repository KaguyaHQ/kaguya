import {
  createVnSearchList,
  getRecentVnSearches
} from "../lib/vn_search"
import {lvNavigate} from "../lib/lv_navigate"

const VNSearch = {
  mounted() {
    this.input = this.el.querySelector("[data-vn-search-input]")
    this.form = this.el.querySelector("[data-vn-search-form]")
    this.popover = this.el.querySelector("[data-vn-search-popover]")
    this.clearButton = this.el.querySelector("[data-vn-search-clear]")
    this.pageSize = parseInt(this.el.dataset.pageSize, 10) || 24
    this.compact = this.el.dataset.variant === "compact"
    this.showAllResults = this.el.dataset.showAllResults !== "false"
    this.selectEvent = this.el.dataset.selectEvent || null
    this.selectTarget = this.el.dataset.selectTarget || null
    this.hideRecent = this.el.dataset.hideRecent === "true"
    this.mobileFullHeight = this.el.dataset.mobileFullheight === "true"
    this._requestId = 0
    this._abortController = null

    this._onFocus = () => this._renderForCurrentQuery()
    this._onInput = () => {
      this._syncClearButton()
      clearTimeout(this._searchTimer)
      const query = this._query()
      if (!query) {
        this._renderRecentOrClose()
        return
      }
      this._searchTimer = setTimeout(() => this._search(query), 350)
    }
    this._onKeyDown = event => {
      if (event.key === "Escape") this._close()
      if (event.key === "Enter") {
        event.preventDefault()
        this._goToSearch()
      }
    }
    this._onSubmit = event => {
      event.preventDefault()
      this._goToSearch()
    }
    this._onClear = () => {
      this.input.value = ""
      this._syncClearButton()
      this._renderRecentOrClose()
      this.input.focus()
    }
    this._onDocumentPointerDown = event => {
      if (!this.el.contains(event.target)) this._close()
    }

    this.input?.addEventListener("focus", this._onFocus)
    this.input?.addEventListener("input", this._onInput)
    this.input?.addEventListener("keydown", this._onKeyDown)
    this.form?.addEventListener("submit", this._onSubmit)
    this.clearButton?.addEventListener("click", this._onClear)
    document.addEventListener("pointerdown", this._onDocumentPointerDown, true)
    this._syncClearButton()
  },

  destroyed() {
    clearTimeout(this._searchTimer)
    this._abortController?.abort()
    this.input?.removeEventListener("focus", this._onFocus)
    this.input?.removeEventListener("input", this._onInput)
    this.input?.removeEventListener("keydown", this._onKeyDown)
    this.form?.removeEventListener("submit", this._onSubmit)
    this.clearButton?.removeEventListener("click", this._onClear)
    document.removeEventListener("pointerdown", this._onDocumentPointerDown, true)
  },

  _query() {
    return (this.input?.value || "").trim()
  },

  _syncClearButton() {
    if (!this.clearButton) return
    this.clearButton.hidden = this._query() === ""
  },

  _renderForCurrentQuery() {
    const query = this._query()
    if (query) {
      this._search(query)
    } else {
      this._renderRecentOrClose()
    }
  },

  _renderRecentOrClose() {
    if (this.hideRecent) {
      this._close()
      return
    }
    const recent = getRecentVnSearches()
    if (recent.length === 0) {
      this._close()
      return
    }
    this._renderList(recent, {recent: true})
  },

  _renderLoading() {
    this.popover.replaceChildren()
    const loading = document.createElement("div")
    loading.className = "text-foreground-primary flex w-full items-center justify-center px-6 py-3 text-center text-sm"
    const loader = document.createElement("div")
    loader.className = "kaguya-button-loader"
    loader.setAttribute("aria-label", "Loading")
    loader.setAttribute("role", "status")
    for (let index = 0; index < 3; index += 1) {
      const bar = document.createElement("span")
      bar.className = "kaguya-button-loader-bar"
      bar.style.animationDelay = index === 0 ? "0s" : index === 1 ? "-0.2s" : "-0.4s"
      loader.appendChild(bar)
    }
    loading.appendChild(loader)
    this.popover.appendChild(loading)
    this._open()
  },

  _renderEmpty(message = "No results found") {
    this.popover.replaceChildren()
    const empty = document.createElement("div")
    empty.className = "text-foreground-primary flex items-center justify-center px-6 py-[18px] text-center text-sm font-medium"
    empty.textContent = message
    this.popover.appendChild(empty)
    this._open()
  },

  _renderList(items, {pagination = null, recent = false} = {}) {
    if (!items || items.length === 0) {
      this._renderEmpty()
      return
    }

    this.popover.replaceChildren()
    const scroller = document.createElement("div")
    scroller.className = [
      "custom-search-scrollbar bg-surface-menu-item-default overflow-y-auto rounded-none",
      this.mobileFullHeight
        ? "max-h-[424px] pt-2"
        : this.compact
          ? "max-h-[262px] p-0"
          : "max-sm:h-[calc(100vh-52px)] sm:max-h-[484px] p-0"
    ].join(" ")

    scroller.appendChild(createVnSearchList({
      items,
      compact: this.compact,
      recent,
      selectOnly: !!this.selectEvent,
      onSelect: item => {
        if (this.selectEvent && item?.id) {
          const payload = {
            id: item.id,
            slug: item.slug || null,
            title: item.title || null,
            image_url:
              item.image_url ||
              item.imageUrl ||
              item.images?.medium ||
              item.images?.large ||
              item.images?.small ||
              null,
            is_image_nsfw: !!(item.is_image_nsfw || item.isImageNsfw),
            is_image_suggestive: !!(item.is_image_suggestive || item.isImageSuggestive)
          }
          const target = this.selectTarget
            ? document.querySelector(this.selectTarget) || this.selectTarget
            : null
          if (target) {
            this.pushEventTo(target, this.selectEvent, payload)
          } else {
            this.pushEvent(this.selectEvent, payload)
          }
          if (this.input) {
            this.input.value = ""
            this._syncClearButton()
          }
        }
        this._close()
      },
      onRemove: () => this._renderRecentOrClose()
    }))

    this.popover.appendChild(scroller)

    const totalCount = pagination?.total_count || pagination?.totalCount || 0
    if (!recent && !this.selectEvent && this.showAllResults && totalCount > this.pageSize) {
      const footer = document.createElement("div")
      footer.className = "border-border-divider bg-surface-menu-item-default sticky bottom-0 z-10 -mt-px w-full border-t"
      const button = document.createElement("button")
      button.type = "button"
      button.className = "text-style-body2Regular text-foreground-primary hover:bg-surface-menu-item-hover flex h-11 w-full items-center justify-center rounded-none bg-transparent px-4 py-2.5 md:h-12 md:py-3.5"
      button.textContent = `See all ${totalCount.toLocaleString("en-US")} results`
      button.addEventListener("click", () => this._goToSearch())
      footer.appendChild(button)
      this.popover.appendChild(footer)
    }

    this._open()
  },

  _open() {
    if (this.popover) this.popover.hidden = false
  },

  _close() {
    if (this.popover) this.popover.hidden = true
  },

  _goToSearch() {
    const params = new URLSearchParams({type: "visualNovels"})
    const query = this._query()
    if (query) params.set("q", query)
    lvNavigate(`/search?${params.toString()}`, "redirect")
  },

  async _search(query) {
    const currentRequest = ++this._requestId
    this._abortController?.abort()
    this._abortController = new AbortController()
    this._renderLoading()

    const params = new URLSearchParams({q: query, page_size: String(this.pageSize)})

    try {
      const response = await fetch(`/search/visual-novels?${params.toString()}`, {
        signal: this._abortController.signal,
        headers: {"x-requested-with": "XMLHttpRequest"}
      })
      if (!response.ok) throw new Error("Search failed")
      const payload = await response.json()
      if (currentRequest !== this._requestId) return
      this._renderList(payload.items || [], {pagination: payload.pagination || {}})
    } catch (error) {
      if (error.name === "AbortError") return
      this._renderEmpty("Something went wrong with search. Please try again.")
    }
  }
}

export default VNSearch
