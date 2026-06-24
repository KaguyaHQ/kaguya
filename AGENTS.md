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

- **Elixir `~> 1.19` / OTP 27** (installed locally: 1.19.5)
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

## Framework conventions

The sections below are Phoenix-installer usage-rules — evergreen guardrails for Elixir / Phoenix / Ecto / LiveView code, lifted from `mix phx.new` boilerplate and lightly trimmed for kaguya's setup (Tailwind v4, SaladUI components, no daisyUI).

- Prefer the included `:req` (`Req`) library for HTTP requests; **avoid** `:httpoison`, `:tesla`, and `:httpc`. (`:finch` is also present but is used as a low-level pool for ExAws etc.; new HTTP call sites should use Req.)

<!-- phoenix:phoenix18-start -->
### Phoenix v1.8 guidelines

- **Always** begin LiveView templates with `<Layouts.app flash={@flash} ...>` which wraps all inner content
- The `KaguyaWeb.Layouts` module is aliased in `kaguya_web.ex`, so you can use it without aliasing again
- Anytime you run into errors with no `current_scope` assign:
  - You failed to follow the Authenticated Routes guidelines, or you failed to pass `current_scope` to `<Layouts.app>`
  - **Always** fix the `current_scope` error by moving your routes to the proper `live_session` and ensure you pass `current_scope` as needed
- Phoenix v1.8 moved the `<.flash_group>` component to the `Layouts` module. You are **forbidden** from calling `<.flash_group>` outside of the `layouts.ex` module
- Out of the box, `core_components.ex` imports an `<.icon name="hero-x-mark" class="w-5 h-5"/>` component for hero icons. **Always** use the `<.icon>` component for icons, **never** use `Heroicons` modules or similar
- **Always** use the imported `<.input>` component for form inputs from `core_components.ex` when available
- If you override the default input classes (`<.input class="myclass px-2 py-1 rounded-lg">)`) class with your own values, no default classes are inherited, so your custom classes must fully style the input
<!-- phoenix:phoenix18-end -->

### JS and CSS guidelines

- **Use Tailwind CSS classes and custom CSS rules** to create polished, responsive interfaces.
- Tailwind v4 **no longer needs a tailwind.config.js** and uses the new import syntax in `app.css`:

      @import "tailwindcss" source(none);
      @source "../css";
      @source "../js";
      @source "../../lib/kaguya_web";

- **Always use and maintain this import syntax** in `assets/css/app.css`
- **Never** use `@apply` when writing raw css
- kaguya uses **SaladUI** (`salad_ui`) + `tw_merge` for shared components; hand-written Tailwind components are also fine. Don't pull in daisyUI.
- For clickable LiveView actions inside `<.dropdown_menu_content>`, use `<.dropdown_menu_action event="..." value={...}>`. Do not put raw `<button phx-click=...>` inside dropdown menu content; raw buttons bypass the menu state machine and can leave open/focus state stuck after LiveView patches.
- Out of the box **only the app.js and app.css bundles are supported** (plus the per-island esbuild entries declared in `mix.exs`)
  - You cannot reference an external vendor'd script `src` or link `href` in the layouts
  - You must import the vendor deps into app.js and app.css to use them
  - **Never write inline `<script>custom js</script>` tags within templates**

