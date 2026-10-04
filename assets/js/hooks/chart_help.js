export default {
  mounted() {
    const trigger = this.el.querySelector("button")
    const tooltip = this.el.querySelector('[role="tooltip"]')
    const show = () => {
      tooltip.dispatchEvent(new Event("anchored-popover:show"))
    }
    const hide = () => {
      tooltip.dispatchEvent(new Event("anchored-popover:hide"))
    }
    this.onEnter = event => { if (event.pointerType !== "touch") show() }
    this.onLeave = () => { if (document.activeElement !== trigger) hide() }
    this.onClick = event => { event.preventDefault(); show() }
    this.onFocus = show
    this.onBlur = hide
    this.onScroll = hide
    this.el.addEventListener("pointerenter", this.onEnter)
    this.el.addEventListener("pointerleave", this.onLeave)
    trigger.addEventListener("click", this.onClick)
    trigger.addEventListener("focus", this.onFocus)
    trigger.addEventListener("blur", this.onBlur)
    window.addEventListener("scroll", this.onScroll, true)
  },
  destroyed() {
    const trigger = this.el.querySelector("button")
    this.el.removeEventListener("pointerenter", this.onEnter)
    this.el.removeEventListener("pointerleave", this.onLeave)
    trigger.removeEventListener("click", this.onClick)
    trigger.removeEventListener("focus", this.onFocus)
    trigger.removeEventListener("blur", this.onBlur)
    window.removeEventListener("scroll", this.onScroll, true)
  }
}
