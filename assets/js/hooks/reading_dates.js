// Native date inputs report value="" for both blanks and incomplete dates.
// Do not let a LiveView change patch erase an incomplete edit as if it were blank.
const ReadingDates = {
  mounted() {
    this.onEdit = event => {
      if (event.target.matches('input[type="date"]') && event.target.validity.badInput) {
        event.stopImmediatePropagation()
      }
    }
    this.onClear = event => {
      const input = this.el.querySelector(`#${event.detail.id}`)
      if (!input) return
      input.value = ""
      input.dispatchEvent(new Event("input", {bubbles: true}))
    }
    this.el.addEventListener("input", this.onEdit, true)
    this.el.addEventListener("change", this.onEdit, true)
    this.el.addEventListener("reading-date:clear", this.onClear)
  },
  destroyed() {
    this.el.removeEventListener("input", this.onEdit, true)
    this.el.removeEventListener("change", this.onEdit, true)
    this.el.removeEventListener("reading-date:clear", this.onClear)
  }
}
export default ReadingDates
