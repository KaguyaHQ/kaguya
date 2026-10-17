// Landing story motion (KaguyaWeb.HomeLive.LandingStory).
//
// Wide screens: the chapter nearest the middle of the viewport is active.
// Its window fades in on the sticky stage, the page tint follows, and one
// cover (the "traveler") arcs from its slot in the previous window to its
// slot in the next. Each chapter has one signature motion tied to scroll
// progress, so scrolling back simply reverses it:
//   lists   – the traveler is re-ranked from #14 to #3 at the midpoint
//   profile – the banner settles
//   stats   – the chart line draws and the total counts up
//   import  – the link types, the bar fills, covers populate
//
// Narrow screens: windows stay under their chapter text, keep the same
// scroll-driven motion, and fade up once when they first scroll into view.

const WIDE = "(min-width: 1024px)"
const EASE = "cubic-bezier(.2,.7,.2,1)"
const CHART = { width: 640, padX: 40, top: 40, bottom: 250 }
const UNITS = { hours: "hours since 2023", titles: "titles finished since 2023" }
const IMPORT_LINK = "vndb.org/u184022"
const IMPORT_TOTAL = 59
const BLEED = 140
const MAX_PANEL_W = 1240

const clamp = (v, lo = 0, hi = 1) => Math.min(hi, Math.max(lo, v))

