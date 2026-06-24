# Copied from bluzky/salad_ui@a8c1da89e7978283a2befc01c793ed141e940b66; modified for kaguya tokens.
# See docs/migrations/nextjs-liveview/references/saladui-manifest.md.
defmodule KaguyaWeb.UI.Input do
  @moduledoc """
  Implementation of an input component for various form input types.

  ## Examples:

      <.input type="text" placeholder="Enter your name" />
      <.input type="email" placeholder="Enter your email" />
      <.input type="password" placeholder="Enter your password" />
      <.input field={f[:email]} type="email" placeholder="Enter your email" />
  """
  use KaguyaWeb, :ui_component

  @doc """
  Renders a form input field or a component that looks like an input field.

  ## Options

  * `:id` - The id to use for the input
  * `:name` - The name to use for the input
  * `:value` - The value to pre-populate the input with
  * `:type` - The type of input (text, email, password, etc.)
  * `:default-value` - The default value of the input
  * `:field` - A form field struct to build the input from
  * `:class` - Additional CSS classes to apply
  * `:placeholder` - Placeholder text (passed through as rest)
  * `:disabled` - Whether the input is disabled (passed through as rest)
  * `:required` - Whether the input is required (passed through as rest)
  * `:readonly` - Whether the input is readonly (passed through as rest)
  * `:autocomplete` - Hints for form autofill feature (passed through as rest)
  """
  attr :id, :any, default: nil
  attr :name, :any, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(date datetime-local email file hidden month number password tel text time url week)

  attr :"default-value", :any

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :class, :any, default: nil

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(assigns) do
    assigns = prepare_assign(assigns)

    rest =
      Map.merge(assigns.rest, Map.take(assigns, [:id, :name, :value, :type]))

    assigns = assign(assigns, :rest, rest)

    ~H"""
    <input
      class={[
        "bg-surface-elevated border-text-field-border focus-visible:border-text-field-border-focus placeholder:text-foreground-quaternary text-foreground-primary flex h-9 w-full rounded-md border px-3 py-1 text-sm shadow-none transition-colors file:border-0 file:bg-transparent file:text-sm file:font-medium focus-visible:border focus-visible:outline-hidden disabled:cursor-not-allowed disabled:opacity-50 dark:bg-transparent dark:shadow-xs",
        @class
      ]}
      {@rest}
    />
    """
  end
end
