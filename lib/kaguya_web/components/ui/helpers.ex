# Originally trimmed from bluzky/salad_ui (SaladUI.Helpers). After the
# native-first floating-UI migration, only `prepare_assign/1` (used by the
# kept `input`/`checkbox` styled components) remains.
defmodule KaguyaWeb.UI.Helpers do
  @moduledoc false
  use Phoenix.Component

  @doc """
  Prepare input assigns for use in a form. Extracts the required attributes
  from the `Phoenix.HTML.FormField` struct and updates the current assigns.
  """
  def prepare_assign(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    assigns
    |> assign(field: nil, id: assigns[:id] || field.id)
    |> assign(:errors, Enum.map(field.errors, &translate_error(&1)))
    |> assign(
      :name,
      assigns[:name] || if(assigns[:multiple], do: field.name <> "[]", else: field.name)
    )
    |> assign(:value, assigns[:value] || field.value)
    |> prepare_assign()
  end

  # use default value if value is not provided or empty
  def prepare_assign(assigns) do
    value =
      if assigns[:value] in [nil, "", []] do
        assigns[:"default-value"]
      else
        assigns[:value]
      end

    assign(assigns, value: value)
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
