# Kaguya

Visual novel discovery platform: Phoenix + LiveView application with
context-driven browser surfaces and controller/API boundaries.

## Commands

- `mix setup` — install deps, create DB, run migrations, install frontend build deps
- `mix ecto.setup` — create + migrate DB
- `mix ecto.reset` — drop + recreate DB and migrate
- `mix phx.server` — start dev server on :4000
- `mix assets.setup` — install frontend build deps/tooling
- `mix assets.build` — compile Tailwind/JS assets
- `mix assets.deploy` — compile and minify production assets
- `mix test` — run all tests (creates/migrates test DB automatically)
- `mix test test/kaguya/some_test.exs` — run a single test file
- `mix test test/kaguya/some_test.exs:42` — run a specific test by line
- `mix compile --warnings-as-errors` — check for compilation warnings
- `mix credo` — static analysis / linting
- `mix format` — format Elixir source
- `OBAN_INLINE=true mix phx.server` — run Oban jobs inline for debugging

## Architecture

**Project shape:**
- `lib/kaguya/` — contexts, schemas, and business logic
- `lib/kaguya_web/` — controllers, LiveView pages, components, plugs, policies
- `assets/` — JS/CSS build assets and SaladUI-adjacent components
- `priv/repo/scripts/` — one-off maintenance, backfill, and migration scripts
- `lib/mix/tasks/` — reusable operational tasks (imports, syncs, deletes, reporting)

**Key services:**
- VNDB sync + dump sync (`lib/kaguya/sync/`) — VN data imports/reconciliation
- Supabase JWT auth (`lib/kaguya/auth/`) — JWKS verification and auth helpers
- Oban background jobs (`lib/kaguya/**/workers`) — async maintenance, imports, images, recommendations
- Cachex (`lib/kaguya/`) — hot-path caches including VN browse caches
- ExAws/S3 (R2) uploads (`lib/kaguya/uploads/`) — covers, screenshots, exports, images
- Search (`lib/kaguya/search/`) — Meilisearch indexing pipeline
- Recommendations (`lib/kaguya/recommendations/`) — Nx + EXLA inference stack
- Revisions/statistics/moderation/community entities (`lib/kaguya/revisions/`, `stats/`, `site_stats/`, `moderation/`, `social/`, `activities/`, `discussions/`)

## Tooling

- **Elixir `~> 1.20.4` / OTP 27**
- Phoenix `~> 1.8.0`, Phoenix LiveView `~> 1.1.0`
- Tailwind **v4** (no `tailwind.config.js`; uses the `@import "tailwindcss"` + `@source` syntax in `assets/css/app.css`)
- Dev DB: `kaguya_dev2` on `localhost:5432`, user `postgres`
- Deployed via Docker — `./scripts/deploy.sh` triggers a GH Actions workflow to build/push/restart. See `deploy/` for the compose stack and ops guide.
- Use the Conventional Commits 1.0.0 specification for commit messages.

## Data loading

LiveView and controller surfaces call contexts in `lib/kaguya/` directly.
Keep data loading batched at the context/query layer: preload associations that
templates access, aggregate per-parent counts in bulk, and avoid `Enum.map`
loops that issue one query per row.

## Elixir and data rules

- Use Req for new HTTP calls. Finch remains a low-level pool for ExAws; don't add HTTPoison, Tesla, or `:httpc` call sites.
- Keep one module per file. Never turn user input into atoms with `String.to_atom/1`.
- Use standard date/time modules; don't add dependencies without authorization.
- Return or bind the result of socket transformations and conditional expressions; rebinding inside a branch does not update the outer variable.
- Access struct fields directly and changeset fields with `Ecto.Changeset.get_field/2`.
- Keep server-controlled fields such as `user_id` out of `cast`; set them explicitly.
- `validate_number/2` has no `:allow_nil` option. Ecto schema text fields use `:string`.
- Generate migrations with `mix ecto.gen.migration descriptive_name`.
- Prefer `Task.async_stream/3` for bounded concurrent enumeration; choose timeouts for the workload.

## Phoenix and templates