<!-- phoenix:elixir-start -->
### Elixir guidelines

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access, ie:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc you *must* bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression, ie:

      # INVALID: we are rebinding inside the `if` and the result never gets assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID: we rebind the result of the `if` to a new variable
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist — `Ecto.Changeset.get_field/2` for changesets
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces. **Never** install additional dependencies unless asked or for date/time parsing (use `date_time_parser` if needed)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry` require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

### Mix guidelines

- Read the docs and options before using tasks (by using `mix help task_name`)
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason

### Test guidelines

- **Always use `start_supervised!/1`** to start processes in tests as it guarantees cleanup between tests
- **Avoid** `Process.sleep/1` and `Process.alive?/1` in tests
  - Instead of sleeping to wait for a process to finish, **always** use `Process.monitor/1` and assert on the DOWN message:

        ref = Process.monitor(pid)
        assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

  - Instead of sleeping to synchronize before the next call, **always** use `_ = :sys.get_state/1` to ensure the process has handled prior messages
<!-- phoenix:elixir-end -->

<!-- phoenix:phoenix-start -->
### Phoenix guidelines

- Remember Phoenix router `scope` blocks include an optional alias which is prefixed for all routes within the scope. **Always** be mindful of this when creating routes within a scope to avoid duplicate module prefixes.

- You **never** need to create your own `alias` for route definitions! The `scope` provides the alias, ie:

      scope "/admin", KaguyaWeb.Admin do
        pipe_through :browser

        live "/users", UserLive, :index
      end

  the UserLive route would point to the `KaguyaWeb.Admin.UserLive` module

- `Phoenix.View` no longer is needed or included with Phoenix, don't use it
<!-- phoenix:phoenix-end -->

<!-- phoenix:ecto-start -->
### Ecto guidelines

- **Always** preload Ecto associations in queries when they'll be accessed in templates, ie a message that needs to reference the `message.user.email`
- Remember `import Ecto.Query` and other supporting modules when you write `seeds.exs`
- `Ecto.Schema` fields always use the `:string` type, even for `:text` columns, ie: `field :name, :string`
- `Ecto.Changeset.validate_number/2` **DOES NOT SUPPORT the `:allow_nil` option**. By default, Ecto validations only run if a change for the given field exists and the change value is not nil, so such an option is never needed
- You **must** use `Ecto.Changeset.get_field(changeset, :field)` to access changeset fields
- Fields which are set programmatically, such as `user_id`, must not be listed in `cast` calls or similar for security purposes. Instead they must be explicitly set when creating the struct
- **Always** invoke `mix ecto.gen.migration migration_name_using_underscores` when generating migration files, so the correct timestamp and conventions are applied
<!-- phoenix:ecto-end -->

<!-- phoenix:html-start -->
### Phoenix HTML guidelines

- Phoenix templates **always** use `~H` or `.html.heex` files (known as HEEx), **never** use `~E`
- **Always** use the imported `Phoenix.Component.form/1` and `Phoenix.Component.inputs_for/1` function to build forms. **Never** use `Phoenix.HTML.form_for` or `Phoenix.HTML.inputs_for` as they are outdated
- When building forms **always** use the already imported `Phoenix.Component.to_form/2` (`assign(socket, form: to_form(...))` and `<.form for={@form} id="msg-form">`), then access those forms in the template via `@form[:field]`
- **Always** add unique DOM IDs to key elements (like forms, buttons, etc) when writing templates, these IDs can later be used in tests (`<.form for={@form} id="product-form">`)
- For "app wide" template imports, you can import/alias into the `kaguya_web.ex`'s `html_helpers` block, so they will be available to all LiveViews, LiveComponents, and modules that do `use KaguyaWeb, :html`

- Elixir supports `if/else` but **does NOT support `if/else if` or `if/elsif`**. **Never use `else if` or `elseif` in Elixir**, **always** use `cond` or `case` for multiple conditionals.

  **Never do this (invalid)**:

      <%= if condition do %>
        ...
      <% else if other_condition %>
        ...
      <% end %>

  Instead **always** do this:

      <%= cond do %>
        <% condition -> %>
          ...
        <% condition2 -> %>
          ...
        <% true -> %>
          ...
      <% end %>

- HEEx require special tag annotation if you want to insert literal curlys like `{` or `}`. If you want to show a textual code snippet on the page in a `<pre>` or `<code>` block you *must* annotate the parent tag with `phx-no-curly-interpolation`:

      <code phx-no-curly-interpolation>
        let obj = {key: "val"}
      </code>

  Within `phx-no-curly-interpolation` annotated tags, you can use `{` and `}` without escaping them, and dynamic Elixir expressions can still be used with `<%= ... %>` syntax

- HEEx class attrs support lists, but you must **always** use list `[...]` syntax. You can use the class list syntax to conditionally add classes, **always do this for multiple class values**:

      <a class={[
        "px-2 text-white",
        @some_flag && "py-5",
        if(@other_condition, do: "border-red-500", else: "border-blue-100"),
        ...
      ]}>Text</a>

  and **always** wrap `if`'s inside `{...}` expressions with parens, like done above

  and **never** do this, since it's invalid (note the missing `[` and `]`):

      <a class={
        "px-2 text-white",
        @some_flag && "py-5"
      }> ...
      => Raises compile syntax error on invalid HEEx attr syntax

- **Never** use `<% Enum.each %>` or non-for comprehensions for generating template content, instead **always** use `<%= for item <- @collection do %>`
- HEEx HTML comments use `<%!-- comment --%>`. **Always** use the HEEx HTML comment syntax for template comments
- HEEx allows interpolation via `{...}` and `<%= ... %>`, but the `<%= %>` **only** works within tag bodies. **Always** use the `{...}` syntax for interpolation within tag attributes, and for interpolation of values within tag bodies. **Always** interpolate block constructs (if, cond, case, for) within tag bodies using `<%= ... %>`.

  **Always** do this:

      <div id={@id}>
        {@my_assign}
        <%= if @some_block_condition do %>
          {@another_assign}
        <% end %>
      </div>

  and **Never** do this – the program will terminate with a syntax error:

      <%!-- THIS IS INVALID NEVER EVER DO THIS --%>
      <div id="<%= @invalid_interpolation %>">
        {if @invalid_block_construct do}
        {end}
      </div>
<!-- phoenix:html-end -->

<!-- phoenix:liveview-start -->
### Phoenix LiveView guidelines

- **Never** use the deprecated `live_redirect` and `live_patch` functions, instead **always** use the `<.link navigate={href}>` and `<.link patch={href}>` in templates, and `push_navigate` and `push_patch` functions in LiveViews
- **Avoid LiveComponents** unless you have a strong, specific need for them
- LiveViews should be named like `KaguyaWeb.WeatherLive`, with a `Live` suffix. When you go to add LiveView routes to the router, the default `:browser` scope is **already aliased** with the `KaguyaWeb` module, so you can just do `live "/weather", WeatherLive`

#### Link convention — `navigate=` vs `patch=` vs `href=`

This project uses Phoenix LiveView for all primary surfaces. Every in-app link must use LiveView client-side navigation so the topbar progress indicator and SPA feel work correctly. Picking the wrong link type causes a full browser reload, which kills the SPA experience.

Rule of thumb — decide by checking the destination route in `lib/kaguya_web/router.ex`:

- **`<.link navigate={...}>`** — destination is a different `live "/path", SomeLive` route. Most in-app links fall here (VN page, profile, character, developer, lists, discussions, settings, account/edit/*, policy pages, etc.).
- **`<.link patch={...}>`** — destination is the **same LiveView module** (often the same path with different query params or action). Use for filter chips, sort toggles, tabs, and pagination *within* a single LiveView. `patch` triggers `handle_params/3` instead of a remount, so state is preserved.
- **`<.link href={...}>`** — only for:
  - External URLs (`https://`, `http://`, `mailto:`, `tel:`)
  - Same-page anchors (`"#section"`)
  - Plug controller routes (`/auth/google`, `/auth/sign-out`, `/signup`, `/sitemap/:id`, `/dumps.json`, etc.)
  - File downloads and content with `target="_blank"`

