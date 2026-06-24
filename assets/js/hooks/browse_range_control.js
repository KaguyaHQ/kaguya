const BrowseRangeControl = {
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

    this.minSlider = this.el.querySelector("[data-range-min-slider]")
    this.maxSlider = this.el.querySelector("[data-range-max-slider]")
    this.minInput = this.el.querySelector("[data-range-min-input]")
    this.maxInput = this.el.querySelector("[data-range-max-input]")
    this.fill = this.el.querySelector("[data-range-fill]")
    this.sliderTrack = this.el.querySelector("[data-range-slider]")
    this.stops = (this.el.dataset.stops || "")
      .split(",")
      .map(value => parseFloat(value))
      .filter(value => !Number.isNaN(value))
    this.minRange = parseFloat(this.el.dataset.minRange || "0")
    this.maxRange = parseFloat(this.el.dataset.maxRange || "100")

    if (!this.minSlider || !this.maxSlider || !this.minInput || !this.maxInput || !this.fill) return

    this._onMinSliderInput = () => this._syncFromSlider("min")
    this._onMaxSliderInput = () => this._syncFromSlider("max")
    this._onMinInputCommit = () => this._syncFromInput("min")
    this._onMaxInputCommit = () => this._syncFromInput("max")
    this._onTrackPointerDown = event => this._syncFromTrack(event)
    this._onInputKeydown = event => {
      if (event.key === "Enter") event.currentTarget.blur()
    }

    this.minSlider.addEventListener("input", this._onMinSliderInput)
    this.maxSlider.addEventListener("input", this._onMaxSliderInput)
    this.minInput.addEventListener("blur", this._onMinInputCommit)
    this.maxInput.addEventListener("blur", this._onMaxInputCommit)
    this.minInput.addEventListener("keydown", this._onInputKeydown)
    this.maxInput.addEventListener("keydown", this._onInputKeydown)
    this.sliderTrack?.addEventListener("pointerdown", this._onTrackPointerDown)

    this._updateFill()

    this._teardown = () => {
      this.minSlider?.removeEventListener("input", this._onMinSliderInput)
      this.maxSlider?.removeEventListener("input", this._onMaxSliderInput)
      this.minInput?.removeEventListener("blur", this._onMinInputCommit)
      this.maxInput?.removeEventListener("blur", this._onMaxInputCommit)
      this.minInput?.removeEventListener("keydown", this._onInputKeydown)
      this.maxInput?.removeEventListener("keydown", this._onInputKeydown)
      this.sliderTrack?.removeEventListener("pointerdown", this._onTrackPointerDown)
    }
  },

  _syncFromTrack(event) {
    if (event.target?.matches?.("input[type='range']")) return
    const rect = this.sliderTrack.getBoundingClientRect()
    if (rect.width <= 0) return

    const min = parseFloat(this.minSlider.min)
    const max = parseFloat(this.minSlider.max)
    const pct = Math.max(0, Math.min(1, (event.clientX - rect.left) / rect.width))
    const raw = min + pct * (max - min)
    const step = parseFloat(this.minSlider.step || "1") || 1
    const next = Math.max(min, Math.min(max, Math.round(raw / step) * step))
    const currentMin = parseFloat(this.minSlider.value)
    const currentMax = parseFloat(this.maxSlider.value)
    const target = Math.abs(next - currentMin) <= Math.abs(next - currentMax) ? "min" : "max"

    if (target === "min") this.minSlider.value = String(Math.min(next, currentMax))
    else this.maxSlider.value = String(Math.max(next, currentMin))

    this._syncFromSlider(target)
  },

  _syncFromSlider(source) {
    let min = parseFloat(this.minSlider.value)
    let max = parseFloat(this.maxSlider.value)

    if (min > max) {
      if (source === "min") {
        max = min
        this.maxSlider.value = String(max)
      } else {
        min = max
        this.minSlider.value = String(min)
      }
    }

    const minValue = this._displayValue(min)
    const maxValue = this._displayValue(max)
    this.minInput.value = minValue <= this.minRange ? "" : String(minValue)
    this.maxInput.value = maxValue >= this.maxRange ? "" : String(maxValue)
    this._updateFill()
  },

  _syncFromInput(source) {
    const minValue = this._parseInput(this.minInput.value, this.minRange)
    const maxValue = this._parseInput(this.maxInput.value, this.maxRange)
    let min = Math.max(this.minRange, Math.min(minValue, this.maxRange))
    let max = Math.max(this.minRange, Math.min(maxValue, this.maxRange))

    if (min > max) {
      if (source === "min") min = max
      else max = min
    }

    this.minInput.value = min <= this.minRange ? "" : String(min)
    this.maxInput.value = max >= this.maxRange ? "" : String(max)
    this.minSlider.value = String(this._sliderValue(min))
    this.maxSlider.value = String(this._sliderValue(max))
    this._updateFill()
  },

  _parseInput(value, fallback) {
    if (String(value || "").trim() === "") return fallback
    const parsed = parseFloat(value)
    return Number.isNaN(parsed) ? fallback : parsed
  },

  _displayValue(sliderValue) {
    if (this.stops.length === 0) return Number(sliderValue)
    return this.stops[Math.round(sliderValue)] ?? this.stops[0]
  },

  _sliderValue(value) {
    if (this.stops.length === 0) return value

    let closest = 0
    let diff = Math.abs(this.stops[0] - value)
    this.stops.forEach((stop, index) => {
      const nextDiff = Math.abs(stop - value)
      if (nextDiff < diff) {
        closest = index
        diff = nextDiff
      }
    })
    return closest
  },

  _updateFill() {
    const min = parseFloat(this.minSlider.min)
    const max = parseFloat(this.minSlider.max)
    const left = parseFloat(this.minSlider.value)
    const right = parseFloat(this.maxSlider.value)
    const span = Math.max(1, max - min)
    const leftPct = ((Math.min(left, right) - min) / span) * 100
    const rightPct = ((Math.max(left, right) - min) / span) * 100

    this.fill.style.left = `${leftPct}%`
    this.fill.style.width = `${Math.max(0, rightPct - leftPct)}%`
    this.fill.classList.toggle("bg-white/[8%]", leftPct <= 0 && rightPct >= 100)
    this.fill.classList.toggle("bg-button-background-brand-default", !(leftPct <= 0 && rightPct >= 100))
    this.minSlider.style.zIndex = left > max - 2 ? "4" : "3"
    this.maxSlider.style.zIndex = "3"
  }
}

export default BrowseRangeControl