- Wrap LiveView content in `<Layouts.app flash={@flash} ...>`. For missing `current_scope`, check the route's `live_session`, auth hooks, and layout assigns.
- `Layouts` is already aliased through `kaguya_web.ex`. Keep `<.flash_group>` calls inside `layouts.ex`.
- Use the shared `<.icon>` and `<.input>` components. Custom input classes must provide complete styling because they replace the defaults.
- Prefer function components; use LiveComponents only for a specific need. Name LiveViews with a `Live` suffix.
- Router scopes already supply module aliases; avoid duplicate prefixes. Shared template imports belong in `kaguya_web.ex`'s `html_helpers`.
- Use HEEx (`~H` / `.html.heex`), `{...}` for values and attributes, and `<%= ... %>` for body blocks. Render collections with `for` or `:for`, not `Enum.each`.
- Use lists for conditional classes, `<%!-- --%>` for comments, and `phx-no-curly-interpolation` for literal code containing braces.
- Build forms with `to_form/2`, `<.form for={@form}>`, `<.inputs_for>`, and `<.input field={@form[:field]}>`. Use changesets for validated forms or string-keyed maps for param-only forms; don't pass raw changesets to templates or use legacy form helpers.
- Give forms, key interactive elements, and hook elements unique DOM IDs.

## Navigation

Check destinations in `lib/kaguya_web/router.ex`. Preserve LiveView navigation so the topbar and client state behave correctly:

- `<.link navigate={...}>` for another LiveView; `<.link patch={...}>` for filters, tabs, pagination, or actions within the current LiveView.
- `<.link href={...}>` for controller routes, external URLs, anchors, downloads, or new-tab links. Don't use raw anchors for internal LiveView navigation.
- Components taking a generic `href` for internal destinations (such as `section_header_link`, `target_link`, and `hero_stat`) must render `<.link navigate={@href}>` internally. `FilterChip` supports `href`, `navigate`, and `patch`; choose per destination.
- Use `push_navigate` / `push_patch`, not deprecated `live_redirect` / `live_patch`.
- In JS, use `lvNavigate(href, "redirect" | "patch")` from `assets/js/lib/lv_navigate.js`. Dynamically created internal anchors need `data-phx-link="redirect"` (or `"patch"`) and `data-phx-link-state="push"`. Don't use `window.location.assign` for LiveView routes.

## Collections and hooks

- Use streams for large or incrementally updated collections; small, bounded lists can use regular assigns.
- Stream containers need an ID and `phx-update="stream"`; each streamed child must use the supplied DOM ID.
- Append with the default `at: -1`; prepend with `at: 0`. Use `stream_delete` for removal and refetch with `reset: true` for filtering or sorting. Streams cannot be filtered or counted with `Enum`.
- Track counts and empty state separately, or use an empty-state element with its own ID and `hidden only:block` as the sole non-stream child.
- Reinsert affected stream items when an assign changes their rendered content. Don't use deprecated `phx-update="append"` / `"prepend"`.
- Hooks that own their DOM need `phx-update="ignore"`. Put external hooks in `assets/js/` and register them with `LiveSocket`.
- Colocated hooks use `:type={Phoenix.LiveView.ColocatedHook}` and names starting with `.`; ordinary inline script tags are forbidden.
- Return or rebind the socket from `push_event/3`; hooks receive events with `this.handleEvent` and send them with `this.pushEvent`.

## Assets and shared UI

- Preserve Tailwind v4's `@import "tailwindcss" source(none)` and the `@source` entries for `../css`, `../js`, and `../../lib/kaguya_web` in `assets/css/app.css`. No `tailwind.config.js` or `@apply`.
- Use SaladUI + `tw_merge`, Tailwind utilities, and custom CSS. Don't add daisyUI.
- Inside `<.dropdown_menu_content>`, use `<.dropdown_menu_action event="..." value={...}>` for LiveView actions. Raw `button phx-click` bypasses menu state management and can leave focus/open state stuck after patches.
- Import vendor JS/CSS through `app.js` / `app.css`; don't add vendor script or stylesheet URLs to layouts. Other supported bundles are the per-island esbuild entries in `mix.exs`.

## Verification

- Read `mix help task_name` before using Mix tasks. Run focused tests while iterating; use `mix test --failed` to retry failures.
- Run checks appropriate to the change: targeted tests, `mix compile --warnings-as-errors`, `mix credo`, and formatting of touched Elixir files. Avoid `mix deps.clean --all` without a specific reason.
- Start test processes with `start_supervised!/1`. Synchronize with messages/monitors or `:sys.get_state/1`, not `Process.sleep/1` or `Process.alive?/1` checks.
- Test observable behavior with `Phoenix.LiveViewTest`: stable IDs, `element/2`, `has_element?/2`, `render_change/2`, and `render_submit/2`. Avoid raw HTML string assertions; inspect selector failures with LazyHTML.
