defmodule KaguyaWeb.UI.Button do
  @moduledoc """
  The system button.

  Appearance lives in one place: the `.btn` block in `assets/css/app.css`
  (`@layer components`), keyed to the Figma `--color-*` tokens. This component
  only picks a variant + size; there is no class merging and no per-call-site
  styling.

  **Appearance overrides at call sites are forbidden.** `class` is for
  layout/placement only — width (`w-full`), order (`order-2`), margin,
  responsive visibility. If a button needs to look different, that's a new
  variant in app.css or a local component, never a utility override.

  ## Variants

  * `"brand"` (default) — solid brand background; the primary action
  * `"neutral"` — bordered dark neutral; the secondary action
  * `"neutral-inverse"` — light-on-dark fill; safe action in guard dialogs
  * `"destructive"` — solid red; explicit deletes
  * `"ghost"` — transparent until hovered; quiet/tertiary actions
  * `"ghost-destructive"` — error-red text, transparent; the guarded confirm
    in `UI.ConfirmDialog`'s `:guard` tone
  * `"link"` — looks like an inline link

  ## Sizes

  `"large"` (56px) · `"medium"` (44px, default) · `"small"` (40px) ·
  `"icon"` (36px square)

  ## Examples

      <.button phx-click="subscribe">Subscribe</.button>
      <.button variant="destructive" size="small" phx-click="delete">Delete</.button>
      <.button variant="ghost" size="icon" aria-label="Close">
        <.icon name="hero-x-mark" />
      </.button>
      <.button type="submit" loading={@saving?} class="w-full lg:w-fit">
        Save Changes
      </.button>
  """
  use Phoenix.Component

  @variant_classes %{
    "brand" => "btn-brand",
    "neutral" => "btn-neutral",
    "neutral-inverse" => "btn-neutral-inverse",
    "destructive" => "btn-destructive",
    "ghost" => "btn-ghost",
    "ghost-destructive" => "btn-ghost-destructive",
    "link" => "btn-link"
  }

  @size_classes %{
    "large" => "btn-large",
    "medium" => "btn-medium",
    "small" => "btn-small",
    "icon" => "btn-icon"
  }

  attr :type, :string, default: "button"

  attr :class, :any,
    default: nil,
    doc: "layout/placement only (width, order, margin) — never appearance"

  attr :variant, :string,
    values: Map.keys(@variant_classes),
    default: "brand",
    doc: "the button variant style"

  attr :size, :string,
    values: Map.keys(@size_classes),
    default: "medium"

  attr :loading, :boolean,
    default: false,
    doc: "render the three-dot loader instead of the inner block"

  attr :rest, :global, include: ~w(disabled form name value)

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "btn",
        variant_class(@variant),
        size_class(@size),
        "phx-submit-loading:opacity-75",
        @loading && "btn-loading",
        @class
      ]}
      {@rest}
    >
      <%= if @loading do %>
        <.button_loader />
      <% else %>
        {render_slot(@inner_block)}
      <% end %>
    </button>
    """
  end

  @doc """
  Three-dot bouncing loader. Public so callers can drop it next to text when
  they want a custom layout (e.g. "Saving" + dots).
  """
  attr :class, :any, default: nil

  def button_loader(assigns) do
    ~H"""
    <span class={["inline-flex items-center gap-1", @class]} aria-label="Loading" role="status">
      <span class="size-1 animate-bounce rounded-full bg-current [animation-delay:-0.32s]" />
      <span class="size-1 animate-bounce rounded-full bg-current [animation-delay:-0.16s]" />
      <span class="size-1 animate-bounce rounded-full bg-current" />
    </span>
    """
  end

  # `attr values:` catches static typos at compile time; fetch! makes dynamic
  # values (`variant={if …}`) raise loudly instead of falling back silently.
  defp variant_class(variant), do: Map.fetch!(@variant_classes, variant)
  defp size_class(size), do: Map.fetch!(@size_classes, size)
end
