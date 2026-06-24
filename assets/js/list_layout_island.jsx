import React from "react"
import {createRoot} from "react-dom/client"
import {CSS} from "@dnd-kit/utilities"
import {
  closestCenter,
  closestCorners,
  DndContext,
  DragOverlay,
  pointerWithin,
  PointerSensor,
  rectIntersection,
  TouchSensor,
  useDroppable,
  useSensor,
  useSensors
} from "@dnd-kit/core"
import {
  arrayMove,
  rectSortingStrategy,
  SortableContext,
  useSortable
} from "@dnd-kit/sortable"
import {restrictToParentElement} from "@dnd-kit/modifiers"

const isTouchDevice = typeof window !== "undefined" && "ontouchstart" in window
const CONTAINER_PREFIX = "tier-container:"
const ITEM_DROP_PREFIX = "tier-item-drop:"

const DEFAULT_TIERS = [
  {id: "tier-s", label: "S", color: "#f87171", position: 1},
  {id: "tier-a", label: "A", color: "#fb923c", position: 2},
  {id: "tier-b", label: "B", color: "#facc15", position: 3},
  {id: "tier-c", label: "C", color: "#4ade80", position: 4},
  {id: "tier-d", label: "D", color: "#60a5fa", position: 5}
]

const cx = (...classes) => classes.filter(Boolean).join(" ")
const toArray = value => (Array.isArray(value) ? value : [])
const asString = value => (value === null || value === undefined ? null : String(value))
const booleanValue = value => value === true || value === "true" || value === 1 || value === "1"

const unique = ids => {
  const seen = new Set()
  return ids.filter(id => {
    if (!id || seen.has(id)) return false
    seen.add(id)
    return true
  })
}

const normalizedMode = value => (value === "tier" ? "tier" : "grid")

const field = (source, ...names) => {
  for (const name of names) {
    if (source && source[name] !== undefined) return source[name]
  }

  return undefined
}

const itemId = item =>
  asString(
    field(item, "visual_novel_id", "visualNovelId", "id") ||
      field(item?.visual_novel, "id") ||
      field(item?.visualNovel, "id") ||
      field(item?.vn, "id")
  )

const itemPayload = item => item?.visual_novel || item?.visualNovel || item?.vn || item || {}

const itemPosition = item => Number(field(item, "position", "rank")) || Number.MAX_SAFE_INTEGER

const tierPosition = item =>
  Number(field(item, "tier_position", "tierPosition")) || Number.MAX_SAFE_INTEGER

const normalizeTiers = tiers => {
  const source = toArray(tiers).length ? toArray(tiers) : DEFAULT_TIERS

  return source
    .map((tier, index) => ({
      id: asString(tier.id) || `tier-${index + 1}`,
      label: String(tier.label || tier.name || DEFAULT_TIERS[index]?.label || index + 1),
      color: /^#[0-9a-fA-F]{6}$/.test(tier.color || "") ? tier.color : DEFAULT_TIERS[index]?.color || "#64748b",
      position: Number(tier.position) || index + 1
    }))
    .sort((a, b) => a.position - b.position)
    .map((tier, index) => ({...tier, position: index + 1}))
}

const normalizeItem = item => {
  const payload = itemPayload(item)
  const id = itemId(item)
  if (!id) return null

  return {
    ...payload,
    ...item,
    id,
    visual_novel_id: id,
    title: field(payload, "title", "name") || field(item, "title", "name") || "",
    slug: field(payload, "slug") || field(item, "slug") || null,
    images: field(payload, "images") || field(item, "images") || null,
    imageUrl:
      field(payload, "imageUrl", "image_url", "coverUrl", "cover_url") ||
      field(item, "imageUrl", "image_url", "coverUrl", "cover_url") ||
      null,
    tier_id: asString(field(item, "tier_id", "tierId")),
    tier_position: field(item, "tier_position", "tierPosition") ?? null,
    position: Number(field(item, "position", "rank")) || null
  }
}

const normalizeExplicitIdMap = (value, validIds) => {
  const valid = new Set(validIds)

  return Object.fromEntries(
    Object.entries(value || {}).map(([tierId, ids]) => [
      tierId,
      unique(toArray(ids).map(asString).filter(id => valid.has(id)))
    ])
  )
}

