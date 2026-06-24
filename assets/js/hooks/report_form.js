const ReportForm = {
  mounted() {
    this.reason = this.el.querySelector("input[name='reason']")
    this.category = this.el.querySelector("select[name='category']")
    this.submit = this.el.querySelector("[data-report-submit]")
    this.counter = this.el.querySelector("[data-reason-counter]")
    this._onInput = () => this._sync()
    this._onSubmit = () => {
      if (!this.submit || this.submit.disabled) return
      this.submit.disabled = true
      this.submit.textContent = "Submitting..."
    }

    this.reason?.addEventListener("input", this._onInput)
    this.category?.addEventListener("change", this._onInput)
    this.el.addEventListener("submit", this._onSubmit)
    this._sync()
  },

  updated() {
    this._sync()
  },

  destroyed() {
    this.reason?.removeEventListener("input", this._onInput)
    this.category?.removeEventListener("change", this._onInput)
    this.el.removeEventListener("submit", this._onSubmit)
  },

  _sync() {
    const length = this.reason?.value.length || 0
    if (this.counter) this.counter.textContent = `${length}/200`
    if (this.submit) {
      this.submit.disabled = !this.category?.value || this.reason?.value.trim().length === 0
    }
  }
}

export default ReportForm
