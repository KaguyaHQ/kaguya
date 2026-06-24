defmodule Kaguya.ProducerImagesTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Kaguya.Repo

  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.ProducerImages
  alias Kaguya.Producers.{Producer, ProducerImage}
  alias Kaguya.Repo
  alias Kaguya.Test.UserFixtures

  setup do
    :ok = Sandbox.checkout(Repo)

    user = UserFixtures.insert_user!()

    producer =
      %Producer{}
      |> Producer.changeset(%{name: "Image Studio #{System.unique_integer([:positive])}"})
      |> Repo.insert!()

    %{producer: producer, user: user}
  end

  test "upload_image inserts a row, enqueues variants, and auto-sets primary", %{
    producer: producer,
    user: user
  } do
    upload_id = Ecto.UUID.generate()

    assert {:ok, %ProducerImage{id: ^upload_id, producer_id: producer_id}} =
             ProducerImages.upload_image(producer.id, upload_id, user.id)

    assert producer_id == producer.id

    assert_enqueued(
      worker: Kaguya.Uploads.ImageVariantWorker,
      args: %{"type" => "producer_image", "id" => upload_id}
    )

    assert %{primary_image_id: ^upload_id} = Repo.get!(Producer, producer.id)
  end

  test "upload_image does not replace an existing primary image", %{
    producer: producer,
    user: user
  } do
    first_id = Ecto.UUID.generate()
    second_id = Ecto.UUID.generate()

    assert {:ok, _} = ProducerImages.upload_image(producer.id, first_id, user.id)
    assert {:ok, _} = ProducerImages.upload_image(producer.id, second_id, user.id)

    assert %{primary_image_id: ^first_id} = Repo.get!(Producer, producer.id)
  end
end