const flattenTierIds = (tiers, tierItemIds, unrankedItemIds) => [
  ...tiers.flatMap(tier => tierItemIds[tier.id] || []),
  ...unrankedItemIds
]

const normalizeLayout = rawLayout => {
  const raw = rawLayout || {}
  const displayMode = normalizedMode(field(raw, "display_mode", "displayMode", "mode"))
  const isRanked = booleanValue(field(raw, "is_ranked", "isRanked"))
  const items = toArray(field(raw, "items", "vns", "visual_novels", "visualNovels"))
    .map(normalizeItem)
    .filter(Boolean)
    .sort((a, b) => itemPosition(a) - itemPosition(b))

  const itemsById = Object.fromEntries(items.map(item => [item.id, item]))
  const allItemIds = unique(items.map(item => item.id))
  const tiers = normalizeTiers(field(raw, "tiers"))
  const validIds = new Set(allItemIds)

  let tierItemIds = normalizeExplicitIdMap(field(raw, "tier_item_ids", "tierItemIds"), allItemIds)
  let unrankedItemIds = unique(
    toArray(field(raw, "unranked_item_ids", "unrankedItemIds"))
      .map(asString)
      .filter(id => validIds.has(id))
  )

  const hasExplicitTierState =
    Object.values(tierItemIds).some(ids => ids.length > 0) || unrankedItemIds.length > 0

  if (!hasExplicitTierState) {
    tierItemIds = Object.fromEntries(tiers.map(tier => [tier.id, []]))

    const tierIds = new Set(tiers.map(tier => tier.id))
    const grouped = new Map()

    for (const item of items) {
      if (item.tier_id && tierIds.has(item.tier_id)) {
        if (!grouped.has(item.tier_id)) grouped.set(item.tier_id, [])
        grouped.get(item.tier_id).push(item)
      } else {
        unrankedItemIds.push(item.id)
      }
    }

    for (const tier of tiers) {
      tierItemIds[tier.id] = toArray(grouped.get(tier.id))
        .sort((a, b) => tierPosition(a) - tierPosition(b))
        .map(item => item.id)
    }
  }

  const assigned = new Set([...Object.values(tierItemIds).flat(), ...unrankedItemIds])
  const rawItemIds = unique(
    toArray(field(raw, "item_ids", "itemIds"))
      .map(asString)
      .filter(id => validIds.has(id))
  )
  const itemIds = rawItemIds.length ? rawItemIds : allItemIds
  const missing = itemIds.filter(id => !assigned.has(id))
  unrankedItemIds = unique([...unrankedItemIds, ...missing])

  for (const tier of tiers) {
    tierItemIds[tier.id] = unique(toArray(tierItemIds[tier.id]).filter(id => validIds.has(id)))
  }

  return {displayMode, isRanked, itemsById, itemIds, tiers, tierItemIds, unrankedItemIds}
}

const serverLayout = layout => {
  const placement = new Map()

  for (const tier of layout.tiers) {
    ;(layout.tierItemIds[tier.id] || []).forEach((id, index) => {
      placement.set(id, {tier_id: tier.id, tier_position: index + 1})
    })
  }

  layout.unrankedItemIds.forEach(id => {
    placement.set(id, {tier_id: null, tier_position: null})
  })

  const orderedIds =
    layout.displayMode === "tier"
      ? flattenTierIds(layout.tiers, layout.tierItemIds, layout.unrankedItemIds)
      : layout.itemIds

  return {
    display_mode: layout.displayMode,
    is_ranked: layout.isRanked,
    items: orderedIds
      .filter(id => layout.itemsById[id])
      .map((id, index) => ({
        visual_novel_id: id,
        position: index + 1,
        tier_id: placement.get(id)?.tier_id ?? null,
        tier_position: placement.get(id)?.tier_position ?? null
      })),
    tiers: layout.tiers.map((tier, index) => ({
      id: tier.id,
      label: tier.label,
      color: tier.color,
      position: index + 1
    }))
  }
}

const ensureTierState = layout => {
  const assigned = new Set([
    ...Object.values(layout.tierItemIds).flat(),
    ...layout.unrankedItemIds
  ])
  const missing = layout.itemIds.filter(id => !assigned.has(id))

  return {
    ...layout,
    tierItemIds: Object.fromEntries(
      layout.tiers.map(tier => [tier.id, layout.tierItemIds[tier.id] || []])
    ),
    unrankedItemIds: unique([...layout.unrankedItemIds, ...missing])
  }
}

