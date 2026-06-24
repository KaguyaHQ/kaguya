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

  describe "perform/1 with unknown args" do
    test "returns an error tuple for an unrecognized type" do
      job = %Oban.Job{args: %{"type" => "nonsense"}}
      assert {:error, msg} = ImageVariantWorker.perform(job)
      assert msg =~ "unknown args shape"
    end

    test "returns an error tuple for empty args" do
      job = %Oban.Job{args: %{}}
      assert {:error, msg} = ImageVariantWorker.perform(job)
      assert msg =~ "unknown args shape"
    end

    test "returns an error tuple when type is missing" do
      job = %Oban.Job{args: %{"id" => "abc", "vn_id" => "def"}}
      assert {:error, msg} = ImageVariantWorker.perform(job)
      assert msg =~ "unknown args shape"
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
