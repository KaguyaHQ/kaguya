defmodule Kaguya.RatingDistribution do
  @moduledoc """
  Pure helpers for 0.5-step rating distributions (10 buckets: 0.5..5.0).

  Schema-agnostic so it can be reused by VNs and user rating stats
  without duplicating bucket math in multiple places.
  """

  @valid_ratings [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0]
  @default_dist [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

  @doc "Returns the canonical list of allowed rating values."
  def valid_rating_values, do: @valid_ratings

  @doc "Returns a 10-bucket zero distribution."
  def default_dist, do: @default_dist

  @doc "Converts a rating value (0.5..5.0) into a zero-based bucket index (0..9)."
  def rating_to_bucket(rating) when rating in @valid_ratings do
    round(rating * 2) - 1
  end

  @doc "Converts a zero-based bucket index (0..9) to its canonical rating."
  def bucket_to_rating(index) when index in 0..9 do
    index * 0.5 + 0.5
  end

  @doc """
  Adjusts a distribution by `delta` for `rating_val`.

  - `nil` is treated as no-op (useful for create/delete transitions).
  - Values must be in `valid_rating_values/0` (otherwise a FunctionClauseError).
  """
  def adjust_bucket(dist, nil, _delta), do: dist

  def adjust_bucket(dist, rating_val, delta) when rating_val in @valid_ratings do
    index = rating_to_bucket(rating_val)

    List.update_at(dist, index, fn old_count ->
      max(old_count + delta, 0)
    end)
  end

  @doc "Returns the sum of bucket counts."
  def total_count(dist), do: Enum.sum(dist)

  @doc "Returns the sum of ratings (e.g. 3 * 4.0 + 2 * 2.5 ...)."
  def total_sum(dist) do
    dist
    |> Enum.with_index(0)
    |> Enum.reduce(0.0, fn {count, index}, acc ->
      acc + count * bucket_to_rating(index)
    end)
  end

  @doc """
  Computes a simple average from a distribution.
  Returns `0.0` when the distribution is empty.
  """
  def simple_average(dist) do
    count = total_count(dist)

    if count > 0 do
      total_sum(dist) / count
    else
      0.0
    end
  end

  @doc """
  Same as `simple_average/1` but rounded to `decimals`.
  """
  def simple_average(dist, decimals) when is_integer(decimals) and decimals >= 0 do
    dist
    |> simple_average()
    |> Float.round(decimals)
  end

  @doc """
  Bayesian average used for work-level averages.

  When `total_count == 0`, returns `prior_mean`.
  """
  def bayesian_average(prior_mean, prior_count, total_sum, total_count) do
    if total_count > 0 do
      (prior_count * prior_mean + total_sum) / (prior_count + total_count)
    else
      prior_mean
    end
  end

  @doc """
  Converts a 10-element integer list into a map of %{"0.5" => count, "1.0" => count, ...}.
  Used by UI callers to expose rating distributions.
  """
  def convert_ratings_dist(nil), do: %{}

  def convert_ratings_dist(ratings_dist) when is_list(ratings_dist) do
    Enum.zip(Enum.map(1..10, fn i -> i * 0.5 end), ratings_dist)
    |> Enum.into(%{}, fn {rating, count} ->
      {to_string(rating), count}
    end)
  end
end
