const BrowseTagPicker = {
  mounted() {
    this._bind()
  },

  updated() {
    this._bind()
  },

  destroyed() {
    this._teardown?.()
  },

  _bind() {
    this._teardown?.()

    this.includeInput = this.el.querySelector("[data-tag-picker-include]")
    this.excludeInput = this.el.querySelector("[data-tag-picker-exclude]")
    this.searchInput = this.el.querySelector("[data-tag-picker-search]")
    this.empty = this.el.querySelector("[data-tag-picker-empty]")
    this.rows = Array.from(this.el.querySelectorAll("[data-tag-picker-row]"))
    this.initialLimit = parseInt(this.el.dataset.initialLimit || "150", 10)
    this.searchLimit = parseInt(this.el.dataset.searchLimit || "120", 10)
    this.tagDataUrl = this.el.dataset.tagPickerDataUrl || null
    this.allTags = []
    this.allTagsLoaded = false
    this.allTagsPromise = null

    this._onSearch = () => {
      this._ensureFullTags()
      this._render()
    }
    this._onFocus = () => this._ensureFullTags()
    this._onClick = event => {
      const row = event.target.closest("[data-tag-picker-row]")
      if (!row) return

      const excludeButton = event.target.closest("[data-tag-picker-exclude-button]")
      event.preventDefault()

      if (excludeButton) this._toggleExclude(row.dataset.tagSlug)
      else this._toggleInclude(row.dataset.tagSlug)
    }

    this.searchInput?.addEventListener("input", this._onSearch)
    this.searchInput?.addEventListener("focus", this._onFocus)
    this.el.addEventListener("click", this._onClick)
    this._render()

    this._teardown = () => {
      this.searchInput?.removeEventListener("input", this._onSearch)
      this.searchInput?.removeEventListener("focus", this._onFocus)
      this.el.removeEventListener("click", this._onClick)
    }
  },

  _ensureFullTags() {
    if (this.allTagsLoaded || !this.tagDataUrl) return this.allTagsPromise
    if (this.allTagsPromise) return this.allTagsPromise

    this.allTagsPromise = fetch(this.tagDataUrl, {credentials: "omit"})
      .then(response => (response.ok ? response.json() : []))
      .then(tags => {
        this.allTags = Array.isArray(tags) ? tags : []
        this.allTagsLoaded = true
        this._render()
      })
      .catch(() => {
        // Network failure: leave allTags empty. Server-rendered rows still
        // render and remain searchable via their data-tag-name attributes.
        this.allTagsPromise = null
      })

    return this.allTagsPromise
  },

  _values(input) {
    return new Set(
      (input?.value || "")
        .split(",")
        .map(value => value.trim())
        .filter(Boolean),
    )
  },

  _write(input, values) {
    if (input) input.value = Array.from(values).join(",")
  },

  _toggleInclude(slug) {
    const included = this._values(this.includeInput)
    const excluded = this._values(this.excludeInput)

    if (included.has(slug)) included.delete(slug)
    else {
      included.add(slug)
      excluded.delete(slug)
    }

    this._write(this.includeInput, included)
    this._write(this.excludeInput, excluded)
    this._render()
  },

  _toggleExclude(slug) {
    const included = this._values(this.includeInput)
    const excluded = this._values(this.excludeInput)

    if (excluded.has(slug)) excluded.delete(slug)
    else {
      excluded.add(slug)
      included.delete(slug)
    }

    this._write(this.includeInput, included)
    this._write(this.excludeInput, excluded)
    this._render()
  },

  _render() {
    const included = this._values(this.includeInput)
    const excluded = this._values(this.excludeInput)
    const words = (this.searchInput?.value || "")
      .trim()
      .toLowerCase()
      .split(/\s+/)
      .filter(Boolean)
    const searching = words.length > 0
    this._syncRowsForQuery(included, excluded, words, searching)

    let visible = 0
    let suggestions = 0

    this.rows.forEach(row => {
      const slug = row.dataset.tagSlug
      const isIncluded = included.has(slug)
      const isExcluded = excluded.has(slug)
      const selected = isIncluded || isExcluded
      const matches = words.every(word => (row.dataset.tagName || "").includes(word))
      const withinLimit = selected || searching || suggestions < this.initialLimit
      const show = matches && withinLimit

      row.hidden = !show
      row.dataset.selected = String(selected)
      row.dataset.included = String(isIncluded)
      row.dataset.excluded = String(isExcluded)
      const checkbox = row.querySelector("[data-tag-picker-checkbox]")
      if (checkbox) {
        checkbox.setAttribute("data-checked", String(isIncluded))
        checkbox.innerHTML = isIncluded ? this._checkIconMarkup() : ""
      }
      row.querySelector("[data-tag-picker-exclude-button]")?.setAttribute("data-excluded", String(isExcluded))

      if (show) visible += 1
      if (!selected && matches && !searching) suggestions += 1
    })

    this._orderRows()

    if (this.empty) this.empty.hidden = visible !== 0
  },

  _orderRows() {
    const list = this.el.querySelector("[data-tag-picker-list]")
    if (!list || !this.empty) return

    const included = this.rows.filter(row => row.dataset.included === "true")
    const excluded = this.rows.filter(row => row.dataset.excluded === "true")
    const unselected = this.rows.filter(
      row => row.dataset.included !== "true" && row.dataset.excluded !== "true",
    )
    ;[...included, ...excluded, ...unselected].forEach(row => this.empty.before(row))
  },

  _syncRowsForQuery(included, excluded, words, searching) {
    if (!this.allTags.length) return

    const existing = new Set(this.rows.map(row => row.dataset.tagSlug))
    const selected = new Set([...included, ...excluded])
    const limit = searching ? this.searchLimit : this.initialLimit
    let added = 0

    this.allTags.forEach(tag => {
      if (existing.has(tag.slug)) return

      const name = String(tag.name || "")
      const matches = words.every(word => name.toLowerCase().includes(word))
      if (!selected.has(tag.slug) && (!matches || added >= limit)) return

      const row = this._buildRow(tag, included.has(tag.slug), excluded.has(tag.slug))
      this.empty?.before(row)
      this.rows.push(row)
      existing.add(tag.slug)
      if (!selected.has(tag.slug)) added += 1
    })
  },

  _buildRow(tag, included, excluded) {
    const row = document.createElement("div")
    row.className = "flex cursor-pointer items-center justify-between rounded px-3.5 py-3 transition hover:bg-white/[2%] data-[excluded=true]:bg-red-900/20 data-[selected=true]:bg-white/[2%]"
    row.dataset.tagPickerRow = ""
    row.dataset.tagSlug = tag.slug
    row.dataset.tagName = String(tag.name || "").toLowerCase()
    row.dataset.selected = String(included || excluded)
    row.dataset.included = String(included)
    row.dataset.excluded = String(excluded)
    row.innerHTML = `
      <button type="button" class="flex min-w-0 flex-1 items-center gap-2 text-left" data-tag-picker-include-button>
        <span class="flex size-3.5 shrink-0 items-center justify-center rounded-[3px] border-[2px] border-foreground-secondary text-surface-elevated data-[checked=true]:border-foreground-secondary data-[checked=true]:bg-foreground-secondary" data-tag-picker-checkbox data-checked="${included}"></span>
        <span class="min-w-0 truncate text-sm leading-[17px]" data-tag-picker-name></span>
        <span class="shrink-0 text-xs leading-[15px] text-foreground-primary/40" data-tag-picker-count></span>
      </button>
      <button type="button" class="-my-2 -mr-2 flex size-8 shrink-0 items-center justify-center text-foreground-quaternary transition hover:text-semantic-error data-[excluded=true]:text-semantic-error" data-tag-picker-exclude-button data-excluded="${excluded}" aria-label="Exclude"></button>
    `
    row.querySelector("[data-tag-picker-name]").textContent = tag.name || tag.slug
    row.querySelector("[data-tag-picker-count]").textContent = this._shortCount(tag.vnsCount || 0)
    row.querySelector("[data-tag-picker-exclude-button]").setAttribute("aria-label", `Exclude ${tag.name || tag.slug}`)
    row.querySelector("[data-tag-picker-exclude-button]").append(this._circleMinusIcon())
    return row
  },

  _shortCount(count) {
    if (count >= 1000000) return `${Math.round((count / 1000000) * 10) / 10}m`
    if (count >= 1000) return `${Math.round((count / 1000) * 10) / 10}k`
    return String(count)
  },

  _circleMinusIcon() {
    const icon = document.createElementNS("http://www.w3.org/2000/svg", "svg")
    icon.setAttribute("viewBox", "0 0 24 24")
    icon.setAttribute("fill", "none")
    icon.setAttribute("class", "size-4")
    icon.setAttribute("aria-hidden", "true")
    icon.innerHTML = '<circle cx="12" cy="12" r="10" stroke="currentColor" stroke-width="2"></circle><path d="M8 12h8" stroke="currentColor" stroke-width="2" stroke-linecap="round"></path>'
    return icon
  },

  _checkIconMarkup() {
    return '<svg viewBox="0 0 24 24" fill="none" class="size-3" aria-hidden="true"><path d="m20 6-11 11-5-5" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"></path></svg>'
  },
}

export default BrowseTagPicker
