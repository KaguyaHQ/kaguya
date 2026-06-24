defmodule Kaguya.Images do
  @moduledoc "Canonical definitions for every image type"

  @public_base_url Application.compile_env(
                     :kaguya,
                     :uploads_public_base_url,
                     "https://images.kaguya.io"
                   )

  @variants %{
    avatar: [
      %{suffix: "120w", w: 120, h: 120},
      %{suffix: "360w", w: 360, h: 360}
    ],
    banner: [
      # 5.04:1 — matches the rendered desktop banner (988×196 max).
      # Mobile (~2.5:1) object-covers the sides; the user's compositional
      # intent (top↔bottom) is preserved everywhere.
      %{suffix: "1280w", w: 1280, h: 254},
      %{suffix: "2560w", w: 2560, h: 508}
    ],
    vn_cover: [
      %{suffix: "128w", w: 128, h: 182},
      %{suffix: "256w", w: 256, h: 364},
      %{suffix: "512w", w: 512, h: 728},
      %{suffix: "1024w", w: 1024, h: 1456}
    ],
    vn_screenshot: [
      %{suffix: "320w", w: 320, h: 180, fit: true},
      %{suffix: "640w", w: 640, h: 360, fit: true},
      %{suffix: "1280w", w: 1280, h: 720, fit: true}
    ],
    character: [
      %{suffix: "240w", w: 240, h: 342}
    ],
    producer: [
      %{suffix: "120w", w: 120, h: 120},
      %{suffix: "360w", w: 360, h: 360}
    ]
  }

  # Types whose user-uploaded source bytes are archived to S3 verbatim
  # (server-side copy from temp_key) so the lossless original survives.
  # Personal types (avatar/banner) are intentionally excluded.
  @archive_originals MapSet.new([:vn_cover, :vn_screenshot, :character, :producer])

  @paths %{
    avatar: "users/avatars",
    banner: "users/banners",
    vn_cover: "visual_novels",
    vn_screenshot: "visual_novels/screenshots",
    character: "characters",
    producer: "producers"
  }

  @archive_paths %{
    vn_cover: "archive/visual_novels/covers",
    vn_screenshot: "archive/visual_novels/screenshots",
    character: "archive/characters",
    producer: "archive/producers"
  }

  @default_avatar_ids [
    "5a3c374d-edb3-48c5-8424-bcd2c72129a9"
  ]

  # Public API
  def variants(type), do: Map.fetch!(@variants, type)
  def suffixes(type), do: for(v <- variants(type), do: v.suffix)

  def bucket, do: Application.fetch_env!(:kaguya, :uploads_bucket)
  def key(type, id, suffix), do: "#{@paths[type]}/#{id}-#{suffix}.webp"

  def url_for_key(key), do: "#{@public_base_url}/#{key}"
  def public_base_url, do: @public_base_url
  def default_avatar_ids, do: @default_avatar_ids
  def random_default_avatar, do: Enum.random(@default_avatar_ids)
  def temp_key(upload_id), do: "users/temp/#{upload_id}"

  @doc """
  Whether the user-uploaded source bytes for this image type should be
  archived (server-side copy from temp → archive key) before the temp
  file is cleaned up.
  """
  def archive_original?(type), do: MapSet.member?(@archive_originals, type)

  @doc """
  S3 key for the archived original of an upload. Lives under the
  bucket-wide `archive/` namespace, grouped by entity. The key is
  extensionless — the source mime is preserved on the S3 object's
  Content-Type, since archives are never served via direct download.
  """
  def archive_key(type, id), do: "#{Map.fetch!(@archive_paths, type)}/#{id}"
end
