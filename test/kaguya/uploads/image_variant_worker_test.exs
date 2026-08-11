defmodule Kaguya.Uploads.ImageVariantWorkerTest do
  @moduledoc """
  Unit-level tests for ImageVariantWorker. Only covers what can be
  verified without S3, libvips, or DB — namely arg dispatch and the
  worker's Oban config.

  Integration coverage (variant generation actually running, swap
  succeeding for avatar/banner, CDN purge firing) is validated in Phase 2
  via production smoke testing once the VN cover/screenshot callers
  start enqueuing real jobs.
  """

  use ExUnit.Case, async: true

  alias Kaguya.Uploads.ImageVariantWorker

  describe "perform/1 with invalid args" do
    test "cancels an unrecognized type without retrying" do
      job = %Oban.Job{args: %{"type" => "nonsense"}}
      assert {:cancel, msg} = ImageVariantWorker.perform(job)
      assert msg =~ "unknown args shape"
    end

    test "cancels empty args without retrying" do
      job = %Oban.Job{args: %{}}
      assert {:cancel, msg} = ImageVariantWorker.perform(job)
      assert msg =~ "unknown args shape"
    end

    test "cancels when type is missing without retrying" do
      job = %Oban.Job{args: %{"id" => "abc", "vn_id" => "def"}}
      assert {:cancel, msg} = ImageVariantWorker.perform(job)
      assert msg =~ "unknown args shape"
    end
  end

  describe "handle_result/2" do
    test "cancels an undecodable image without retrying" do
      assert {:cancel, "Could not extract image metadata"} =
               ImageVariantWorker.handle_result(
                 {:error, {:invalid_image, "Could not extract image metadata"}},
                 %{"type" => "vn_cover", "id" => "cover-id"}
               )
    end

    test "leaves transient failures retryable" do
      error = {:error, "Failed to fetch temporary image"}
      assert ^error = ImageVariantWorker.handle_result(error, %{"type" => "vn_cover"})
    end
  end

  describe "Oban.Worker configuration" do
    test "uses the images queue" do
      assert ImageVariantWorker.__opts__()[:queue] == :images
    end

    test "retries up to 5 times" do
      assert ImageVariantWorker.__opts__()[:max_attempts] == 5
    end

    test "is unique on type+id within an hour" do
      unique = ImageVariantWorker.__opts__()[:unique]
      assert unique[:keys] == [:type, :id]
      assert unique[:period] == 3600
    end
  end
end
