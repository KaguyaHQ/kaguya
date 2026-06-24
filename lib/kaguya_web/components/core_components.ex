defmodule KaguyaWeb.CoreComponents do
  use Phoenix.Component

  attr :default, :string, default: nil
  attr :suffix, :string, default: nil

  def live_title(assigns) do
    ~H"""
    <title>{render_slot(assigns) || @default}{if @suffix, do: @suffix}</title>
    """
  end

  attr :class, :any, default: nil
  attr :rest, :global

  def search_icon(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 512 512"
      fill="none"
      class={["shrink-0", @class]}
      {@rest}
    >
      <path
        d="M221.09 64a157.09 157.09 0 10157.09 157.09A157.1 157.1 0 00221.09 64z"
        stroke="currentColor"
        stroke-miterlimit="10"
        stroke-width="32"
      />
      <path
        d="M338.29 338.29L448 448"
        stroke="currentColor"
        stroke-linecap="round"
        stroke-miterlimit="10"
        stroke-width="32"
      />
    </svg>
    """
  end
end