Never use raw `<a href="/in-app-path">` — convert to `<.link navigate>` or `<.link patch>`. The only acceptable raw `<a>` tags are external URLs (with `target="_blank"`), anchors, or `mailto:`/`tel:`.

If a component accepts a generic `href` attribute (e.g. `<.section_header_link href={...}>`, `<.target_link href={...}>`, `<.hero_stat href={...}>`), the component's *internal* rendering must use `<.link navigate={@href}>` (not `<.link href={@href}>`). Callers pass `href={...}` to the component; the component decides how to navigate. The `FilterChip` shared component accepts all three (`href`, `navigate`, `patch`) — callers pick based on the rule above.

When in doubt, grep the router for the destination path. If it's `live "..."`, use `navigate` (or `patch` for same module). If it's `get/post`, use `href`.

**Client-side JS navigation:** if you need to navigate from a hook or other JS to an in-app LiveView route, **never** use `window.location.assign(...)` (full reload — kills the topbar). Use the `lvNavigate(href, "redirect" | "patch")` helper from `assets/js/lib/lv_navigate.js`, or build the anchor manually with `data-phx-link="redirect"` + `data-phx-link-state="push"` attributes so the LiveView JS client intercepts the click. The same applies to dynamically-created `<a>` tags via `document.createElement("a")` — set those data attributes for in-app destinations.

#### LiveView streams

