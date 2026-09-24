# Kaguya

Visual novel discovery platform built with Phoenix, LiveView, and Tailwind v4.
Use `mix.exs` and `mise.toml` for dependency and toolchain versions, and
`config/` for environment settings; don't duplicate machine-specific setup here.

## Commands

- `mix setup` — dependencies, database setup, assets, and Git hooks
- `mix phx.server` — development server
- `mix assets.build` / `mix assets.deploy` — development / production assets
- `mix test path/to/test.exs` — focused tests; `mix test --failed` retries failures
- `mix compile --warnings-as-errors`, `mix credo`, `mix format` — code checks

Read `mix help <task>` before using an unfamiliar task. Database reset drops
local data; don't use it or `mix deps.clean --all` as routine troubleshooting.
Deployment instructions live in `deploy/`; use Conventional Commits for commits.

## Code boundaries

- `lib/kaguya/` owns queries, schemas, and business logic. LiveViews and controllers call contexts directly.
- `lib/kaguya_web/` owns browser/API surfaces, components, and policies.
- `assets/` owns CSS, JS hooks, and React islands.
- `lib/mix/tasks/` holds reusable operations; `priv/repo/scripts/` holds one-off maintenance.
- Batch queries and preload what templates need. Don't issue one query per displayed item.
- Keep server-controlled fields such as `user_id` out of changeset `cast`; set them explicitly. Check ownership in mutation handlers, not just templates.
- Use Req for new HTTP calls and `Task.async_stream/3` for bounded concurrency.
- Never convert user input with `String.to_atom/1`. Keep one module per file and use standard date/time modules.
- Return or bind transformed sockets, including results from conditionals and `push_event/3`.
- Generate migrations with `mix ecto.gen.migration`. Don't add dependencies without authorization.

## Shared UI and typography

- Check existing components before building another control. Primitives live in `lib/kaguya_web/components/ui/`; feature components live beside their feature.
- The app uses local `KaguyaWeb.UI` components, not installed SaladUI or Petal packages. Some local components retain SaladUI source attribution.
- Use `KaguyaWeb.UI.Menu` for disclosure menus/popovers and `KaguyaWeb.UI.Dialog` for dialogs. Reuse `AnchoredPopover` for positioning instead of writing another positioner. Inside menus, use `menu_item` for actions that should dismiss the panel.
- Use the shared inputs/buttons and existing `Lucide` icon alias; check `lib/kaguya_web.ex` for available imports. Custom input classes may replace defaults, so inspect the component contract.
- Use `text-style-*` utilities from `assets/css/typography.css` for UI text instead of rebuilding size, weight, and line height separately. Body 1 is 16/24px, Body 2 is 14/20px, and Caption is 12/18px; heading/display styles are defined there too. Reserve captions for supporting text, not primary values users need to read or edit.
- Reuse semantic color/surface tokens from `assets/css/generated/figma-variables.css` and `assets/css/custom-tokens.css`. Keep intentional chart palettes or visual experiments scoped to their feature.
- Preserve Tailwind v4's `@import "tailwindcss" source(none)` and the CSS, JS, and HEEx `@source` entries in `assets/css/app.css`. No `tailwind.config.js` or `@apply`.
- Import vendor assets through the existing CSS/JS bundles, not external script/stylesheet tags in layouts.

## LiveView behavior

- `use KaguyaWeb, :live_view` supplies the app layout. Follow the page's existing layout/auth setup; don't add a second app wrapper. Authentication uses `current_user`.
- Prefer function components; use LiveComponents when their own state/lifecycle is needed. Build forms with `to_form/2`, `<.form>`, and changesets or string-keyed maps.
- Give forms, interactive controls, and hook elements stable, unique DOM IDs.
- Check destinations in `lib/kaguya_web/router.ex`. Use `<.link navigate>` between LiveViews, `<.link patch>` for changes within the current LiveView, and `href` for controller/external/download links. Use `push_navigate` / `push_patch` server-side.
- In JS, use `lvNavigate` from `assets/js/lib/lv_navigate.js` for LiveView navigation. Dynamically created internal links need `data-phx-link` and `data-phx-link-state="push"`; don't replace LiveView navigation with `window.location.assign`.
- Use streams for large/incremental collections. Containers need `id` and `phx-update="stream"`; children use stream-provided IDs. Track counts/empty state separately; don't enumerate streams to count or filter them.
- Reset streams when filtering/sorting. Reinsert affected items when parent assigns change their appearance; changing an assign alone does not update consumed stream rows.
- Put hooks in `assets/js/` and register them with LiveSocket. Use `phx-update="ignore"` only where client code owns the contents; keep ordinary LiveView-patched controls reactive. Clean up listeners and observers on destruction.
- Use colocated hooks or registered hooks instead of ordinary inline scripts.

## Verification

- Run focused tests and appropriate compilation, formatting, lint, and asset checks. Report existing failures separately from regressions.
- For UI changes, check the real browser flow at desktop and narrow widths. Verify keyboard focus, Escape/outside dismissal where relevant, and behavior after LiveView patches; a successful compile is not a visual check.
- Test observable behavior with `Phoenix.LiveViewTest`, stable selectors, and `has_element?/2`; avoid raw HTML string assertions.
- Start test processes with `start_supervised!/1`. Synchronize with messages/monitors or `:sys.get_state/1`, not sleeps or liveness polling.
