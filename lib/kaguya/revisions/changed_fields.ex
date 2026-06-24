defmodule Kaguya.Revisions.ChangedFields do
  @moduledoc false

  def normalize(fields) when is_list(fields) do
    fields
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
  end

  def summary_label(fields, limit \\ 3) when is_list(fields) do
    normalized_fields = normalize(fields)

    label =
      normalized_fields
      |> Enum.take(limit)
      |> Enum.map_join(", ", &field_label/1)

    if length(normalized_fields) > limit do
      "#{label} +#{length(normalized_fields) - limit}"
    else
      label
    end
  end

  def field_label(field), do: to_string(field)
end
