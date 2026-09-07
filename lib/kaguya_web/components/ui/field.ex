defmodule KaguyaWeb.UI.Field do
  @moduledoc """
  A labeled field with optional hint and validation messages.

  Pass the slot's attributes to the input (or textarea/select). Validation stays
  with the caller; errors are already translated, user-facing strings.

      <Field.field :let={attrs} id="email" label="Email" errors={@errors}>
        <Input.input name="email" type="email" control_size="roomy" {attrs} />
      </Field.field>
  """
  use Phoenix.Component

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :hint, :string, default: nil
  attr :errors, :list, default: []
  attr :required, :boolean, default: false
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def field(assigns) do
    described_by =
      [assigns.errors != [] && "#{assigns.id}-errors", assigns.hint && "#{assigns.id}-hint"]
      |> Enum.filter(& &1)
      |> Enum.join(" ")

    assigns =
      assign(assigns, :input_attrs, %{
        id: assigns.id,
        required: assigns.required,
        "aria-invalid": if(assigns.errors != [], do: "true"),
        "aria-describedby": if(described_by != "", do: described_by)
      })

    ~H"""
    <div class={["space-y-2", @class]}>
      <label for={@id} class="text-foreground-secondary block text-sm">
        {@label}<span :if={@required} aria-hidden="true"> *</span>
      </label>
      <div>
        {render_slot(@inner_block, @input_attrs)}
        <div :if={@errors != [] || @hint} class="mt-1 space-y-1 text-sm">
          <div
            :if={@errors != []}
            id={@id <> "-errors"}
            aria-live="polite"
            class="text-semantic-error space-y-1"
          >
            <p :for={error <- @errors}>{error}</p>
          </div>
          <p :if={@hint} id={@id <> "-hint"} class="text-foreground-tertiary">{@hint}</p>
        </div>
      </div>
    </div>
    """
  end
end
