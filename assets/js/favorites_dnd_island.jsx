/*
 * FavoritesDndIsland — React/dnd-kit island that fully owns the favorites
 * grid DOM while the user is editing favorites. Mirrors the architecture
 * of `list_layout_island.jsx`: the parent LiveView wraps the mount node
 * with `phx-update="ignore"` so React keeps control across re-renders,
 * passing fresh state in via `data-items` on each `updated()` hook tick.
 *
 * Mount signature:
 *   mountFavoritesDnd(rootEl, {
 *     kind: "visual_novels" | "characters",
 *     items: [{id, title, slug, images, image_url, ...}, ...],
 *     limit: 5,
 *     onReorder: (kind, from, to) => void,
 *     onRemove:  (kind, id) => void,
 *     onAdd:     (kind) => void
 *   }) -> { setItems({items, limit, kind}), unmount() }
 *
 * The island renders the tiles itself using dnd-kit's SortableContext +
 * verticalListSortingStrategy, with a DragOverlay for the smooth ghost.
 * Per-item remove + the add slot are rendered here too so the React tree
 * owns every interactive element inside the grid.
 */

import React from "react"
import {createRoot} from "react-dom/client"
import {
  DndContext,
  DragOverlay,
  KeyboardSensor,
  PointerSensor,
  TouchSensor,
  closestCenter,
  useSensor,
  useSensors
} from "@dnd-kit/core"
import {
  SortableContext,
  arrayMove,
  rectSortingStrategy,
  sortableKeyboardCoordinates,
  useSortable
} from "@dnd-kit/sortable"
import {CSS} from "@dnd-kit/utilities"

const cx = (...classes) => classes.filter(Boolean).join(" ")

const isTouchDevice = typeof window !== "undefined" && "ontouchstart" in window

const asId = value => (value === null || value === undefined ? null : String(value))

const titleOf = item => item?.title || item?.name || ""

const imageData = item => {
  const images = item?.images || {}
  const small = images.small || item?.imageUrl || item?.image_url || null
  const medium = images.medium || small
  const large = images.large || images.xl || medium || small
  const src = medium || large || small || ""
  const srcSet = [
    small ? `${small} 128w` : null,
    medium ? `${medium} 256w` : null,
    large ? `${large} 512w` : null
  ]
    .filter(Boolean)
    .join(", ")

  return {src, srcSet}
}

const normalizeItems = items =>
  (Array.isArray(items) ? items : [])
    .map(item => {
      const id = asId(item?.id)
      if (!id) return null
      return {...item, id}
    })
    .filter(Boolean)

const Cover = ({item, kind}) => {
  const {src, srcSet} = imageData(item)
  const title = titleOf(item)

  if (!src) {
    return (
      <div
        className={cx(
          "bg-[rgb(var(--surface-elevated))] flex h-full w-full items-center justify-center px-1 text-center text-[10px] font-medium text-[rgb(var(--foreground-tertiary))]",
          kind === "characters" ? "aspect-square rounded-[4px]" : "aspect-[2/3] rounded-[4px]"
        )}
        title={title}
      >
        {title}
      </div>
    )
  }

  return (
    <img
      alt={title}
      title={title}
      className={cx(
        "block h-full w-full select-none object-cover rounded-[4px]",
        kind === "characters" ? "aspect-square object-top" : "aspect-[2/3] object-center"
      )}
      draggable={false}
      loading="lazy"
      decoding="async"
      sizes="(max-width: 640px) 90px, 170px"
      src={src}
      srcSet={srcSet || undefined}
    />
  )
}

const XIcon = () => (
  <svg viewBox="0 0 10 10" fill="none" className="size-2.5" aria-hidden="true">
    <path d="M2 2l6 6M8 2l-6 6" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
  </svg>
)

const PlusIcon = () => (
  <svg
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth="1.5"
    strokeLinecap="round"
    className="size-6"
    aria-hidden="true"
  >
    <path d="M12 5v14" />
    <path d="M5 12h14" />
  </svg>
)

const SortableTile = ({item, kind, onRemove}) => {
  const {attributes, listeners, isDragging, setNodeRef, transform, transition} = useSortable({
    id: item.id
  })

  const style = {
    transition,
    transform: CSS.Transform.toString(transform),
    // Hide the source tile while the DragOverlay renders the moving ghost.
    opacity: isDragging ? 0 : 1
  }

  return (
    <div
      ref={setNodeRef}
      style={style}
      className="group/fav relative cursor-grab touch-none select-none active:cursor-grabbing [-webkit-touch-callout:none]"
      {...attributes}
      {...listeners}
    >
      <div className="relative">
        <Cover item={item} kind={kind} />
      </div>

      <button
        type="button"
        aria-label={`Remove ${titleOf(item) || "favorite"}`}
        onPointerDown={event => event.stopPropagation()}
        onClick={event => {
          event.stopPropagation()
          onRemove(item.id)
        }}
        className="absolute -top-1.5 -right-1.5 z-10 flex size-5 items-center justify-center rounded-full bg-black/70 text-white opacity-100 backdrop-blur-xs transition-opacity sm:opacity-0 sm:group-hover/fav:opacity-100 sm:focus-visible:opacity-100"
      >
        <XIcon />
      </button>
    </div>
  )
}

