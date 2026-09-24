defmodule Kaguya.VisualNovels.ContributionMedia do
  @moduledoc "Attaches server-staged uploads inside the contribution transaction."
  alias Kaguya.Repo
  alias Kaguya.VisualNovels.Image
  alias Kaguya.Screenshots.Screenshot
  alias Kaguya.Uploads.ImageVariantWorker

  def attach(vn, %{staged_media: %{items: items, user_id: user_id}}) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      attrs = Map.merge(item.flags, %{id: item.id, visual_novel_id: vn.id, uploaded_by: user_id})

      changeset =
        case item.type do
          :cover ->
            Image.changeset(%Image{}, attrs)

          :screenshot ->
            Screenshot.changeset(
              %Screenshot{},
              Map.put(attrs, :s3_key, "visual_novels/screenshots/#{item.id}")
            )
        end

      type = if item.type == :cover, do: "vn_cover", else: "vn_screenshot"

      with {:ok, _} <- Repo.insert(changeset),
           {:ok, _} <-
             Oban.insert(ImageVariantWorker.new(%{type: type, id: item.id, vn_id: vn.id})) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def attach(_vn, _attrs), do: :ok
end