const replaceTiers = (layout, tiers) => {
  const nextTiers = normalizeTiers(tiers)
  const nextTierIds = new Set(nextTiers.map(tier => tier.id))
  const tierItemIds = Object.fromEntries(nextTiers.map(tier => [tier.id, []]))
  let unrankedItemIds = [...layout.unrankedItemIds]

  for (const [tierId, itemIds] of Object.entries(layout.tierItemIds)) {
    if (nextTierIds.has(tierId)) {
      tierItemIds[tierId] = unique(itemIds)
    } else {
      unrankedItemIds = [...unrankedItemIds, ...itemIds]
    }
  }

  const next = ensureTierState({
    ...layout,
    tiers: nextTiers,
    tierItemIds,
    unrankedItemIds: unique(unrankedItemIds)
  })

  return {
    ...next,
    itemIds:
      next.displayMode === "tier"
        ? flattenTierIds(next.tiers, next.tierItemIds, next.unrankedItemIds)
        : next.itemIds
  }
}

const addItem = (layout, item) => {
  const normalized = normalizeItem(item)
  if (!normalized || layout.itemsById[normalized.id]) return layout

  const itemIds = [...layout.itemIds, normalized.id]
  const next = {
    ...layout,
    itemIds,
    itemsById: {
      ...layout.itemsById,
      [normalized.id]: {...normalized, position: itemIds.length}
    }
  }

  return next.displayMode === "tier"
    ? {...next, unrankedItemIds: [...next.unrankedItemIds, normalized.id]}
    : next
}

const removeItem = (layout, id) => {
  if (!layout.itemsById[id]) return layout

  const itemsById = {...layout.itemsById}
  delete itemsById[id]

  return {
    ...layout,
    itemsById,
    itemIds: layout.itemIds.filter(itemId => itemId !== id),
    tierItemIds: Object.fromEntries(
      Object.entries(layout.tierItemIds).map(([tierId, ids]) => [
        tierId,
        ids.filter(itemId => itemId !== id)
      ])
    ),
    unrankedItemIds: layout.unrankedItemIds.filter(itemId => itemId !== id)
  }
}

const moveGridItem = (layout, activeId, overId) => {
  const from = layout.itemIds.indexOf(activeId)
  const to = layout.itemIds.indexOf(overId)
  if (from < 0 || to < 0 || from === to) return layout
  return {...layout, itemIds: arrayMove(layout.itemIds, from, to)}
}

const containerDropId = containerId => `${CONTAINER_PREFIX}${containerId}`
const itemDropId = (id, edge) => `${ITEM_DROP_PREFIX}${id}:${edge}`
const isPreciseDropId = id => String(id).startsWith(ITEM_DROP_PREFIX)

const preciseCollisionDetection = args => {
  const droppableContainers = args.droppableContainers.filter(container => container.id !== args.active.id)
  const collisionArgs = {...args, droppableContainers}

  if (isTouchDevice) {
    // TierMaker-style: which row is the finger over, then which item in that row.
    // closestCorners over everything was finicky — items in adjacent rows would
    // win on corner-distance even when the finger was clearly inside another row.
    const containers = droppableContainers.filter(c => String(c.id).startsWith(CONTAINER_PREFIX))
    const containerHits = pointerWithin({...collisionArgs, droppableContainers: containers})
    if (containerHits.length === 0) return closestCorners(collisionArgs)

    const targetContainerId = String(containerHits[0].id).slice(CONTAINER_PREFIX.length)
    const itemsInContainer = droppableContainers.filter(
      c => c.data?.current?.containerId === targetContainerId
    )
    if (itemsInContainer.length === 0) return containerHits

    const itemHits = closestCenter({...collisionArgs, droppableContainers: itemsInContainer})
    return itemHits.length > 0 ? itemHits : containerHits
  }

  const pointerCollisions = pointerWithin(collisionArgs)
  const collisions = pointerCollisions.length > 0 ? pointerCollisions : rectIntersection(collisionArgs)
  const precise = collisions.filter(collision => isPreciseDropId(collision.id))

  return precise.length > 0 ? precise : collisions
}

