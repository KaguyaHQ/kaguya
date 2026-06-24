const ClientTagFilter = {
  mounted() {
    this.input = this.el.querySelector("[data-client-tag-filter-input]")
    this.empty = this.el.querySelector("[data-client-tag-filter-empty]")
    this.options = Array.from(this.el.querySelectorAll("[data-client-tag-filter-option]"))

    this._onInput = () => this._filter()
    this._onToggle = () => {
      if (this.el.open) {
        requestAnimationFrame(() => this.input?.focus())
      } else if (this.input) {
        this.input.value = ""
        this._filter()
      }
    }

    this.input?.addEventListener("input", this._onInput)
    this.el.addEventListener("toggle", this._onToggle)
    this._filter()
  },

  destroyed() {
    this.input?.removeEventListener("input", this._onInput)
    this.el.removeEventListener("toggle", this._onToggle)
  },

  updated() {
    this.options = Array.from(this.el.querySelectorAll("[data-client-tag-filter-option]"))
    this._filter()
  },

  _filter() {
    const query = (this.input?.value || "").trim().toLowerCase()
    let visible = 0

    this.options.forEach(option => {
      const text = option.dataset.tagName || ""
      const matches = query === "" || text.includes(query)
      option.hidden = !matches
      if (matches) visible += 1
    })

    if (this.empty) this.empty.hidden = visible !== 0
    this.el.querySelector("[data-tag-picker-label]")?.replaceChildren(searching ? "Results" : "Popular")
  },
}

export default ClientTagFilter
