defmodule KaguyaWeb.VNLive.Show.ComponentsTest do
  use KaguyaWeb.ConnCase, async: true

  alias KaguyaWeb.VNLive.Show.Components

  test "media lightbox exposes previous and next keyboard controls" do
    html =
      render_component(&Components.media_lightbox/1,
        media: %{
          src: "/images/screenshot.webp",
          alt: "Screenshot",
          heading: "Screenshots",
          context: "Example VN",
          kind: :screenshots,
          index: 0,
          count: 2,
          entries: [
            %{
              id: "shot-1",
              src: "/images/screenshot.webp",
              thumb: "/images/screenshot-small.webp",
              alt: "Screenshot",
              title: "Screenshot 1 of 2"
            },
            %{
              id: "shot-2",
              src: "/images/screenshot-2.webp",
              thumb: "/images/screenshot-2-small.webp",
              alt: "Screenshot",
              title: "Screenshot 2 of 2"
            }
          ]
        }
      )

    document = LazyHTML.from_fragment(html)

    assert document
           |> LazyHTML.query("#media-lightbox [data-modal-previous][phx-click='previous_media']")
           |> Enum.count() == 1

    assert document
           |> LazyHTML.query("#media-lightbox [data-modal-next][phx-click='next_media']")
           |> Enum.count() == 1

    assert document
           |> LazyHTML.query("#media-lightbox [data-media-thumbnail][phx-click='select_media']")
           |> Enum.count() == 2

    assert document |> LazyHTML.query("[data-modal-fit]") |> Enum.empty?()
    assert document |> LazyHTML.query("[data-modal-fullscreen]") |> Enum.count() == 1
  end

  test "media lightbox omits navigation controls for a single image" do
    html =
      render_component(&Components.media_lightbox/1,
        media: %{
          src: "/images/screenshot.webp",
          alt: "Screenshot",
          heading: "Screenshots",
          context: "Example VN",
          kind: :screenshots,
          index: 0,
          count: 1,
          entries: [
            %{
              id: "shot-1",
              src: "/images/screenshot.webp",
              thumb: "/images/screenshot-small.webp",
              alt: "Screenshot",
              title: "Screenshot 1 of 1"
            }
          ]
        }
      )

    document = LazyHTML.from_fragment(html)

    assert document |> LazyHTML.query("[data-modal-previous]") |> Enum.empty?()
    assert document |> LazyHTML.query("[data-modal-next]") |> Enum.empty?()
  end
end
