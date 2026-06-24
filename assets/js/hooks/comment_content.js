const CommentContent = {
  mounted() {
    this._reveal = el => {
      if (el.classList.contains("revealed")) return
      el.classList.add("revealed")
      el.removeAttribute("aria-hidden")
      el.removeAttribute("aria-label")
      el.removeAttribute("role")
      el.removeAttribute("tabindex")
    }

    this._onClick = event => {
      const spoiler = event.target.closest("[data-spoiler]")
      if (!spoiler || !this.el.contains(spoiler)) return
      event.preventDefault()
      this._reveal(spoiler)
    }

    this._onKeyDown = event => {
      const active = document.activeElement
      if (!active || !this.el.contains(active) || !active.hasAttribute("data-spoiler")) return

      if (event.key === "Enter" || event.key === " " || event.key === "Spacebar") {
        event.preventDefault()
        this._reveal(active)
      }
    }

    this.el.addEventListener("click", this._onClick)
    this.el.addEventListener("keydown", this._onKeyDown)
  },

  destroyed() {
    this.el.removeEventListener("click", this._onClick)
    this.el.removeEventListener("keydown", this._onKeyDown)
  }
}

export default CommentContent