const findTierContainer = (layout, id) => {
  if (id === "unranked") return "unranked"
  if (layout.tiers.some(tier => tier.id === id)) return id
  if (layout.unrankedItemIds.includes(id)) return "unranked"
  return layout.tiers.find(tier => (layout.tierItemIds[tier.id] || []).includes(id))?.id || null
}

const parseDropTarget = (layout, overId) => {
  const id = String(overId)

  if (id.startsWith(CONTAINER_PREFIX)) {
    const containerId = id.slice(CONTAINER_PREFIX.length)
    if (containerId === "unranked" || layout.tiers.some(tier => tier.id === containerId)) {
      return {containerId, itemId: null, edge: "end"}
    }
  }

  if (id.startsWith(ITEM_DROP_PREFIX)) {
    const payload = id.slice(ITEM_DROP_PREFIX.length)
    const splitAt = payload.lastIndexOf(":")
    const itemId = payload.slice(0, splitAt)
    const edge = payload.slice(splitAt + 1)
    const containerId = findTierContainer(layout, itemId)

    if (containerId && (edge === "before" || edge === "after")) {
      return {containerId, itemId, edge}
    }
  }

  const containerId = findTierContainer(layout, id)
  return containerId ? {containerId, itemId: id, edge: "before"} : null
}

const moveTierItem = (layout, activeId, overId) => {
  const from = findTierContainer(layout, activeId)
  const target = parseDropTarget(layout, overId)
  if (!from || !target) return layout

  const idsFor = containerId =>
    containerId === "unranked"
      ? layout.unrankedItemIds
      : layout.tierItemIds[containerId] || []

  const fromIds = idsFor(from)
  const toIds = idsFor(target.containerId)
  const activeIndex = fromIds.indexOf(activeId)
  if (activeIndex < 0) return layout

  let nextFrom = fromIds.filter(id => id !== activeId)
  let nextTo = from === target.containerId ? nextFrom : toIds.filter(id => id !== activeId)
  let insertIndex = nextTo.length

  if (target.itemId) {
    const targetIndex = nextTo.indexOf(target.itemId)
    if (targetIndex < 0) return layout
    insertIndex = target.edge === "after" ? targetIndex + 1 : targetIndex
  }

  nextTo = [...nextTo.slice(0, insertIndex), activeId, ...nextTo.slice(insertIndex)]
  if (from === target.containerId) nextFrom = nextTo

  const tierItemIds = {...layout.tierItemIds}
  let unrankedItemIds = layout.unrankedItemIds

  if (from === "unranked") unrankedItemIds = nextFrom
  else tierItemIds[from] = nextFrom

  if (target.containerId === "unranked") unrankedItemIds = nextTo
  else tierItemIds[target.containerId] = nextTo

  return {
    ...layout,
    tierItemIds,
    unrankedItemIds,
    itemIds: flattenTierIds(layout.tiers, tierItemIds, unrankedItemIds)
  }
}

