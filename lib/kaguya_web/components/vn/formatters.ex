defmodule KaguyaWeb.VN.Formatters do
  @moduledoc """
  Pure data-shaping helpers used by every VN page component.

  All functions are side-effect free, accept normalized maps from
  `KaguyaWeb.VNLive.PageData`, and return primitive values ready to embed
  in HEEx. Nothing here renders markup; nothing here imports Phoenix.
  """

  @doc "Best available cover URL for a normalized VN map."
  def cover_url(vn) do
    get_in(vn, [:images, :large]) || get_in(vn, [:images, :medium]) ||
      get_in(vn, [:images, :small])
  end

  @doc "Four-digit year extracted from an ISO date prefix."
  def year(nil), do: nil
  def year(<<year::binary-size(4), _rest::binary>>), do: year
  def year(_), do: nil

  @doc "Comma-joined producer names."
  def producer_names(producers) do
    producers
    |> Enum.map(fn
      %{name: name} -> name
      %{producer: %{name: name}} -> name
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  @doc """
  Returns a human-readable length label for a VN.

  Rounds `length_minutes` to whole hours (minimum 1h) and only falls back
  to the humanized `length_category` when minutes are missing.
  """
  def length_label(%{length_minutes: minutes}) when is_integer(minutes) and minutes > 0 do
    hours = max(round(minutes / 60), 1)
    "#{hours}h"
  end

  def length_label(%{length_category: category}) when is_binary(category) and category != "",
    do: humanize(category)

  def length_label(_), do: nil

  @doc "Two-decimal rating, e.g. `4.35`."
  def format_rating(nil), do: "0.00"

  def format_rating(value) when is_number(value),
    do: :erlang.float_to_binary(value * 1.0, decimals: 2)

  @doc "Pluralized count, e.g. `format_count(2, \"like\") => \"2 likes\"`. Adds thousands separator."
  def format_count(value, singular) do
    suffix = if value == 1, do: singular, else: singular <> "s"
    "#{with_commas(value)} #{suffix}"
  end

  @doc "Format an ISO 8601 timestamp as `Jan 27, 2026`."
  def format_datetime(nil), do: nil

  def format_datetime(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, datetime} -> Calendar.strftime(datetime, "%b %-d, %Y")
      _ -> value
    end
  end

  @doc "Title-case a SCREAMING_SNAKE relation/status enum."
  def humanize(nil), do: nil

  def humanize(value) do
    value
    |> to_string()
    |> String.replace("_", " ")
    |> String.downcase()
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  @doc """
  Stretches a raw 0–1 tag `relevance_score` to the 10–96 percentage range used
  on tag chips.
  """
  def tag_percentage(%{relevance_score: score}) when is_number(score) do
    neutral = 0.65
    upper = 0.96
    cap = upper * 100
    stretched = (score - neutral) / (upper - neutral) * (cap - 10) + 10

    stretched
    |> min(cap)
    |> max(10)
    |> round()
  end

  def tag_percentage(_), do: nil

  @doc "Map an availability enum to a small parenthetical label, or nil."
  def availability_label("FREE"), do: "Free"
  def availability_label("DEMO"), do: "Demo"
  def availability_label(_), do: nil

  @doc "Render integers with thousands separators (e.g. 1234 -> 1,234)."
  def with_commas(value) when is_integer(value) do
    value
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end

  def with_commas(value), do: to_string(value)
end
