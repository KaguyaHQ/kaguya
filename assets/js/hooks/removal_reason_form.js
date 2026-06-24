const RemovalReasonForm = {
  mounted() {
    this.reasonSelect = this.el.querySelector("[data-removal-reason]")
    this.messageEl = this.el.querySelector("[data-removal-message]")
    this.submit = this.el.querySelector("[data-removal-submit]")
    // Switching reason always overwrites the message textarea with that
    // reason's default copy, even if the moderator had been editing it.
    // In-progress edits are discarded on reason change so the wording
    // stays consistent.
    this._onReasonChange = () => {
      if (!this.reasonSelect || !this.messageEl) return
      const option = this.reasonSelect.options[this.reasonSelect.selectedIndex]
      const defaultMessage = option?.dataset.defaultMessage
      if (defaultMessage) this.messageEl.value = defaultMessage
      this._sync()
    }
    this._onMessageInput = () => this._sync()
    this._onSubmit = () => {
      if (!this.submit || this.submit.disabled) return
      this.submit.disabled = true
    }

    this.reasonSelect?.addEventListener("change", this._onReasonChange)
    this.messageEl?.addEventListener("input", this._onMessageInput)
    this.el.addEventListener("submit", this._onSubmit)
    this._sync()
  },

  updated() {
    this._sync()
  },

  destroyed() {
    this.reasonSelect?.removeEventListener("change", this._onReasonChange)
    this.messageEl?.removeEventListener("input", this._onMessageInput)
    this.el.removeEventListener("submit", this._onSubmit)
  },

  _sync() {
    if (!this.submit) return
    const hasReason = !!this.reasonSelect?.value
    const hasMessage = (this.messageEl?.value || "").trim().length > 0
    this.submit.disabled = !(hasReason && hasMessage)
  }
}

export default RemovalReasonForm
