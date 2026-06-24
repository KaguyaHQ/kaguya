defmodule KaguyaWeb.SharedComponents.StatusIcons do
  @moduledoc """
  Single source of truth for reading-status icons + colors.

  Mirrors `../personal/legacy-next-app/src/utils/statusIcons.tsx`:
    * Phosphor icons (CheckCircle, BookOpen, PauseCircle, StopCircle, XCircle)
      inlined as SVG so we don't pull in the whole icon set.
    * Custom Sparkle SVG for Wishlist — Phosphor's default looks wrong.
    * Colors come from the `--status-*` design tokens (see custom-tokens.css),
      exposed in Tailwind as `text-status-read`, `text-status-reading`, etc.

  Use `statuses/0` to enumerate options for menus and `status_icon/1` to
  render an icon for a known status (or `nil` for the empty/add state).
  """

  use KaguyaWeb, :html

  @statuses [
    %{
      status: :read,
      label: "Read",
      icon: :check_circle,
      color_class: "text-status-read"
    },
    %{
      status: :currently_reading,
      label: "Reading",
      icon: :book_open,
      color_class: "text-status-reading"
    },
    %{
      status: :on_hold,
      label: "Paused",
      icon: :pause_circle,
      color_class: "text-status-paused"
    },
    %{
      status: :did_not_finish,
      label: "Did not finish",
      icon: :stop_circle,
      color_class: "text-status-dnf"
    },
    %{
      status: :want_to_read,
      label: "Wishlist",
      icon: :sparkle,
      color_class: "text-status-wishlist"
    },
    %{
      status: :not_interested,
      label: "Not interested",
      icon: :x_circle,
      color_class: "text-status-not-interested"
    }
  ]

  @doc "List of every status option in the canonical order used by the Change-status menu."
  def statuses, do: @statuses

  @doc "Look up a status option by atom. Returns `nil` if the atom isn't a known status."
  def get(status) when is_atom(status), do: Enum.find(@statuses, &(&1.status == status))
  def get(_), do: nil

  attr :status, :atom, default: nil, doc: "Status atom; renders the default sparkle when nil."
  attr :weight, :string, values: ~w(regular fill), default: "regular"
  attr :class, :string, default: "size-4"

  @doc """
  Render the icon for a status. `weight="fill"` switches to the solid variant.
  When `status` is nil, renders the sparkle "add" icon in the tertiary color —
  same convention as Next.js (`getStatusIcon` with no status).
  """
  def status_icon(%{status: nil} = assigns) do
    assigns = assign(assigns, :icon, :sparkle)

    ~H"""
    <.svg_icon icon={@icon} weight={@weight} class={["text-foreground-tertiary", @class]} />
    """
  end

  def status_icon(%{status: status} = assigns) do
    case get(status) do
      nil ->
        assigns = assign(assigns, :icon, :sparkle)

        ~H"""
        <.svg_icon icon={@icon} weight={@weight} class={["text-foreground-tertiary", @class]} />
        """

      option ->
        assigns =
          assigns
          |> assign(:icon, option.icon)
          |> assign(:color_class, option.color_class)

        ~H"""
        <.svg_icon icon={@icon} weight={@weight} class={[@color_class, @class]} />
        """
    end
  end

  # ---------------------------------------------------------------------------
  # Phosphor-style SVG icons (inlined). Two weights: regular (outline) + fill.
  # Color comes from the parent via `currentColor`.
  # ---------------------------------------------------------------------------

  attr :icon, :atom, required: true
  attr :weight, :string, default: "regular"
  attr :class, :any, default: nil

  defp svg_icon(%{icon: :check_circle, weight: "regular"} = assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" class={@class} aria-hidden="true">
      <path
        fill="currentColor"
        d="M173.66,98.34a8,8,0,0,1,0,11.32l-56,56a8,8,0,0,1-11.32,0l-24-24a8,8,0,0,1,11.32-11.32L112,148.69l50.34-50.35A8,8,0,0,1,173.66,98.34ZM232,128A104,104,0,1,1,128,24,104.11,104.11,0,0,1,232,128Zm-16,0a88,88,0,1,0-88,88A88.1,88.1,0,0,0,216,128Z"
      />
    </svg>
    """
  end

  defp svg_icon(%{icon: :check_circle, weight: "fill"} = assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" class={@class} aria-hidden="true">
      <path
        fill="currentColor"
        d="M128,24A104,104,0,1,0,232,128,104.11,104.11,0,0,0,128,24Zm45.66,85.66-56,56a8,8,0,0,1-11.32,0l-24-24a8,8,0,0,1,11.32-11.32L112,148.69l50.34-50.35a8,8,0,0,1,11.32,11.32Z"
      />
    </svg>
    """
  end

  defp svg_icon(%{icon: :book_open, weight: "regular"} = assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" class={@class} aria-hidden="true">
      <path
        fill="currentColor"
        d="M224,48H160a40,40,0,0,0-32,16A40,40,0,0,0,96,48H32A16,16,0,0,0,16,64V192a16,16,0,0,0,16,16H96a24,24,0,0,1,24,24,8,8,0,0,0,16,0,24,24,0,0,1,24-24h64a16,16,0,0,0,16-16V64A16,16,0,0,0,224,48ZM96,192H32V64H96a24,24,0,0,1,24,24V200A39.81,39.81,0,0,0,96,192Zm128,0H160a39.81,39.81,0,0,0-24,8V88a24,24,0,0,1,24-24h64Z"
      />
    </svg>
    """
  end

  defp svg_icon(%{icon: :book_open, weight: "fill"} = assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" class={@class} aria-hidden="true">
      <path
        fill="currentColor"
        d="M224,48H160a40,40,0,0,0-32,16A40,40,0,0,0,96,48H32A16,16,0,0,0,16,64V192a16,16,0,0,0,16,16H96a24,24,0,0,1,24,24,8,8,0,0,0,16,0,24,24,0,0,1,24-24h64a16,16,0,0,0,16-16V64A16,16,0,0,0,224,48ZM120,196.26A39.75,39.75,0,0,0,96,188H32V64H96a24,24,0,0,1,24,24Zm104-4.26H160a39.75,39.75,0,0,0-24,8.26V88a24,24,0,0,1,24-24h64Z"
      />
    </svg>
    """
  end

  defp svg_icon(%{icon: :pause_circle, weight: "regular"} = assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" class={@class} aria-hidden="true">
      <path
        fill="currentColor"
        d="M112,88v80a8,8,0,0,1-16,0V88a8,8,0,0,1,16,0Zm48-8a8,8,0,0,0-8,8v80a8,8,0,0,0,16,0V88A8,8,0,0,0,160,80Zm72,48A104,104,0,1,1,128,24,104.11,104.11,0,0,1,232,128Zm-16,0a88,88,0,1,0-88,88A88.1,88.1,0,0,0,216,128Z"
      />
    </svg>
    """
  end

  defp svg_icon(%{icon: :pause_circle, weight: "fill"} = assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" class={@class} aria-hidden="true">
      <path
        fill="currentColor"
        d="M128,24A104,104,0,1,0,232,128,104.11,104.11,0,0,0,128,24Zm-16,144a8,8,0,0,1-16,0V88a8,8,0,0,1,16,0Zm56,0a8,8,0,0,1-16,0V88a8,8,0,0,1,16,0Z"
      />
    </svg>
    """
  end

  defp svg_icon(%{icon: :stop_circle, weight: "regular"} = assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" class={@class} aria-hidden="true">
      <path
        fill="currentColor"
        d="M160,80H96a16,16,0,0,0-16,16v64a16,16,0,0,0,16,16h64a16,16,0,0,0,16-16V96A16,16,0,0,0,160,80Zm0,80H96V96h64v64Zm72-32A104,104,0,1,1,128,24,104.11,104.11,0,0,1,232,128Zm-16,0a88,88,0,1,0-88,88A88.1,88.1,0,0,0,216,128Z"
      />
    </svg>
    """
  end

  defp svg_icon(%{icon: :stop_circle, weight: "fill"} = assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" class={@class} aria-hidden="true">
      <path
        fill="currentColor"
        d="M128,24A104,104,0,1,0,232,128,104.11,104.11,0,0,0,128,24Zm48,136a16,16,0,0,1-16,16H96a16,16,0,0,1-16-16V96A16,16,0,0,1,96,80h64a16,16,0,0,1,16,16Z"
      />
    </svg>
    """
  end

  defp svg_icon(%{icon: :x_circle, weight: "regular"} = assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" class={@class} aria-hidden="true">
      <path
        fill="currentColor"
        d="M165.66,101.66,139.31,128l26.35,26.34a8,8,0,0,1-11.32,11.32L128,139.31l-26.34,26.35a8,8,0,0,1-11.32-11.32L116.69,128,90.34,101.66a8,8,0,0,1,11.32-11.32L128,116.69l26.34-26.35a8,8,0,0,1,11.32,11.32ZM232,128A104,104,0,1,1,128,24,104.11,104.11,0,0,1,232,128Zm-16,0a88,88,0,1,0-88,88A88.1,88.1,0,0,0,216,128Z"
      />
    </svg>
    """
  end

  defp svg_icon(%{icon: :x_circle, weight: "fill"} = assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" class={@class} aria-hidden="true">
      <path
        fill="currentColor"
        d="M128,24A104,104,0,1,0,232,128,104.11,104.11,0,0,0,128,24Zm37.66,130.34a8,8,0,0,1-11.32,11.32L128,139.31l-26.34,26.35a8,8,0,0,1-11.32-11.32L116.69,128,90.34,101.66a8,8,0,0,1,11.32-11.32L128,116.69l26.34-26.35a8,8,0,0,1,11.32,11.32L139.31,128Z"
      />
    </svg>
    """
  end

  # Box-Icons-style sparkle (Wishlist). Phosphor's default sparkle reads as a
  # "magic wand" — this one matches the Next.js custom SVG.
  defp svg_icon(%{icon: :sparkle, weight: "regular"} = assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" class={@class} aria-hidden="true">
      <path
        fill="currentColor"
        d="m21.45 11.11l-3-1.5l-2.7-1.35l-1.35-2.7l-1.5-3c-.34-.68-1.45-.68-1.79 0l-1.5 3l-1.35 2.7l-2.7 1.35l-3 1.5c-.34.17-.55.52-.55.89s.21.72.55.89l3 1.5l2.7 1.35l1.35 2.7l1.5 3c.17.34.52.55.89.55s.73-.21.89-.55l1.5-3l1.35-2.7l2.7-1.35l3-1.5c.34-.17.55-.52.55-.89s-.21-.72-.55-.89Zm-3.89 1.5l-.84.42l-2.16 1.08l-.3.15l-.15.3L12 18.77l-2.11-4.21l-.15-.3l-.3-.15l-2.16-1.08l-.84-.42L5.23 12l1.21-.61l.84-.42l2.16-1.08l.3-.15l.15-.3L12 5.23l2.11 4.21l.15.3l.3.15l2.16 1.08l.84.42l1.21.61z"
      />
    </svg>
    """
  end

  defp svg_icon(%{icon: :sparkle, weight: "fill"} = assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" class={@class} aria-hidden="true">
      <path
        fill="currentColor"
        d="m21.45 11.11l-3-1.5l-2.68-1.34l-.03-.03l-1.34-2.68l-1.5-3c-.34-.68-1.45-.68-1.79 0l-1.5 3l-1.34 2.68l-.03.03l-2.68 1.34l-3 1.5c-.34.17-.55.52-.55.89s.21.72.55.89l3 1.5l2.68 1.34l.03.03l1.34 2.68l1.5 3c.17.34.52.55.89.55s.72-.21.89-.55l1.5-3l1.34-2.68l.03-.03l2.68-1.34l3-1.5c.34-.17.55-.52.55-.89s-.21-.72-.55-.89Z"
      />
    </svg>
    """
  end
end