const imageData = item => {
  const images = item?.images || {}
  const small = images.small || item?.imageUrl || item?.image_url || null
  const medium = images.medium || item?.imageUrl || item?.image_url || small
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

const hexToRgba = (hex, alpha) => {
  if (!/^#[0-9a-fA-F]{6}$/.test(hex || "")) return `rgba(100, 116, 139, ${alpha})`

  const value = parseInt(hex.slice(1), 16)
  const r = (value >> 16) & 255
  const g = (value >> 8) & 255
  const b = value & 255
  return `rgba(${r}, ${g}, ${b}, ${alpha})`
}

const coverSensitive = item =>
  item?.is_image_nsfw === true ||
  item?.isImageNsfw === true ||
  item?.is_image_suggestive === true ||
  item?.isImageSuggestive === true

const Cover = ({item, className, blurSize = 140}) => {
  const {src, srcSet} = imageData(item)
  const title = item?.title || "Untitled"

  if (!src) {
    return (
      <div
        className={cx(
          "bg-surface-elevated text-foreground-tertiary flex h-full w-full items-center justify-center rounded-[4px] px-1 text-center text-[10px] font-medium leading-tight",
          className
        )}
        title={title}
      >
        {title}
      </div>
    )
  }

  const nsfw = coverSensitive(item)

  return (
    <img
      alt={title}
      className={className}
      data-nsfw-blur={nsfw ? "1" : undefined}
      draggable={false}
      loading="lazy"
      sizes="96px"
      src={src}
      srcSet={srcSet || undefined}
      style={nsfw ? {"--nsfw-blur-size": String(blurSize)} : undefined}
    />
  )
}

const RemoveButton = ({onClick}) => (
  <button
    type="button"
    aria-label="Remove"
    className="absolute top-1 right-1 flex size-5 items-center justify-center rounded-full bg-black/60 text-xs font-semibold text-white opacity-0 transition-opacity group-hover:opacity-100 max-lg:opacity-100 max-sm:top-0.5 max-sm:right-0.5 max-sm:size-4"
    onClick={event => {
      event.stopPropagation()
      onClick()
    }}
  >
    <svg
      aria-hidden="true"
      className="size-3.5 max-sm:size-3"
      fill="none"
      stroke="currentColor"
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeWidth="2"
      viewBox="0 0 24 24"
    >
      <path d="M18 6 6 18" />
      <path d="m6 6 12 12" />
    </svg>
  </button>
)

const ListLayoutApp = React.forwardRef(({initialLayout, emitInitial, onChange, onReady}, ref) => {
  const [layout, setLayout] = React.useState(() => normalizeLayout(initialLayout))
  const mounted = React.useRef(false)

  React.useImperativeHandle(
    ref,
    () => ({
      addItem: item => setLayout(current => addItem(current, item)),
      setMode: mode =>
        setLayout(current => ensureTierState({...current, displayMode: normalizedMode(mode)})),
      setRanked: value => setLayout(current => ({...current, isRanked: booleanValue(value)})),
      setTiers: tiers => setLayout(current => replaceTiers(current, tiers)),
      setLayout: nextLayout => setLayout(normalizeLayout(nextLayout))
    }),
    []
  )

  React.useEffect(() => {
    onReady()
  }, [onReady])

  React.useEffect(() => {
    if (!mounted.current) {
      mounted.current = true
      if (!emitInitial) return
    }

    onChange(serverLayout(layout))
  }, [emitInitial, layout, onChange])

  const update = React.useCallback(updater => setLayout(current => updater(current)), [])

  return (
    <div className="list-layout-island">
      {layout.displayMode === "tier" ? (
        <TierBoard layout={layout} update={update} />
      ) : (
        <GridBoard layout={layout} update={update} />
      )}
    </div>
  )
})

ListLayoutApp.displayName = "ListLayoutApp"

const GridBoard = ({layout, update}) => {
  const [activeId, setActiveId] = React.useState(null)
  const touchSensor = useSensor(TouchSensor, {activationConstraint: {delay: 100, tolerance: 5}})
  const pointerSensor = useSensor(PointerSensor, {activationConstraint: {distance: 5}})
  const sensors = useSensors(touchSensor, ...(isTouchDevice ? [] : [pointerSensor]))

  return (
    <DndContext
      collisionDetection={closestCorners}
      modifiers={[restrictToParentElement]}
      sensors={sensors}
      onDragStart={({active}) => setActiveId(String(active.id))}
      onDragCancel={() => setActiveId(null)}
      onDragEnd={({active, over}) => {
        setActiveId(null)
        if (!active || !over || active.id === over.id) return
        update(current => moveGridItem(current, String(active.id), String(over.id)))
      }}
    >
      <SortableContext items={layout.itemIds} strategy={rectSortingStrategy}>
        <div
          className={cx(
            "text-foreground-primary grid h-full grid-cols-4 gap-x-[5px] gap-y-[5px] max-md:mt-5 sm:grid-cols-5 md:grid-cols-6 md:gap-x-2 md:gap-y-2 md:max-lg:mt-6 lg:grid-cols-6 lg:pt-5",
            layout.isRanked && "gap-y-1"
          )}
        >
          {layout.itemIds.map((id, index) => (
            <GridItem
              key={id}
              item={layout.itemsById[id]}
              rank={index + 1}
              isRanked={layout.isRanked}
              onRemove={() => update(current => removeItem(current, id))}
            />
          ))}
        </div>
      </SortableContext>
      <DragOverlay modifiers={[restrictToParentElement]}>
        {activeId ? (
          <GridItem
            dragOverlay
            item={layout.itemsById[activeId]}
            rank={layout.itemIds.indexOf(activeId) + 1}
            isRanked={layout.isRanked}
            onRemove={() => {}}
          />
        ) : null}
      </DragOverlay>
    </DndContext>
  )
}

const GridItem = ({item, rank, isRanked, onRemove, dragOverlay = false}) => {
  const {attributes, listeners, isDragging, setNodeRef, transform, transition} = useSortable({
    id: item.id
  })

  const style = {
    transition,
    transform: CSS.Transform.toString(transform),
    visibility: isDragging && !dragOverlay ? "hidden" : undefined
  }

  return (
    <div
      className="relative cursor-grab active:cursor-grabbing"
      ref={setNodeRef}
      style={style}
      {...attributes}
      {...listeners}
    >
      <div className="touch-pan-y select-none [-webkit-touch-callout:none]">
        <div className="group relative aspect-[1/1.5] overflow-hidden">
          <Cover item={item} className="h-full w-full rounded-[2px] object-cover object-center" />
          {!dragOverlay && <RemoveButton onClick={onRemove} />}
        </div>
        {isRanked && rank ? (
          <p className="text-foreground-primary mt-1.5 text-center text-[11px] font-medium lg:text-sm">
            {rank}
          </p>
        ) : null}
      </div>
    </div>
  )
}

const TierBoard = ({layout, update}) => {
  const [activeId, setActiveId] = React.useState(null)
  const touchSensor = useSensor(TouchSensor, {activationConstraint: {delay: 100, tolerance: 5}})
  const pointerSensor = useSensor(PointerSensor, {activationConstraint: {distance: 5}})
  const sensors = useSensors(touchSensor, ...(isTouchDevice ? [] : [pointerSensor]))

  return (
    <div className="mt-4 space-y-3 lg:mt-6">
      <DndContext
        collisionDetection={preciseCollisionDetection}
        sensors={sensors}
        onDragStart={({active}) => setActiveId(String(active.id))}
        onDragCancel={() => setActiveId(null)}
        onDragEnd={({active, over}) => {
          setActiveId(null)
          if (!active || !over || active.id === over.id) return
          update(current => moveTierItem(current, String(active.id), String(over.id)))
        }}
      >
        <div className="border-border-divider overflow-hidden rounded-[8px] border">
          {layout.tiers.map(tier => (
            <TierRow
              key={tier.id}
              tier={tier}
              itemIds={layout.tierItemIds[tier.id] || []}
              itemsById={layout.itemsById}
              onRemove={id => update(current => removeItem(current, id))}
            />
          ))}
        </div>
        <UnrankedPool
          itemIds={layout.unrankedItemIds}
          itemsById={layout.itemsById}
          onRemove={id => update(current => removeItem(current, id))}
        />
        <DragOverlay>
          {activeId ? (
            <TierCover dragOverlay item={layout.itemsById[activeId]} onRemove={() => {}} />
          ) : null}
        </DragOverlay>
      </DndContext>
    </div>
  )
}

const tierHeaderStyle = color => ({
  background: `linear-gradient(135deg, ${hexToRgba(color, 0.58)}, ${hexToRgba(color, 0.36)})`,
  boxShadow: "inset 0 1px 0 rgba(255, 255, 255, 0.1)"
})

const TierRow = ({tier, itemIds, itemsById, onRemove}) => {
  const {setNodeRef, isOver} = useDroppable({id: containerDropId(tier.id)})

  return (
    <div className="border-border-divider grid min-h-[112px] grid-cols-[104px_1fr] border-b last:border-b-0 max-sm:min-h-[64px] max-sm:grid-cols-[56px_1fr]">
      <div
        className="flex items-center justify-center border-r border-white/[0.06] text-base font-bold text-white/95 max-sm:text-[11px]"
        style={tierHeaderStyle(tier.color)}
      >
        <span className="line-clamp-2 break-words px-2 text-center max-sm:px-1">{tier.label}</span>
      </div>
      <SortableContext items={itemIds}>
        <div
          ref={setNodeRef}
          className={cx(
            "flex min-h-[112px] flex-wrap content-start gap-2 p-2 transition-colors max-sm:min-h-[56px] max-sm:gap-1 max-sm:p-1",
            isOver && "bg-white/[0.04]"
          )}
        >
          {itemIds.map(id => (
            <TierCover
              key={id}
              item={itemsById[id]}
              containerId={tier.id}
              onRemove={() => onRemove(id)}
            />
          ))}
        </div>
      </SortableContext>
    </div>
  )
}

const UnrankedPool = ({itemIds, itemsById, onRemove}) => {
  const {setNodeRef, isOver} = useDroppable({id: containerDropId("unranked")})

  return (
    <section className="mt-5">
      <div className="text-foreground-secondary mb-2 flex items-center gap-2 text-sm font-semibold max-sm:mb-1.5 max-sm:text-xs">
        <span>Unranked</span>
        <span className="bg-surface-elevated rounded-full px-2 py-0.5 text-xs font-normal">
          {itemIds.length}
        </span>
      </div>
      <SortableContext items={itemIds}>
        <div
          ref={setNodeRef}
          className={cx(
            "border-border-divider bg-surface-elevated/40 flex min-h-[118px] flex-wrap content-start gap-2 rounded-[8px] border border-dashed p-2 transition-colors max-sm:min-h-[64px] max-sm:gap-1 max-sm:p-1",
            isOver && "bg-white/[0.05]"
          )}
        >
          {itemIds.length === 0 ? (
            <div className="text-foreground-tertiary flex flex-1 items-center justify-center text-xs italic max-sm:text-[10px]">
              All items have been ranked
            </div>
          ) : null}
          {itemIds.map(id => (
            <TierCover
              key={id}
              item={itemsById[id]}
              containerId="unranked"
              onRemove={() => onRemove(id)}
            />
          ))}
        </div>
      </SortableContext>
    </section>
  )
}

const TierCover = ({item, containerId, onRemove, dragOverlay = false}) => {
  const {attributes, listeners, isDragging, setNodeRef, transform, transition} = useSortable({
    id: item.id,
    data: {containerId}
  })

  const style = {
    transition,
    transform: CSS.Transform.toString(transform),
    visibility: isDragging && !dragOverlay ? "hidden" : undefined
  }

  return (
    <div
      ref={setNodeRef}
      style={style}
      {...attributes}
      {...listeners}
      className={cx(
        "group relative h-[104px] w-[70px] shrink-0 touch-pan-y overflow-hidden rounded-[4px] transition-transform select-none [-webkit-touch-callout:none] max-sm:h-[72px] max-sm:w-[48px]",
        "cursor-grab active:cursor-grabbing",
        dragOverlay && "scale-105 shadow-2xl"
      )}
    >
      <Cover
        item={item}
        blurSize={70}
        className="h-full w-full rounded-[4px] object-cover object-center"
      />
      {!isTouchDevice && !dragOverlay && <ItemDropZones itemId={item.id} />}
      {!dragOverlay && <RemoveButton onClick={onRemove} />}
    </div>
  )
}

const ItemDropZones = ({itemId}) => {
  const before = useDroppable({id: itemDropId(itemId, "before")})
  const after = useDroppable({id: itemDropId(itemId, "after")})

  return (
    <>
      <div
        ref={before.setNodeRef}
        aria-hidden
        className={cx(
          "pointer-events-none absolute inset-y-0 left-0 w-1/2 transition-shadow",
          before.isOver && "shadow-[inset_2px_0_0_rgba(255,255,255,0.9)]"
        )}
      />
      <div
        ref={after.setNodeRef}
        aria-hidden
        className={cx(
          "pointer-events-none absolute inset-y-0 right-0 w-1/2 transition-shadow",
          after.isOver && "shadow-[inset_-2px_0_0_rgba(255,255,255,0.9)]"
        )}
      />
    </>
  )
}

export function mountListLayoutIsland(el, opts = {}) {
  const root = createRoot(el)
  const api = React.createRef()
  const pending = []

  const call = (name, payload) => {
    if (api.current?.[name]) api.current[name](payload)
    else pending.push([name, payload])
  }

  const flush = () => {
    pending.splice(0).forEach(([name, payload]) => call(name, payload))
  }

  root.render(
    <ListLayoutApp
      ref={api}
      initialLayout={opts.layout || {}}
      emitInitial={Boolean(opts.emitInitial)}
      onChange={opts.onChange || (() => {})}
      onReady={flush}
    />
  )

  return {
    addItem: item => call("addItem", item),
    setMode: mode => call("setMode", mode),
    setRanked: value => call("setRanked", value),
    setTiers: tiers => call("setTiers", tiers),
    setLayout: layout => call("setLayout", layout),
    unmount: () => root.unmount()
  }
}
