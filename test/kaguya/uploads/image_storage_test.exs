defmodule Kaguya.ImageStorageTest do
  use ExUnit.Case, async: true

  alias Kaguya.{ImageStorage, Uploads}

  describe "validate_image_bytes/1" do
    test "rejects bytes without image metadata as a permanent input error" do
      assert {:error, {:invalid_image, "Could not extract image metadata"}} =
               ImageStorage.validate_image_bytes("not an image")
    end

    test "rejects unsupported image formats as a permanent input error" do
      gif = <<"GIF89a", 1::little-16, 1::little-16, 0, 0, 0>>

      assert {:error, {:invalid_image, message}} = ImageStorage.validate_image_bytes(gif)
      assert message =~ "Unsupported image format"
    end
  end

  describe "Uploads.stage_local_file/1" do
    test "rejects invalid bytes before requesting an upload URL" do
      path =
        Path.join(System.tmp_dir!(), "invalid-cover-#{System.unique_integer([:positive])}.jpg")

      File.write!(path, "not an image")
      on_exit(fn -> File.rm(path) end)

      assert {:error, "Could not extract image metadata"} = Uploads.stage_local_file(path)
    end
  end
end
