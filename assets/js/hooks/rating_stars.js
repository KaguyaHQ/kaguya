const RatingStars = {
  mounted() { this.bind() },
  updated() { this.bind() },
  bind() {
    const row = this.el
    const stars = row.querySelectorAll("[data-star]")
    if (!stars.length) return

    const clearPreview = () => stars.forEach(s => { s.dataset.hover = "" })

    const previewAt = clientX => {
      const rect = row.getBoundingClientRect()
      const ratio = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width))
      const value = Math.max(0.5, Math.min(5, Math.ceil(ratio * 10) / 2))
      stars.forEach((star, i) => {
        if (value >= i + 1) star.dataset.hover = "full"
        else if (value >= i + 0.5) star.dataset.hover = "half"
        else star.dataset.hover = "empty"
      })
    }

    if (this._move) row.removeEventListener("pointermove", this._move)
    if (this._leave) row.removeEventListener("pointerleave", this._leave)

    this._move = e => previewAt(e.clientX)
    this._leave = clearPreview
    row.addEventListener("pointermove", this._move)
    row.addEventListener("pointerleave", this._leave)
  },
  destroyed() {
    if (this._move) this.el.removeEventListener("pointermove", this._move)
    if (this._leave) this.el.removeEventListener("pointerleave", this._leave)
  }
}

export default RatingStars
