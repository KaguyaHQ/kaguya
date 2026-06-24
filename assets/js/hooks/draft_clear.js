// Clears a localStorage draft on click, synchronously, before the element's
// phx-click event tears down the dialog. Used on the review "Discard" and
// "Delete" buttons — both are explicit destroy-my-work intents, so the saved
// draft (see MarkdownEditor's `data-draft-key` persistence) must not survive to
// be restored next time the editor opens.
//
// Why a click listener instead of a server push_event: the same LiveView
// response that handles the click also removes the dialog from the DOM, which
// destroys any hook inside it before a pushed event could be delivered. Running
// on the click guarantees the key is gone while the element still exists.
const DraftClear = {
  mounted() {
    this._onClick = () => {
      const key = this.el.dataset.draftKey
      if (!key) return
      try {
        window.localStorage.removeItem(key)
      } catch (_error) {
        // Private mode / storage disabled — nothing to clear.
      }
    }
    this.el.addEventListener("click", this._onClick)
  },

  destroyed() {
    this.el.removeEventListener("click", this._onClick)
  }
}

export default DraftClear
