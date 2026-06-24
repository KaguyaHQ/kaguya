const LikeButton = {
  mounted() {
    this._previousPressed = this.el.getAttribute("aria-pressed")
    this._previousCount = parseCount(this.el.dataset.likeCountNumber)
    this._onClick = (event) => this._applyOptimistic(event)
    this.el.addEventListener("click", this._onClick)
  },

  updated() {
    const nextPressed = this.el.getAttribute("aria-pressed")
    const nextCount = parseCount(this.el.dataset.likeCountNumber)

    if (nextPressed !== this._previousPressed) {
      this._animatePop(nextPressed === "true")
    }
    if (nextCount !== this._previousCount) {
      this._animateCount(nextCount > this._previousCount)
    }
    syncCountText(this.el, nextCount)
    syncCountVisibility(this.el, nextCount)

    this._previousPressed = nextPressed
    this._previousCount = nextCount
  },

  destroyed() {
    this.el.removeEventListener("click", this._onClick)
  },

  _applyOptimistic() {
    const wasPressed = this.el.getAttribute("aria-pressed") === "true"
    const nextPressed = !wasPressed
    const currentCount = parseCount(this.el.dataset.likeCountNumber)
    const nextCount = Math.max(0, currentCount + (nextPressed ? 1 : -1))

    this.el.setAttribute("aria-pressed", String(nextPressed))
    this.el.setAttribute("aria-label", nextPressed ? "Unlike" : "Like")
    this.el.dataset.likeCountNumber = String(nextCount)

    syncCountText(this.el, nextCount)
    syncCountVisibility(this.el, nextCount)

    this._animatePop(nextPressed)
    if (nextCount !== currentCount) {
      this._animateCount(nextPressed)
    }

    this._previousPressed = String(nextPressed)
    this._previousCount = nextCount
  },

  _animatePop(liked) {
    const wrap = this.el.querySelector("[data-like-heart-wrap]")
    if (!wrap) return
    wrap.classList.remove("kaguya-like-pop", "kaguya-like-unpop")
    void wrap.offsetWidth
    wrap.classList.add(liked ? "kaguya-like-pop" : "kaguya-like-unpop")
  },

  _animateCount(up) {
    const count = this.el.querySelector("[data-like-count]")
    if (!count) return
    count.classList.remove("kaguya-like-count-up", "kaguya-like-count-down")
    void count.offsetWidth
    count.classList.add(up ? "kaguya-like-count-up" : "kaguya-like-count-down")
  }
}

function parseCount(raw) {
  const n = parseInt(raw || "0", 10)
  return Number.isFinite(n) ? n : 0
}

function formatCount(value) {
  if (value >= 1_000_000) return `${(value / 1_000_000).toFixed(1)}M`
  if (value >= 1_000) return `${(value / 1_000).toFixed(1)}K`
  return String(value)
}

function syncCountText(el, count) {
  const formatted = formatCount(count)
  el.querySelectorAll("[data-like-count]").forEach((node) => {
    if (node.textContent.trim() !== formatted) {
      node.textContent = formatted
    }
  })
  // Some templates render a sibling invisible spacer copy to reserve width;
  // keep it in sync so the visible count stays centered.
  el.querySelectorAll("[data-like-count-spacer]").forEach((node) => {
    if (node.textContent.trim() !== formatted) {
      node.textContent = formatted
    }
  })
}

function syncCountVisibility(el, count) {
  const wrappers = el.querySelectorAll("[data-like-count-display]")
  wrappers.forEach((wrapper) => {
    wrapper.classList.toggle("hidden", count <= 0)
  })
}

export default LikeButton
