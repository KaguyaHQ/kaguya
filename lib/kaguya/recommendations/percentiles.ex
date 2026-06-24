defmodule Kaguya.Recommendations.Percentiles do
  @moduledoc """
  Maps raw EASE scores to the display "relevance %" (0–100).

  The table is produced by `priv/recommendations/pregenerate_user_recs.py`
  as a side effect of the pregen scoring pass: every top-K score across
  all scored users is sorted, and 101 boundary scores are written into
  `ease_B_meta.json` under `score_percentiles`.

  Fallback users (primary centered scoring produced too few positives;
  the top-N fallback kicks in) generate scores ~10x larger than
  primary users. To avoid those scores saturating the upper tail of
  the distribution, the Python pregen multiplies fallback entries'
  scores by `fallback_score_scale` (chosen to align fallback's p99
  with primary's p99) before computing the table. The served binary
  carries rescaled scores; the Elixir Engine, on the logged-in path,
  applies the same scale when its own fallback fires.

  Lookup is cheap (~7 comparisons, no allocation) and the boundaries
  + scale factor are cached in `:persistent_term` after the first read.
  """

  @method "ease"
  @term_key {__MODULE__, :ctx, @method}

  @doc "Percentile (0..100) of `score` against the population distribution."
  def relevance_pct(nil), do: nil

  def relevance_pct(score) when is_number(score) do
    case ctx() do
      %{boundaries: boundaries} -> binary_search(score, boundaries, 0, 100)
      nil -> nil
    end
  end

  @doc """
  Scale factor applied to fallback-path scores so they mix cleanly
  into the population percentile distribution. 1.0 when the meta
  doesn't supply it (pre-rescale model artifacts).
  """
  def fallback_score_scale do
    case ctx() do
      %{fallback_scale: s} -> s
      _ -> 1.0
    end
  end

  @doc "Drop cached ctx — call after the meta file is replaced on disk."
  def reset, do: :persistent_term.erase(@term_key)

  defp ctx do
    case :persistent_term.get(@term_key, :miss) do
      :miss ->
        loaded = load_ctx()
        :persistent_term.put(@term_key, loaded)
        loaded

      cached ->
        cached
    end
  end

  defp load_ctx do
    path =
      (System.get_env("KAGUYA_MODEL_DIR") || Application.app_dir(:kaguya, "priv/data"))
      |> Path.join("#{@method}_B_meta.json")

    with {:ok, bin} <- File.read(path),
         {:ok, meta} <- Jason.decode(bin),
         list when is_list(list) and length(list) == 101 <- Map.get(meta, "score_percentiles") do
      %{
        boundaries: List.to_tuple(list),
        fallback_scale: Map.get(meta, "fallback_score_scale", 1.0)
      }
    else
      _ -> nil
    end
  end

  defp binary_search(_score, _boundaries, lo, hi) when lo >= hi, do: lo

  defp binary_search(score, boundaries, lo, hi) do
    mid = div(lo + hi, 2)

    if elem(boundaries, mid) < score do
      binary_search(score, boundaries, mid + 1, hi)
    else
      binary_search(score, boundaries, lo, mid)
    end
  end
end
