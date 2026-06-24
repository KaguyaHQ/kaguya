defmodule Kaguya.CharacterImages do
  @moduledoc """
  Context for character image uploads and management.
  """

  import Ecto.Query
  alias Kaguya.Repo
  alias Kaguya.Characters.{Character, CharacterImage}

  @doc """
  Upload a character image. Auto-sets as primary if character has no image.

  Variant generation is deferred to ImageVariantWorker. The row is
  inserted immediately with nil width/height; the worker backfills them
  along with the variants on S3 (~1s). The URL built from image.id
  resolves once the worker finishes.
  """
  def upload_image(character_id, upload_id, user_id) do
    with {:ok, char} <- fetch_character(character_id) do
      changeset =
        CharacterImage.changeset(%CharacterImage{}, %{
          id: upload_id,
          character_id: char.id,
          uploaded_by: user_id
        })

      multi_result =
        Ecto.Multi.new()
        |> Ecto.Multi.insert(:image, changeset)
        |> Oban.insert(:job, fn %{image: image} ->
          Kaguya.Uploads.ImageVariantWorker.new(%{
            type: "character_image",
            id: image.id
          })
        end)
        |> Repo.transaction()

      case multi_result do
        {:ok, %{image: image}} ->
          # Auto-set as primary if character has no image
          if is_nil(char.primary_image_id) do
            from(c in Character, where: c.id == ^char.id and is_nil(c.primary_image_id))
            |> Repo.update_all(set: [primary_image_id: image.id])
          end

          {:ok, image}

        {:error, _step, reason, _changes} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Backfill width/height on a character_images row after the worker has
  decoded the source image. Public so ImageVariantWorker can call it
  from outside the CharacterImages context.
  """
  def update_dimensions(image_id, width, height) do
    from(i in CharacterImage, where: i.id == ^image_id)
    |> Repo.update_all(set: [width: width, height: height])

    :ok
  end

  @doc """
  Set primary character image. Does not pin — just sets primary_image_id.
  """
  def set_primary_image(character_id, image_id) do
    case Repo.get(CharacterImage, image_id) do
      nil ->
        {:error, "Image not found"}

      %{character_id: ^character_id} = image ->
        from(c in Character, where: c.id == ^character_id)
        |> Repo.update_all(
          set: [
            primary_image_id: image.id,
            is_image_nsfw: image.is_image_nsfw,
            is_image_suggestive: image.is_image_suggestive
          ]
        )

        {:ok, true}

      _ ->
        {:error, "Image does not belong to this character"}
    end
  end

  @doc """
  List images for a character.
  """
  def list_images(character_id) do
    from(i in CharacterImage,
      where: i.character_id == ^character_id,
      order_by: [asc: i.inserted_at]
    )
    |> Repo.all()
  end

  defp fetch_character(id) do
    case Repo.get(Character, id) do
      nil -> {:error, "Character not found"}
      char -> {:ok, char}
    end
  end
end