- **Always** use LiveView streams for collections for assigning regular lists to avoid memory ballooning and runtime termination with the following operations:
  - basic append of N items - `stream(socket, :messages, [new_msg])`
  - resetting stream with new items - `stream(socket, :messages, [new_msg], reset: true)` (e.g. for filtering items)
  - prepend to stream - `stream(socket, :messages, [new_msg], at: -1)`
  - deleting items - `stream_delete(socket, :messages, msg)`

- When using the `stream/3` interfaces in the LiveView, the LiveView template must 1) always set `phx-update="stream"` on the parent element, with a DOM id on the parent element like `id="messages"` and 2) consume the `@streams.stream_name` collection and use the id as the DOM id for each child. For a call like `stream(socket, :messages, [new_msg])` in the LiveView, the template would be:

      <div id="messages" phx-update="stream">
        <div :for={{id, msg} <- @streams.messages} id={id}>
          {msg.text}
        </div>
      </div>

- LiveView streams are *not* enumerable, so you cannot use `Enum.filter/2` or `Enum.reject/2` on them. Instead, if you want to filter, prune, or refresh a list of items on the UI, you **must refetch the data and re-stream the entire stream collection, passing reset: true**:

      def handle_event("filter", %{"filter" => filter}, socket) do
        # re-fetch the messages based on the filter
        messages = list_messages(filter)

        {:noreply,
         socket
         |> assign(:messages_empty?, messages == [])
         # reset the stream with the new messages
         |> stream(:messages, messages, reset: true)}
      end

- LiveView streams *do not support counting or empty states*. If you need to display a count, you must track it using a separate assign. For empty states, you can use Tailwind classes:

      <div id="tasks" phx-update="stream">
        <div class="hidden only:block">No tasks yet</div>
        <div :for={{id, task} <- @streams.tasks} id={id}>
          {task.name}
        </div>
      </div>

  The above only works if the empty state is the only HTML block alongside the stream for-comprehension.

- When updating an assign that should change content inside any streamed item(s), you MUST re-stream the items along with the updated assign:

      def handle_event("edit_message", %{"message_id" => message_id}, socket) do
        message = Chat.get_message!(message_id)
        edit_form = to_form(Chat.change_message(message, %{content: message.content}))

        # re-insert message so @editing_message_id toggle logic takes effect for that stream item
        {:noreply,
         socket
         |> stream_insert(:messages, message)
         |> assign(:editing_message_id, String.to_integer(message_id))
         |> assign(:edit_form, edit_form)}
      end

- **Never** use the deprecated `phx-update="append"` or `phx-update="prepend"` for collections

#### LiveView JavaScript interop

- Remember anytime you use `phx-hook="MyHook"` and that JS hook manages its own DOM, you **must** also set the `phx-update="ignore"` attribute
- **Always** provide a unique DOM id alongside `phx-hook` otherwise a compiler error will be raised

LiveView hooks come in two flavors: 1) colocated js hooks for "inline" scripts defined inside HEEx, and 2) external `phx-hook` annotations where JavaScript object literals are defined and passed to the `LiveSocket` constructor.

**Inline colocated js hooks**

**Never** write raw embedded `<script>` tags in heex as they are incompatible with LiveView. Instead, **always use a colocated js hook script tag (`:type={Phoenix.LiveView.ColocatedHook}`) when writing scripts inside the template**:

    <input type="text" name="user[phone_number]" id="user-phone-number" phx-hook=".PhoneNumber" />
    <script :type={Phoenix.LiveView.ColocatedHook} name=".PhoneNumber">
      export default {
        mounted() {
          this.el.addEventListener("input", e => {
            let match = this.el.value.replace(/\D/g, "").match(/^(\d{3})(\d{3})(\d{4})$/)
            if(match) {
              this.el.value = `${match[1]}-${match[2]}-${match[3]}`
            }
          })
        }
      }
    </script>

- colocated hooks are automatically integrated into the app.js bundle
- colocated hooks names **MUST ALWAYS** start with a `.` prefix, i.e. `.PhoneNumber`

**External phx-hook**

External JS hooks (`<div id="myhook" phx-hook="MyHook">`) must be placed in `assets/js/` and passed to the LiveSocket constructor:

    const MyHook = {
      mounted() { ... }
    }
    let liveSocket = new LiveSocket("/live", Socket, {
      hooks: { MyHook }
    });

**Pushing events between client and server**

