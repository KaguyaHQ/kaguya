// Markdown composer hook — paired with `KaguyaWeb.SharedComponents.MarkdownEditor`.
// Cmd/Ctrl+B/I/K wrap selection, Cmd/Ctrl+Enter submits, textarea auto-grows,
// focus expands the composer via the configured event.

const MarkdownEditor = {
  mounted() {
    this.submitButton =
      this.el.querySelector("[data-markdown-editor-submit]") ||
      this.el.querySelector("[data-reply-submit]")
    // Opt-in localStorage draft persistence. When `data-draft-key` is set (the
    // review editor), every keystroke is mirrored to localStorage and restored
    // when the editor reopens — so an accidental backdrop/Escape dismiss, a tab
    // close, or a dropped connection never loses a long-form review. The
    // comment composer omits the attribute and behaves exactly as before.
    this.draftKey = this.el.dataset.draftKey || null
    this._onInput = () => {
      this._sync()
      this._scheduleDraftSave()
    }
    this._onKeyDown = event => {
      const mod = event.metaKey || event.ctrlKey

      if (mod && event.key.toLowerCase() === "b") {
        event.preventDefault()
        this._wrapSelection("**", "**", "bold")
        return
      }

      if (mod && event.key.toLowerCase() === "i") {
        event.preventDefault()
        this._wrapSelection("*", "*", "italic")
        return
      }

      if (mod && event.key.toLowerCase() === "k") {
        event.preventDefault()
        this._insertLink()
        return
      }

      if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
        event.preventDefault()
        this._sync()
        // The hook attaches to either the form itself (comment composer) or
        // a div wrapping the textarea inside a larger form (review dialog).
        // In the second case, `requestSubmit` must come from the nearest
        // ancestor form.
        const form = this.el.tagName === "FORM" ? this.el : this.el.closest("form")
        if (form && !this.submitButton?.disabled) form.requestSubmit()
      }
    }
    this._onClick = event => {
      if (!event.target.closest("button") && this.textarea) this.textarea.focus()
    }
    this._onFocusIn = () => {
      if (this.el.dataset.expandEvent) {
        this.pushEventTo(this.el, this.el.dataset.expandEvent, {})
      }
    }
    this._onCancel = () => {
      if (!this.textarea) return

      this.textarea.value = ""
      this.textarea.dispatchEvent(new Event("input", {bubbles: true}))
      this.textarea.blur()
      this._sync()
    }

    this.el.addEventListener("click", this._onClick)
    this.el.addEventListener("focusin", this._onFocusIn)
    this.el.addEventListener("kaguya:reply-input-cancel", this._onCancel)

    // Server-driven content swap. The LiveView pushes this with the form's
    // id after create_comment / update_comment etc. — empty content clears
    // the textarea (success path), non-empty restores it (failure path).
    this.handleEvent("kaguya:markdown-editor-set", payload => {
      if (!payload || payload.id !== this.el.id || !this.textarea) return
      const next = typeof payload.content === "string" ? payload.content : ""
      this.textarea.value = next
      this.textarea.dispatchEvent(new Event("input", {bubbles: true}))
      this._sync()
      if (next.length > 0) this.textarea.focus()
    })

    this._bindTextarea()
    this._sync()
    this._restoreDraft()
  },

  updated() {
    this.submitButton =
      this.el.querySelector("[data-markdown-editor-submit]") ||
      this.el.querySelector("[data-reply-submit]")
    this._bindTextarea()
    this._sync()
  },

  destroyed() {
    // Flush any pending debounced save so the last keystrokes before a dismiss
    // aren't lost in the timer window.
    if (this._draftTimer) {
      clearTimeout(this._draftTimer)
      this._saveDraft()
    }
    this._unbindTextarea()
    this.el.removeEventListener("click", this._onClick)
    this.el.removeEventListener("focusin", this._onFocusIn)
    this.el.removeEventListener("kaguya:reply-input-cancel", this._onCancel)
  },

  _bindTextarea() {
    // First textarea in the form — composers may name it `content`, `body`,
    // `note`, etc., so we don't pin to a specific name attribute.
    const nextTextarea = this.el.querySelector("textarea")
    if (nextTextarea === this.textarea) {
      this._adjustHeight()
      return
    }

    this._unbindTextarea()
    this.textarea = nextTextarea
    this.textarea?.addEventListener("input", this._onInput)
    this.textarea?.addEventListener("keydown", this._onKeyDown)
    this._adjustHeight()
  },

  _unbindTextarea() {
    this.textarea?.removeEventListener("input", this._onInput)
    this.textarea?.removeEventListener("keydown", this._onKeyDown)
  },

  _sync() {
    if (!this.textarea) return
    // The submit button only lives inside the editor when the hook owns the
    // form (comment composer). When attached to a nested element (review
    // dialog), the parent form owns Save and we just keep the textarea
    // height in sync.
    if (this.submitButton) {
      this.submitButton.disabled = this.textarea.value.trim().length === 0
    }
    this._adjustHeight()
  },

  _adjustHeight() {
    if (!this.textarea) return

    this.textarea.style.height = "auto"
    const nextHeight = this.textarea.scrollHeight
    if (nextHeight === 0) return

    const maxHeight = parseFloat(getComputedStyle(this.textarea).maxHeight)
    if (Number.isFinite(maxHeight) && maxHeight > 0 && nextHeight > maxHeight) {
      this.textarea.style.height = `${maxHeight}px`
    } else {
      this.textarea.style.height = `${nextHeight}px`
    }
  },

  _restoreDraft() {
    if (!this.draftKey || !this.textarea) return

    let saved
    try {
      saved = window.localStorage.getItem(this.draftKey)
    } catch (_error) {
      return
    }

    // Restore only a non-empty draft that actually differs from what's already
    // shown. The equality guard makes this self-healing: after a successful
    // save the persisted review content equals the draft, so reopening to edit
    // shows the saved text and never resurrects a stale copy. (Explicit Discard
    // / Delete clear the key outright via the DraftClear hook.)
    if (saved == null || saved.trim().length === 0) return
    if (saved === this.textarea.value) return

    this.textarea.value = saved
    // Bubbles to the form so LiveView's phx-change refreshes the server-side
    // form, dirty flag, and min-length state to match the restored text.
    this.textarea.dispatchEvent(new Event("input", {bubbles: true}))
    this.textarea.selectionStart = this.textarea.selectionEnd = saved.length
  },

  _scheduleDraftSave() {
    if (!this.draftKey) return
    clearTimeout(this._draftTimer)
    this._draftTimer = setTimeout(() => this._saveDraft(), 400)
  },

  _saveDraft() {
    if (!this.draftKey || !this.textarea) return
    try {
      const value = this.textarea.value
      if (value.length === 0) {
        window.localStorage.removeItem(this.draftKey)
      } else {
        window.localStorage.setItem(this.draftKey, value)
      }
    } catch (_error) {
      // Storage full or disabled — drafting degrades to the prior behavior.
    }
  },

  _wrapSelection(before, after, placeholder) {
    if (!this.textarea) return

    const start = this.textarea.selectionStart
    const end = this.textarea.selectionEnd
    const selectedText = this.textarea.value.substring(start, end)
    const inner = selectedText || placeholder
    const replacement = `${before}${inner}${after}`

    this.textarea.setRangeText(replacement, start, end, "select")
    this.textarea.selectionStart = start + before.length
    this.textarea.selectionEnd = start + before.length + inner.length
    this.textarea.dispatchEvent(new Event("input", {bubbles: true}))
    this.textarea.focus()
    this._sync()
  },

  _insertLink() {
    if (!this.textarea) return

    const start = this.textarea.selectionStart
    const end = this.textarea.selectionEnd
    const selectedText = this.textarea.value.substring(start, end)
    const label = selectedText || "link text"
    const replacement = `[${label}](url)`

    this.textarea.setRangeText(replacement, start, end, "select")
    this.textarea.selectionStart = start + label.length + 3
    this.textarea.selectionEnd = this.textarea.selectionStart + 3
    this.textarea.dispatchEvent(new Event("input", {bubbles: true}))
    this.textarea.focus()
    this._sync()
  }
}

export default MarkdownEditor