const LandingStory = {
  mounted() {
    this.reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this.wide = window.matchMedia(WIDE)
    this.chapters = [...this.el.querySelectorAll("[data-chapter]")]
    this.panels = Object.fromEntries(
      [...this.el.querySelectorAll("[data-panel]")].map((p) => [p.dataset.panel, p])
    )
    this.stage = this.el.querySelector("[data-stage]")
    this.stageCol = this.el.querySelector("[data-stage-col]")
    this.traveler = this.el.querySelector("[data-traveler]")
    this.ambient = [...this.el.querySelectorAll(".landing-ambient img")]
    this.progress = {}
    this.active = null
    this.travelerAt = null

    this.setupList()
    this.setupChart()

    this.onScroll = () => {
      if (this.frame) return
      this.frame = requestAnimationFrame(() => {
        this.frame = null
        this.update()
      })
    }
    this.onResize = () => {
      this.sizeStage()
      this.placeTraveler()
      this.update()
    }
    this.onWideChange = () => {
      this.layout()
      this.update()
    }

    window.addEventListener("scroll", this.onScroll, { passive: true })
    window.addEventListener("resize", this.onResize)
    this.wide.addEventListener("change", this.onWideChange)

    this.seenObserver = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) entry.target.classList.add("is-seen")
        }
      },
      { rootMargin: "0px 0px -15% 0px" }
    )
    Object.values(this.panels).forEach((p) => this.seenObserver.observe(p))

    this.layout()
    this.el.dataset.ready = ""
    this.update()
    document.fonts?.ready.then(() => this.placeTraveler())
  },

  destroyed() {
    window.removeEventListener("scroll", this.onScroll)
    window.removeEventListener("resize", this.onResize)
    this.wide.removeEventListener("change", this.onWideChange)
    this.seenObserver.disconnect()
    if (this.frame) cancelAnimationFrame(this.frame)
    clearTimeout(this.toastTimer)
    this.pills.forEach((pill) => pill.removeEventListener("click", this.onPill))
  },

  // Wide: windows live on the sticky stage. Narrow: each sits under its chapter.
  layout() {
    for (const chapter of this.chapters) {
      const panel = this.panels[chapter.dataset.chapter]
      if (this.wide.matches) this.stage.appendChild(panel)
      else chapter.appendChild(panel)
    }
    this.traveler.hidden = !this.wide.matches
    for (const [key, panel] of Object.entries(this.panels)) {
      panel.inert = this.wide.matches && key !== this.active
    }
    this.sizeStage()
    this.placeTraveler()
  },

  // The window runs well past the right edge so the crop reads as deliberate
  // (a sliver looks like a layout bug). Its content keeps clear of the cropped
  // part; the app bar does not, so its icons fall off-screen. Very wide
  // screens get a fully visible floating window instead.
  sizeStage() {
    if (!this.wide.matches) return
    const left = this.stageCol.getBoundingClientRect().left
    const room = window.innerWidth - left
    const width = room + BLEED <= MAX_PANEL_W ? Math.max(720, room + BLEED) : Math.min(1000, room - 48)
    this.stage.style.setProperty("--landing-panel-w", `${width}px`)
    this.stage.style.setProperty("--landing-crop", `${Math.max(0, left + width - window.innerWidth)}px`)
  },

  update() {
    const vh = window.innerHeight
    let nearest = null
    let nearestDistance = Infinity

    for (const chapter of this.chapters) {
      const key = chapter.dataset.chapter
      const rect = chapter.getBoundingClientRect()
      let p
      if (this.reduce) p = 1
      // finishes as the chapter reaches the middle of the screen
      else if (this.wide.matches) p = clamp((vh * 0.5 - (rect.top + rect.height * 0.5)) / (rect.height * 0.45) + 1)
      else p = clamp((vh * 0.85 - this.panels[key].getBoundingClientRect().top) / (vh * 0.6))

      if (p !== this.progress[key]) {
        this.progress[key] = p
        this.steps[key].call(this, p)
      }

      const distance = Math.abs(rect.top + rect.height / 2 - vh / 2)
      if (distance < nearestDistance) {
        nearestDistance = distance
        nearest = key
      }
    }

    this.activate(nearest)
  },

  activate(key) {
    if (key === this.active) return
    if (this.active) this.panels[this.active].classList.remove("is-active")
    this.active = key
    this.el.dataset.active = key
    this.chapters.forEach((c) => c.classList.toggle("is-active", c.dataset.chapter === key))
    this.ambient.forEach((img) => img.classList.toggle("is-active", img.dataset.for === key))
    for (const [k, panel] of Object.entries(this.panels)) {
      panel.inert = this.wide.matches && k !== key
    }
    this.panels[key].classList.add("is-active")
    this.travel(key)
  },

  // ---------------------------------------------------------------------------
  // Traveler: the only large motion on a switch. It arcs over while the next
  // window settles beneath it, and parks (fades) where a window has no slot.
  // ---------------------------------------------------------------------------

  slotRect(key) {
    const panel = this.panels[key]
    const slot = panel.querySelector(`[data-slot="${key}"]`)
    if (!slot) return null
    let x = 0
    let y = 0
    for (let el = slot; el && el !== panel; el = el.offsetParent) {
      x += el.offsetLeft
      y += el.offsetTop
    }
    return { x, y, w: slot.offsetWidth, h: slot.offsetHeight }
  },

  setTraveler(rect) {
    Object.assign(this.traveler.style, {
      transform: `translate(${rect.x}px, ${rect.y}px)`,
      width: `${rect.w}px`,
      height: `${rect.h}px`
    })
    this.travelerAt = rect
  },

  placeTraveler() {
    if (!this.wide.matches || !this.active) return
    const rect = this.slotRect(this.active)
    if (rect) this.setTraveler(rect)
  },

  travel(key, { duration = 950, lift = 48 } = {}) {
    if (!this.wide.matches) return
    const to = this.slotRect(key)
    const t = this.traveler
    t.classList.toggle("is-parked", !to)
    if (!to) return

    const from = this.travelerAt
    if (!from || this.reduce) {
      this.setTraveler(to)
      t.classList.add("is-ready")
      return
    }

    const frame = (r) => ({ transform: `translate(${r.x}px, ${r.y}px)`, width: `${r.w}px`, height: `${r.h}px` })
    const mid = {
      x: (from.x + to.x) / 2,
      y: Math.min(from.y, to.y) - lift,
      w: ((from.w + to.w) / 2) * 1.06,
      h: ((from.h + to.h) / 2) * 1.06
    }
    t.getAnimations().forEach((a) => a.cancel())
    t.classList.add("is-flying")
    this.setTraveler(to)
    t.animate([frame(from), { ...frame(mid), offset: 0.5 }, frame(to)], {
      duration,
      easing: "cubic-bezier(.65,0,.25,1)"
    })
      .finished.then(() => t.classList.remove("is-flying"))
      .catch(() => {})
  },

  // ---------------------------------------------------------------------------
  // Lists: one reversible re-rank, animated with FLIP. The traveler is the
  // entry being moved, so it slides along with the grid.
  // ---------------------------------------------------------------------------

  setupList() {
    this.listGrid = this.el.querySelector("[data-list-grid]")
    this.toast = this.el.querySelector("[data-toast]")
    this.rankedEntry = this.listGrid.querySelector("[data-slot=\"lists\"]").closest("li")
    this.originalIndex = [...this.listGrid.children].indexOf(this.rankedEntry)
    this.ranked = false
  },

  flipList(mutate) {
    const before = new Map([...this.listGrid.children].map((el) => [el, el.getBoundingClientRect()]))
    mutate()
    ;[...this.listGrid.children].forEach((el, i) => {
      el.querySelector(".landing-rank").textContent = i + 1
      const a = before.get(el)
      const b = el.getBoundingClientRect()
      if (a.left === b.left && a.top === b.top) return
      el.animate([{ transform: `translate(${a.left - b.left}px, ${a.top - b.top}px)` }, { transform: "none" }], {
        duration: this.reduce ? 0 : 650,
        easing: EASE
      })
    })
    if (this.active === "lists") this.travel("lists", { duration: 650, lift: 24 })
  },

  setRanked(on) {
    if (on === this.ranked) return
    this.ranked = on
    const children = this.listGrid.children
    // insertBefore reads the anchor before moving the entry, so these indices are pre-move.
    const anchor = on ? children[2] : children[this.originalIndex + 1] || null
    this.flipList(() => this.listGrid.insertBefore(this.rankedEntry, anchor))
    clearTimeout(this.toastTimer)
    this.toast.classList.toggle("is-shown", on)
    if (on) this.toastTimer = setTimeout(() => this.toast.classList.remove("is-shown"), 2400)
  },

  // ---------------------------------------------------------------------------
  // Stats chart: built from data attributes; the metric pills morph the line.
  // ---------------------------------------------------------------------------

  setupChart() {
    const svg = this.el.querySelector("[data-chart]")
    this.chart = {
      svg,
      line: svg.querySelector("[data-line]"),
      area: svg.querySelector("[data-area]"),
      labels: JSON.parse(svg.dataset.labels),
      data: { hours: JSON.parse(svg.dataset.hours), titles: JSON.parse(svg.dataset.titles) },
      mode: "hours",
      length: 0
    }
    const n = this.chart.labels.length
    const ns = "http://www.w3.org/2000/svg"
    const points = svg.querySelector("[data-points]")
    const labels = svg.querySelector("[data-labels-group]")
    this.chart.x = (i) => CHART.padX + (i * (CHART.width - CHART.padX * 2)) / (n - 1)
    this.chart.points = this.chart.labels.map(() => {
      const dot = document.createElementNS(ns, "circle")
      dot.setAttribute("r", "5")
      dot.setAttribute("class", "landing-chart-point")
      const value = document.createElementNS(ns, "text")
      value.setAttribute("y", "-14")
      value.setAttribute("class", "landing-chart-value")
      points.append(dot, value)
      return { dot, value }
    })
    this.chart.labels.forEach((label, i) => {
      const text = document.createElementNS(ns, "text")
      text.setAttribute("x", this.chart.x(i))
      text.setAttribute("y", "286")
      text.setAttribute("class", "landing-chart-label")
      text.textContent = label
      labels.append(text)
    })

    this.pills = [...this.el.querySelectorAll(".landing-pill")]
    this.onPill = (e) => this.setChartMode(e.currentTarget.dataset.mode)
    this.pills.forEach((pill) => pill.addEventListener("click", this.onPill))
    this.setChartMode("hours")
  },

  setChartMode(mode) {
    const c = this.chart
    c.mode = mode
    this.panels.stats.dataset.mode = mode
    this.pills.forEach((pill) => pill.setAttribute("aria-pressed", String(pill.dataset.mode === mode)))

    const values = c.data[mode]
    const max = Math.max(...values)
    const pts = values.map((v, i) => [c.x(i), CHART.bottom - (v / max) * (CHART.bottom - CHART.top)])
    let d = `M${pts[0][0]},${pts[0][1]}`
    for (let i = 0; i < pts.length - 1; i++) {
      const [x0, y0] = pts[i]
      const [x1, y1] = pts[i + 1]
      const mx = (x0 + x1) / 2
      d += ` C${mx},${y0} ${mx},${y1} ${x1},${y1}`
    }
    const last = pts[pts.length - 1]
    const area = `${d} L${last[0]},${CHART.bottom} L${pts[0][0]},${CHART.bottom} Z`
    for (const [el, value] of [[c.line, d], [c.area, area]]) {
      el.setAttribute("d", value)
      el.style.d = `path("${value}")`
    }
    c.length = c.line.getTotalLength()
    pts.forEach(([x, y], i) => {
      c.points[i].dot.style.transform = c.points[i].value.style.transform = `translate(${x}px, ${y}px)`
      c.points[i].value.textContent = values[i]
    })
    this.el.querySelector("[data-bigunit]").textContent = UNITS[mode]
    this.steps.stats.call(this, this.progress.stats ?? 0)
  },

  // ---------------------------------------------------------------------------
  // Signature motions, each a pure function of scroll progress (0..1).
  // ---------------------------------------------------------------------------

  steps: {
    lists(p) {
      if (p >= 0.5) this.setRanked(true)
      else if (p < 0.4) this.setRanked(false)
    },

    profile(p) {
      const banner = this.panels.profile.querySelector("[data-banner]")
      banner.style.setProperty("--landing-banner-scale", (1.12 - 0.12 * p).toFixed(4))
      banner.style.setProperty("--landing-banner-y", `${(10 - 10 * p).toFixed(1)}px`)
    },

    stats(p) {
      const c = this.chart
      if (!c) return
      // dasharray is a fixed 1700, so the visible length is 1700 - offset even mid-morph.
      c.line.style.strokeDashoffset = 1700 - c.length * p
      c.area.style.clipPath = `inset(0 ${(100 - p * 100).toFixed(2)}% 0 0)`
      const last = c.points.length - 1
      c.points.forEach(({ dot, value }, i) => {
        const lit = p >= i / last - 0.001
        dot.classList.toggle("is-lit", lit)
        value.classList.toggle("is-lit", lit)
      })
      const total = c.data[c.mode].reduce((sum, v) => sum + v, 0)
      this.el.querySelector("[data-bignum]").textContent = Math.round(total * p)
    },

    import(p) {
      const panel = this.panels.import
      const typed = Math.floor(clamp((p - 0.04) / 0.24) * IMPORT_LINK.length)
      const fill = clamp((p - 0.32) / 0.56)
      panel.querySelector("[data-import-text]").textContent = IMPORT_LINK.slice(0, typed)
      panel.querySelector("[data-progress]").style.setProperty("--landing-progress", `${fill * 100}%`)
      panel.querySelector("[data-import-count]").textContent =
        fill > 0 ? `${Math.round(fill * IMPORT_TOTAL)} of ${IMPORT_TOTAL}` : ""
      panel.querySelector("[data-import-label]").textContent =
        fill >= 1
          ? "All matched"
          : fill > 0
            ? "Matching your visual novels"
            : typed === IMPORT_LINK.length
              ? "Ready to import"
              : "Paste your VNDB profile link"
      const covers = panel.querySelectorAll(".landing-import-cover")
      const shown = Math.round(fill * covers.length)
      covers.forEach((cover, i) => cover.classList.toggle("is-in", i < shown))
      panel.querySelector("[data-import-done]").classList.toggle("is-shown", fill >= 1)
    }
  }
}

export default LandingStory
