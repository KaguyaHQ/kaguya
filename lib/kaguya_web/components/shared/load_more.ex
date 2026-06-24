defmodule KaguyaWeb.SharedComponents.LoadMore do
  @moduledoc """
  Standard "Load More" pill button used at the bottom of paginated lists.

  The caller wires `phx-click` (and any `phx-value-*`) via the global rest;
  this component owns the shared neutral-pill style and disabled-state dim.
  Wrap with a `flex justify-center py-…` container at the callsite — the
  surrounding spacing varies per page and is left to the caller.
  """

  use KaguyaWeb, :html

  attr :disabled, :boolean, default: false
  attr :label, :string, default: "Load More"
  attr :loading_label, :string, default: nil
  attr :size, :atom, default: :md, values: [:sm, :md]
  attr :class, :any, default: nil
  attr :rest, :global

  def load_more(assigns) do
    ~H"""
    <button
      type="button"
      disabled={@disabled}
      class={[
        "bg-button-background-neutral-default hover:bg-button-background-neutral-hover text-foreground-primary w-fit rounded-[8px] font-medium transition-colors disabled:opacity-60",
        @size == :md && "px-4 py-2 text-sm",
        @size == :sm && "px-4 py-1.5 text-xs",
        @class
      ]}
      {@rest}
    >
      {if @disabled and @loading_label, do: @loading_label, else: @label}
    </button>
    """
  end
end
