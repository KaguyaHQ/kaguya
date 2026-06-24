defmodule Kaguya.Moderation.Reasons do
  @moduledoc false

  @max_reason_length 1_000

  def normalize_optional(reason) do
    reason = normalize(reason)

    cond do
      is_nil(reason) ->
        {:ok, nil}

      String.length(reason) > @max_reason_length ->
        {:error, "Reason must be #{@max_reason_length} characters or fewer"}

      true ->
        {:ok, reason}
    end
  end

  def normalize_required(reason) do
    reason = normalize(reason)

    cond do
      is_nil(reason) ->
        {:error, "A moderation reason is required"}

      String.length(reason) > @max_reason_length ->
        {:error, "Reason must be #{@max_reason_length} characters or fewer"}

      true ->
        {:ok, reason}
    end
  end

  def normalize(nil), do: nil

  def normalize(reason) when is_binary(reason) do
    case String.trim(reason) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  def normalize(_reason), do: nil
end