const OverlayTile = ({item, kind}) => (
  <div className="relative scale-105 shadow-2xl">
    <Cover item={item} kind={kind} />
  </div>
)

const AddSlot = ({kind, onAdd}) => (
  <button
    type="button"
    onClick={() => onAdd(kind)}
    className={cx(
      "group flex items-center justify-center rounded-[4px] border border-dashed border-[rgb(var(--border-divider))] text-[rgb(var(--border-divider))] transition-colors hover:border-[rgb(var(--border-strong-divider))] hover:text-[rgb(var(--foreground-secondary))]",
      kind === "characters" ? "aspect-square" : "aspect-[2/3]"
    )}
    aria-label="Add favorite"
  >
    <PlusIcon />
  </button>
)

const gridClass = layout =>
  layout === "edit_profile"
    ? "grid grid-cols-4 gap-1"
    : "grid grid-cols-4 gap-4 sm:grid-cols-5 sm:gap-6 lg:gap-8"

const FavoritesApp = React.forwardRef(({initialItems, initialLimit, kind, layout, onReorder, onRemove, onAdd}, ref) => {
  const [items, setItems] = React.useState(() => normalizeItems(initialItems))
  const [limit, setLimit] = React.useState(initialLimit || 5)
  const [activeId, setActiveId] = React.useState(null)

  React.useImperativeHandle(
    ref,
    () => ({
      setItems: payload => {
        if (payload?.items !== undefined) setItems(normalizeItems(payload.items))
        if (payload?.limit !== undefined) setLimit(Number(payload.limit) || 5)
      }
    }),
    []
  )

  const sensors = useSensors(
    useSensor(PointerSensor, {activationConstraint: {distance: 5}}),
    useSensor(TouchSensor, {activationConstraint: {delay: 100, tolerance: 5}}),
    useSensor(KeyboardSensor, {coordinateGetter: sortableKeyboardCoordinates})
  )

  const ids = React.useMemo(() => items.map(item => item.id), [items])
  const activeItem = activeId ? items.find(item => item.id === activeId) : null

  const handleDragEnd = ({active, over}) => {
    setActiveId(null)
    if (!over || active.id === over.id) return
    const from = ids.indexOf(String(active.id))
    const to = ids.indexOf(String(over.id))
    if (from < 0 || to < 0 || from === to) return

    // Optimistic local reorder so the drop feels instant; the server will
    // confirm by sending fresh items via setItems() on the next render.
    setItems(current => arrayMove(current, from, to))
    onReorder(kind, from, to)
  }

  return (
    <div className={gridClass(layout)}>
      <DndContext
        sensors={sensors}
        collisionDetection={closestCenter}
        onDragStart={({active}) => setActiveId(String(active.id))}
        onDragCancel={() => setActiveId(null)}
        onDragEnd={handleDragEnd}
      >
        <SortableContext items={ids} strategy={rectSortingStrategy}>
          {items.map(item => (
            <SortableTile
              key={item.id}
              item={item}
              kind={kind}
              onRemove={id => onRemove(kind, id)}
            />
          ))}
        </SortableContext>

        <DragOverlay dropAnimation={{duration: 180, easing: "cubic-bezier(0.2, 0, 0, 1)"}}>
          {activeItem ? <OverlayTile item={activeItem} kind={kind} /> : null}
        </DragOverlay>
      </DndContext>

      {items.length < limit ? <AddSlot kind={kind} onAdd={onAdd} /> : null}
    </div>
  )
})

FavoritesApp.displayName = "FavoritesApp"

export function mountFavoritesDnd(el, opts = {}) {
  const root = createRoot(el)
  const api = React.createRef()

  const noop = () => {}

  root.render(
    <FavoritesApp
      ref={api}
      kind={opts.kind || "visual_novels"}
      layout={opts.layout || "default"}
      initialItems={opts.items || []}
      initialLimit={opts.limit || 5}
      onReorder={opts.onReorder || noop}
      onRemove={opts.onRemove || noop}
      onAdd={opts.onAdd || noop}
    />
  )

  return {
    setItems: payload => api.current?.setItems?.(payload),
    unmount: () => root.unmount()
  }
}

// Touch-device detection kept for parity with the old island shape; not
// strictly required but useful if we ever need to branch on it.
export const _isTouchDevice = isTouchDevice
