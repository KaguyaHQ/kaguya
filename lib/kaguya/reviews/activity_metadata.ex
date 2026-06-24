defmodule Kaguya.Reviews.ActivityMetadata do
  @moduledoc """
  Shared VN metadata builders for review- and rating-activity records.

  Both `Kaguya.Reviews` and `Kaguya.Reviews.Ratings` record activities that
  embed the same VN snapshot, so the builders live here rather than being
  duplicated across the two contexts.
  """

  alias Kaguya.VisualNovels

  @doc """
  Builds the common VN metadata map embedded in review/rating activities.
  Returns `%{}` when the VN is missing.
  """
  def vn_metadata(nil), do: %{}

  def vn_metadata(vn) do
    %{
      vn_id: vn.id,
      vn_title: vn.title,
      vn_slug: vn.slug,
      vn_image_url: VisualNovels.build_image_urls(vn)[:small],
      vn_release_year: release_year(vn.release_date)
    }
  end

  @doc """
  Extracts the year from a `Date`, or `nil` for any other value.
  """
  def release_year(%Date{year: y}), do: y
  def release_year(_), do: nil
end
