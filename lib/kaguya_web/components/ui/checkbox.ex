# Copied from bluzky/salad_ui@a8c1da89e7978283a2befc01c793ed141e940b66; modified for kaguya tokens.
# See docs/migrations/nextjs-liveview/references/saladui-manifest.md.
defmodule KaguyaWeb.UI.Checkbox do
  @moduledoc """
  Checkbox input component with SaladUI styling.
  """
  use KaguyaWeb, :ui_component

  attr :id, :any, default: nil
  attr :name, :any, default: nil
  attr :value, :any, default: "true"
  attr :checked, :boolean, default: nil
  attr :"default-value", :any, values: [true, false, "true", "false"], default: false
  attr :field, Phoenix.HTML.FormField
  attr :include_hidden, :boolean, default: true
  attr :class, :string, default: nil
  attr :rest, :global

  def checkbox(assigns) do
    assigns = prepare_assign(assigns)

    checked =
      case assigns.checked do
        value when is_boolean(value) -> value
        _ -> Phoenix.HTML.Form.normalize_value("checkbox", assigns[:"default-value"])
      end

    assigns = assign(assigns, :checked, checked)

    ~H"""
    <input :if={@include_hidden && @name} type="hidden" name={@name} value="false" />
    <input
      id={@id}
      type="checkbox"
      class={[
        "border-primary focus-visible:ring-ring text-primary size-4 shrink-0 rounded-sm border bg-transparent shadow focus-visible:ring-1 focus-visible:outline-none disabled:cursor-not-allowed disabled:opacity-50",
        @class
      ]}
      name={@name}
      value={@value}
      checked={@checked}
      {@rest}
    />
    """
  end
end
