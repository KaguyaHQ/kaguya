defmodule KaguyaWeb.UI.Switch do
  @moduledoc """
  Toggle switch:

    * 36×20 track (`w-9 h-5`), 16×16 thumb (`size-4`).
    * Active track: `bg-primitives-palette-teal-base/45` (the teal we use
      everywhere we mean "on").
    * Inactive track: `bg-text-field-bg`.
    * Thumb travels `translate-x-4` on toggle.

  The component is a plain `<button role="switch">` so the parent owns
  the open/close lifecycle — pass `phx-click`/`phx-value-*` via `:rest`.
  """

  use KaguyaWeb, :html

  attr :id, :string, default: nil
  attr :checked, :boolean, required: true
  attr :class, :string, default: nil

  attr :label, :string,
    default: nil,
    doc: "Accessible label for screen readers when no visible label is rendered."

  attr :disabled, :boolean, default: false
  attr :rest, :global, doc: "phx-click, phx-value-*, etc."

  def switch(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      role="switch"
      aria-checked={to_string(@checked)}
      aria-label={@label}
      disabled={@disabled}
      data-state={if @checked, do: "checked", else: "unchecked"}
      class={[
        "peer inline-flex h-5 w-9 shrink-0 cursor-pointer items-center rounded-full border-2 border-transparent shadow-xs transition-colors",
        "focus-visible:ring-border-divider focus-visible:ring-offset-surface-base focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:outline-hidden",
        "disabled:cursor-not-allowed disabled:opacity-50",
        if(@checked,
          do: "bg-[rgb(var(--primitives-palette-teal-base))]/45",
          else: "bg-text-field-bg"
        ),
        @class
      ]}
      {@rest}
    >
      <span
        aria-hidden="true"
        class={[
          "pointer-events-none block size-4 rounded-full bg-white shadow-lg ring-0 transition-all",
          if(@checked, do: "translate-x-4", else: "translate-x-0 bg-white/60")
        ]}
      />
    </button>
    """
  end
end
