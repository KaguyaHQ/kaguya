defmodule Kaguya.ProducerImages do
  @moduledoc """
  Context for producer image uploads and management.
  """

  import Ecto.Query

  alias Kaguya.Producers.{Producer, ProducerImage}
  alias Kaguya.Repo

  @doc """
  Upload a producer image. Auto-sets it as primary if the producer has no image.

  Variant generation is deferred to ImageVariantWorker. The row is inserted
  immediately with nil width/height; the worker backfills them once variants
  land on S3.
  """
  def upload_image(producer_id, upload_id, user_id) do
    with {:ok, producer} <- fetch_producer(producer_id) do
      changeset =
        ProducerImage.changeset(%ProducerImage{}, %{
          id: upload_id,
          producer_id: producer.id,
          uploaded_by: user_id
        })

      multi_result =
        Ecto.Multi.new()
        |> Ecto.Multi.insert(:image, changeset)
        |> Oban.insert(:job, fn %{image: image} ->
          Kaguya.Uploads.ImageVariantWorker.new(%{
            type: "producer_image",
            id: image.id
          })
        end)
        |> Repo.transaction()

      case multi_result do
        {:ok, %{image: image}} ->
          if is_nil(producer.primary_image_id), do: set_primary_image(producer.id, image.id)
          {:ok, image}

        {:error, _step, reason, _changes} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Backfill width/height on a producer_images row after variant generation.
  """
  def update_dimensions(image_id, width, height) do
    from(i in ProducerImage, where: i.id == ^image_id)
    |> Repo.update_all(set: [width: width, height: height])

    :ok
  end

  @doc """
  Set primary producer image. Does not pin; it only changes primary_image_id.
  """
  def set_primary_image(producer_id, image_id) do
    case Repo.get(ProducerImage, image_id) do
      nil ->
        {:error, "Image not found"}

      %{producer_id: ^producer_id} = image ->
        from(p in Producer, where: p.id == ^producer_id)
        |> Repo.update_all(
          set: [
            primary_image_id: image.id,
            is_image_nsfw: image.is_image_nsfw,
            is_image_suggestive: image.is_image_suggestive
          ]
        )

        {:ok, true}

      _ ->
        {:error, "Image does not belong to this producer"}
    end
  end

  @doc """
  List images for a producer.
  """
  def list_images(producer_id) do
    from(i in ProducerImage,
      where: i.producer_id == ^producer_id,
      order_by: [asc: i.inserted_at]
    )
    |> Repo.all()
  end

  defp fetch_producer(id) do
    case Repo.get(Producer, id) do
      nil -> {:error, "Producer not found"}
      producer -> {:ok, producer}
    end
  end
end