Use LiveView's `push_event/3` when you need to push events/data to the client for a phx-hook to handle. **Always** return or rebind the socket on `push_event/3` when pushing events:

    # re-bind socket so we maintain event state to be pushed
    socket = push_event(socket, "my_event", %{...})

    # or return the modified socket directly:
    def handle_event("some_event", _, socket) do
      {:noreply, push_event(socket, "my_event", %{...})}
    end

Pushed events can then be picked up in a JS hook with `this.handleEvent`:

    mounted() {
      this.handleEvent("my_event", data => console.log("from server:", data));
    }

Clients can also push an event to the server and receive a reply with `this.pushEvent`:

    mounted() {
      this.el.addEventListener("click", e => {
        this.pushEvent("my_event", { one: 1 }, reply => console.log("got reply from server:", reply));
      })
    }

Where the server handled it via:

    def handle_event("my_event", %{"one" => 1}, socket) do
      {:reply, %{two: 2}, socket}
    end

#### LiveView tests

- `Phoenix.LiveViewTest` module and `LazyHTML` (included) for making your assertions
- Form tests are driven by `Phoenix.LiveViewTest`'s `render_submit/2` and `render_change/2` functions
- Come up with a step-by-step test plan that splits major test cases into small, isolated files. You may start with simpler tests that verify content exists, gradually add interaction tests
- **Always reference the key element IDs you added in the LiveView templates in your tests** for `Phoenix.LiveViewTest` functions like `element/2`, `has_element/2`, selectors, etc
- **Never** test against raw HTML, **always** use `element/2`, `has_element/2`, and similar: `assert has_element?(view, "#my-form")`
- Instead of relying on testing text content, which can change, favor testing for the presence of key elements
- Focus on testing outcomes rather than implementation details
- Be aware that `Phoenix.Component` functions like `<.form>` might produce different HTML than expected. Test against the output HTML structure, not your mental model of what you expect it to be
- When facing test failures with element selectors, add debug statements to print the actual HTML, but use `LazyHTML` selectors to limit the output, ie:

      html = render(view)
      document = LazyHTML.from_fragment(html)
      matches = LazyHTML.filter(document, "your-complex-selector")
      IO.inspect(matches, label: "Matches")

#### Form handling

**Creating a form from params**

If you want to create a form based on `handle_event` params:

    def handle_event("submitted", params, socket) do
      {:noreply, assign(socket, form: to_form(params))}
    end

When you pass a map to `to_form/1`, it assumes said map contains the form params, which are expected to have string keys.

You can also specify a name to nest the params:

    def handle_event("submitted", %{"user" => user_params}, socket) do
      {:noreply, assign(socket, form: to_form(user_params, as: :user))}
    end

**Creating a form from changesets**

When using changesets, the underlying data, form params, and errors are retrieved from it. The `:as` option is automatically computed too. E.g. if you have a user schema:

    defmodule Kaguya.Users.User do
      use Ecto.Schema
      ...
    end

And then you create a changeset that you pass to `to_form`:

    %Kaguya.Users.User{}
    |> Ecto.Changeset.change()
    |> to_form()

Once the form is submitted, the params will be available under `%{"user" => user_params}`.

In the template, the form assign can be passed to the `<.form>` function component:

    <.form for={@form} id="todo-form" phx-change="validate" phx-submit="save">
      <.input field={@form[:field]} type="text" />
    </.form>

Always give the form an explicit, unique DOM ID, like `id="todo-form"`.

**Avoiding form errors**

**Always** use a form assigned via `to_form/2` in the LiveView, and the `<.input>` component in the template. In the template **always access forms this**:

    <%!-- ALWAYS do this (valid) --%>
    <.form for={@form} id="my-form">
      <.input field={@form[:field]} type="text" />
    </.form>

And **never** do this:

    <%!-- NEVER do this (invalid) --%>
    <.form for={@changeset} id="my-form">
      <.input field={@changeset[:field]} type="text" />
    </.form>

- You are FORBIDDEN from accessing the changeset in the template as it will cause errors
- **Never** use `<.form let={f} ...>` in the template, instead **always use `<.form for={@form} ...>`**, then drive all form references from the form assign as in `@form[:field]`. The UI should **always** be driven by a `to_form/2` assigned in the LiveView module that is derived from a changeset
<!-- phoenix:liveview-end -->
