defmodule KaguyaWeb.VN.Backdrop do
  @moduledoc """
  Hero screenshot backdrop for the VN page.

  Desktop variant is a 675px-tall image masked by three Letterboxd-style
  multi-stop gradients: a top fade behind the navbar, fine-grained side
  feathers, and a bottom fade into the page. Mobile variant is a 16:9 banner
  with a bottom-only gradient. Either or both can be skipped by passing nil
  URLs.
  """

  use KaguyaWeb, :html

  # Side feather (L/R edges). 30 stops mirror production VNBackdrop.tsx so
  # the image dissolves into the surface without a visible step.
  @side_gradient """
                 linear-gradient(to right,
                   rgb(var(--surface-base)) 0%,
                   rgb(var(--surface-base) / 0.984) 0.97%,
                   rgb(var(--surface-base) / 0.945) 2.07833333%,
                   rgb(var(--surface-base) / 0.882) 3.29666667%,
                   rgb(var(--surface-base) / 0.804) 4.60166667%,
                   rgb(var(--surface-base) / 0.71) 5.96666667%,
                   rgb(var(--surface-base) / 0.608) 7.5%,
                   rgb(var(--surface-base) / 0.5) 9.16666667%,
                   rgb(var(--surface-base) / 0.396) 10.16%,
                   rgb(var(--surface-base) / 0.294) 11.505%,
                   rgb(var(--surface-base) / 0.204) 12.78%,
                   rgb(var(--surface-base) / 0.12) 13.95833333%,
                   rgb(var(--surface-base) / 0.06) 15.01666667%,
                   rgb(var(--surface-base) / 0.016) 15.92833333%,
                   rgb(var(--surface-base) / 0) 16.66666667%,
                   rgb(var(--surface-base) / 0) 83.33333333%,
                   rgb(var(--surface-base) / 0.016) 84.07166667%,
                   rgb(var(--surface-base) / 0.06) 84.98333333%,
                   rgb(var(--surface-base) / 0.12) 86.04166667%,
                   rgb(var(--surface-base) / 0.204) 87.22%,
                   rgb(var(--surface-base) / 0.294) 88.495%,
                   rgb(var(--surface-base) / 0.396) 89.84%,
                   rgb(var(--surface-base) / 0.5) 90.83333333%,
                   rgb(var(--surface-base) / 0.608) 92.5%,
                   rgb(var(--surface-base) / 0.71) 94.03333333%,
                   rgb(var(--surface-base) / 0.804) 95.39833333%,
                   rgb(var(--surface-base) / 0.882) 96.70333333%,
                   rgb(var(--surface-base) / 0.945) 97.92166667%,
                   rgb(var(--surface-base) / 0.984) 99.03%,
                   rgb(var(--surface-base)) 100%
                 )
                 """
                 |> String.replace(~r/\s+/, " ")

  # Top fade. Darkens the area behind the navbar for readability without
  # killing the image entirely (rendered at opacity-70 so the image still
  # shows through near the top).
  @top_gradient """
                linear-gradient(to bottom,
                  rgb(var(--surface-base)),
                  rgb(var(--surface-base) / 0.945) 16.56%,
                  rgb(var(--surface-base) / 0.8) 30.85%,
                  rgb(var(--surface-base) / 0.608) 43.77%,
                  rgb(var(--surface-base) / 0.392) 56.23%,
                  rgb(var(--surface-base) / 0.2) 69.15%,
                  rgb(var(--surface-base) / 0.055) 83.44%,
                  rgb(var(--surface-base) / 0) 100%
                )
                """
                |> String.replace(~r/\s+/, " ")

  # Bottom fade. Holds full surface to ~21% then ramps to transparent at
  # ~58% so the image visually "sits" above the page content.
  @bottom_gradient """
                   linear-gradient(to top,
                     rgb(var(--surface-base)) 0%,
                     rgb(var(--surface-base)) 21.48148148%,
                     rgb(var(--surface-base) / 0.984) 23.63703704%,
                     rgb(var(--surface-base) / 0.945) 26.1%,
                     rgb(var(--surface-base) / 0.882) 28.80740741%,
                     rgb(var(--surface-base) / 0.804) 31.70740741%,
                     rgb(var(--surface-base) / 0.71) 34.74074074%,
                     rgb(var(--surface-base) / 0.608) 37.5%,
                     rgb(var(--surface-base) / 0.5) 40.97407407%,
                     rgb(var(--surface-base) / 0.396) 44.05925926%,
                     rgb(var(--surface-base) / 0.294) 47.04814815%,
                     rgb(var(--surface-base) / 0.204) 49.88148148%,
                     rgb(var(--surface-base) / 0.12) 52.5%,
                     rgb(var(--surface-base) / 0.06) 54.85185185%,
                     rgb(var(--surface-base) / 0.016) 56.87777778%,
                     rgb(var(--surface-base) / 0) 58.51851852%
                   )
                   """
                   |> String.replace(~r/\s+/, " ")

  @mobile_gradient "linear-gradient(to bottom, rgb(var(--surface-base) / 0), rgb(var(--surface-base) / 0) 50%, rgb(var(--surface-base) / 0.75), rgb(var(--surface-base)))"

  attr :image_url, :string, default: nil
  attr :mobile_image_url, :string, default: nil
  attr :adult, :boolean, default: false

  def vn_backdrop(assigns) do
    assigns =
      assigns
      |> assign(
        :side_bottom_style,
        "background-image: #{@side_gradient}, #{@bottom_gradient}; background-repeat: no-repeat, no-repeat;"
      )
      |> assign(:top_style, "background-image: #{@top_gradient};")
      |> assign(:mobile_style, "background-image: #{@mobile_gradient};")
      |> assign(:desktop_nsfw_style, if(assigns.adult, do: "--nsfw-blur-size: 1200;", else: nil))
      |> assign(:mobile_nsfw_style, if(assigns.adult, do: "--nsfw-blur-size: 800;", else: nil))

    ~H"""
    <div
      :if={@image_url}
      class="animate-backdrop-fade-in pointer-events-none absolute inset-x-0 top-0 z-0 hidden h-[675px] overflow-hidden lg:block"
      aria-hidden="true"
    >
      <div class="absolute inset-x-0 top-0 z-1 h-[135px] opacity-70" style={@top_style}></div>
      <div class="absolute top-0 left-1/2 h-full w-[1200px] -translate-x-1/2">
        <img
          src={@image_url}
          alt=""
          loading="eager"
          fetchpriority="high"
          data-nsfw-blur={if @adult, do: "1"}
          style={@desktop_nsfw_style}
          class="absolute inset-0 size-full object-cover object-top"
        />
        <div class="pointer-events-none absolute inset-0" style={@side_bottom_style}></div>
      </div>
    </div>

    <div
      :if={@mobile_image_url}
      class="relative aspect-video overflow-hidden lg:hidden"
    >
      <img
        src={@mobile_image_url}
        alt=""
        data-nsfw-blur={if @adult, do: "1"}
        style={@mobile_nsfw_style}
        class="size-full object-cover object-center"
      />
      <div class="pointer-events-none absolute inset-0" style={@mobile_style}></div>
    </div>
    """
  end
end
