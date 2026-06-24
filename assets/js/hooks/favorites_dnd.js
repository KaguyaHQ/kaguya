/*
 * FavoritesDnd — LiveView hook that lazy-loads the dnd-kit favorites
 * island and forwards events back to the Phoenix favorites editor.
 *
 * Mirrors the architecture of `ListLayoutIsland` in app.js: the wrapping
 * container uses `phx-update="ignore"` so the React island owns the DOM
 * entirely while editing. Phoenix passes fresh state in via a JSON
 * `data-items` attribute on each re-render; the hook detects the change
 * and pushes it into the island so the SortableContext stays in sync.
 *
 * Markup contract:
 *
 *   <div
 *     id={grid_id}
 *     phx-hook="FavoritesDnd"
 *     phx-update="ignore"
 *     data-kind="visual_novels"      // or "characters"
 *     data-items='[{...item}, ...]'  // serialized list of favorites
 *     data-limit="5"
 *     data-island-src={~p"/assets/js/favorites_dnd_island.js"}
 *   />
 *
 * Events pushed back to LiveView:
 *
 *   "reorder_favorite" — {kind, from, to}
 *   "remove_favorite"  — {type, id}
 *   "open_favorite_search" — {type}
 *
 * If the island bundle fails to load, the hook silently no-ops and the
 * server-side up/down chevron fallback (rendered outside the island
 * container) continues to work for keyboard / no-JS users.
 */

const browserImport = src => {
  // Wrap dynamic import in `new Function` so esbuild leaves it as a
  // runtime call instead of trying to bundle the URL.
  const importer = new Function("src", "return import(src)")
  return importer(src)
}

const parseJSON = (value, fallback) => {
  if (!value) return fallback
  try {
    return JSON.parse(value)
  } catch (error) {
    console.warn("[FavoritesDnd] could not parse data-items", error)
    return fallback
  }
}

const readState = el => ({
  kind: el.dataset.kind || "visual_novels",
  items: parseJSON(el.dataset.items, []),
  limit: Number(el.dataset.limit) || 5,
  layout: el.dataset.layout || "default"
})

const kindToType = kind => (kind === "characters" ? "characters" : "visual_novels")

const FavoritesDnd = {
  mounted() {
    this._destroyed = false
    this._island = null
    this._unavailable = false
    this._lastItemsJSON = this.el.dataset.items || ""
    this._mountIsland()
  },

  updated() {
    if (this._unavailable || !this._island) return

    const nextJSON = this.el.dataset.items || ""
    if (nextJSON === this._lastItemsJSON) return
    this._lastItemsJSON = nextJSON

    const {items, limit} = readState(this.el)
    this._island.setItems({items, limit})
  },

  destroyed() {
    this._destroyed = true
    if (this._island?.unmount) this._island.unmount()
    this._island = null
  },

  async _mountIsland() {
    const src = this.el.dataset.islandSrc
    const {kind, items, limit, layout} = readState(this.el)
    const type = kindToType(kind)

    try {
      if (!src) throw new Error("missing data-island-src")

      const mod = await browserImport(src)
      if (this._destroyed) return

      if (!mod.mountFavoritesDnd) {
        throw new Error(`${src} does not export mountFavoritesDnd`)
      }

      this._island = mod.mountFavoritesDnd(this.el, {
        kind,
        items,
        limit,
        layout,
        onReorder: (k, from, to) => {
          this.pushEventTo(this.el, "reorder_favorite", {kind: k, from, to})
        },
        onRemove: (_k, id) => {
          this.pushEventTo(this.el, "remove_favorite", {type, id})
        },
        onAdd: _k => {
          this.pushEventTo(this.el, "open_favorite_search", {type})
        }
      })
    } catch (error) {
      this._unavailable = true
      console.warn("[FavoritesDnd] island unavailable", error)
    }
  }
}

export default FavoritesDnd
