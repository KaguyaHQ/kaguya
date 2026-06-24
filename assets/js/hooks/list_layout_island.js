import {parseJSONAttribute, browserImport, booleanValue} from "../lib/dom"

/*
 * ListLayoutIsland is a bounded React/dnd-kit bridge for list editing.
 *
 * LiveView renders:
 *   <div
 *     id="list-layout-island"
 *     phx-hook="ListLayoutIsland"
 *     phx-update="ignore"
 *     data-layout="{...json...}"
 *     data-island-src={~p"/assets/js/list_layout_island.js"}
 *   />
 *
 * Accepted data-layout:
 *   {
 *     display_mode: "grid" | "tier",
 *     is_ranked: boolean,
 *     items: [{ visual_novel_id, position, tier_id, tier_position, visual_novel }],
 *     tiers: [{ id, label, color, position }]
 *   }
 *
 * Server-pushed events:
 *   list_layout:add_item     item or { item }
 *   list_layout:set_mode     "grid" | "tier" or { mode/display_mode }
 *   list_layout:set_ranked   boolean or { value/is_ranked/isRanked }
 *   list_layout:set_tiers    [{ id, label, color, position }]
 *
 * Client-pushed event:
 *   layout_changed
 *     {
 *       display_mode,
 *       is_ranked,
 *       items: [{ visual_novel_id, position, tier_id, tier_position }],
 *       tiers: [{ id, label, color, position }]
 *     }
 *
 * The island owns only local drag/drop layout state. Persistence, fetching,
 * auth, routing, comments, and validation stay in LiveView/contexts.
 */
const ListLayoutIsland = {
  mounted() {
    this._isDestroyed = false
    this._islandUnavailable = false
    this._queuedCommands = []
    this._mountLayoutIsland()

    this._addItemRef = this.handleEvent("list_layout:add_item", payload => {
      this._sendIslandCommand("addItem", payload?.item || payload)
    })

    this._setModeRef = this.handleEvent("list_layout:set_mode", payload => {
      this._sendIslandCommand(
        "setMode",
        payload?.mode || payload?.display_mode || payload?.displayMode || payload
      )
    })

    this._setRankedRef = this.handleEvent("list_layout:set_ranked", payload => {
      const value =
        typeof payload === "boolean"
          ? payload
          : payload?.is_ranked ?? payload?.isRanked ?? payload?.value

      this._sendIslandCommand("setRanked", booleanValue(value))
    })

    this._setTiersRef = this.handleEvent("list_layout:set_tiers", payload => {
      this._sendIslandCommand("setTiers", payload?.tiers || payload)
    })
  },

  updated() {
    // No-op: after mount, the React island owns the live layout. Echoing the
    // server's normalized data-layout back via setLayout resets every dnd-kit
    // sortable mid-animation, making removals visibly jump. Explicit server
    // commands (list_layout:add_item / set_mode / set_ranked / set_tiers) still
    // flow through handleEvent above; data-layout is only read on initial mount.
  },

  destroyed() {
    this._isDestroyed = true
    this._queuedCommands = []

    if (this._addItemRef) this.removeHandleEvent(this._addItemRef)
    if (this._setModeRef) this.removeHandleEvent(this._setModeRef)
    if (this._setRankedRef) this.removeHandleEvent(this._setRankedRef)
    if (this._setTiersRef) this.removeHandleEvent(this._setTiersRef)

    if (this._island?.unmount) this._island.unmount()
    this._island = null
  },

  _readLayout() {
    const raw = this.el.dataset.layout || ""
    if (raw === this._lastLayoutJSON) return null
    this._lastLayoutJSON = raw
    return parseJSONAttribute(this.el, "layout", {})
  },

  _sendIslandCommand(name, payload) {
    if (this._islandUnavailable) return

    if (this._island && this._island[name]) {
      this._island[name](payload)
    } else {
      this._queuedCommands.push([name, payload])
    }
  },

  _flushQueuedCommands() {
    const commands = this._queuedCommands
    this._queuedCommands = []

    commands.forEach(([name, payload]) => this._sendIslandCommand(name, payload))
  },

  _markUnavailable(error) {
    this._islandUnavailable = true
    this._queuedCommands = []
    this.el.dataset.islandStatus = "unavailable"
    this.el.dispatchEvent(
      new CustomEvent("list-layout-island:unavailable", {
        bubbles: true,
        detail: {message: error?.message || String(error)}
      })
    )
    console.warn("[ListLayoutIsland] unavailable", error)
  },

  async _mountLayoutIsland() {
    const src = this.el.dataset.islandSrc
    const layout = this._readLayout() || {}

    try {
      if (!src) throw new Error("missing data-island-src")

      const mod = await browserImport(src)
      if (this._isDestroyed) return

      if (!mod.mountListLayoutIsland) {
        throw new Error(`${src} does not export mountListLayoutIsland`)
      }

      this.el.dataset.islandStatus = "mounted"
      this._island = mod.mountListLayoutIsland(this.el, {
        layout,
        emitInitial: this.el.dataset.emitInitial === "true",
        onChange: nextLayout => this.pushEvent("layout_changed", nextLayout)
      })
      this._flushQueuedCommands()
    } catch (error) {
      if (!this._isDestroyed) this._markUnavailable(error)
    }
  }
}

export default ListLayoutIsland
