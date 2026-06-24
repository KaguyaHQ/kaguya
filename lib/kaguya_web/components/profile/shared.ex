defmodule KaguyaWeb.Components.Profile.Shared do
  @moduledoc """
  Small reusable atoms shared across profile pages.

  Includes the `user_badge` component, the member-since footer, and the
  `format_short_number/1` helper for compact counts across surfaces.
  """

  use KaguyaWeb, :html

  alias KaguyaWeb.SharedComponents.Time, as: SharedTime

  # ---------------------------------------------------------------------------
  # Formatting helpers
  # ---------------------------------------------------------------------------

  @doc """
  Compact number formatting: `0`, `1.2K`, `34.5M`. Trailing `.0` is stripped.
  """
  def format_short_number(nil), do: "0"
  def format_short_number(0), do: "0"

  def format_short_number(value) when is_integer(value) do
    cond do
      value >= 1_000_000 -> trim_decimal(value / 1_000_000) <> "M"
      value >= 1_000 -> trim_decimal(value / 1_000) <> "K"
      true -> Integer.to_string(value)
    end
  end

  def format_short_number(value) when is_float(value),
    do: format_short_number(trunc(value))

  defp trim_decimal(value) do
    formatted = :erlang.float_to_binary(value * 1.0, decimals: 1)
    if String.ends_with?(formatted, ".0"), do: String.slice(formatted, 0..-3//1), else: formatted
  end

  # ---------------------------------------------------------------------------
  # Badges
  # ---------------------------------------------------------------------------

  @doc """
  Staff / developer badge. Thin wrapper around `SharedComponents.Badge`.
  """
  attr :kind, :atom, default: :staff
  attr :class, :any, default: nil

  def user_badge(assigns) do
    assigns =
      assigns
      |> assign(:label, user_badge_label(assigns.kind))
      |> assign(:tone, user_badge_tone(assigns.kind))

    ~H"""
    <KaguyaWeb.SharedComponents.Badge.badge
      tone={@tone}
      class={@class}
      aria-label={@label}
      title={@label}
    >
      {@label}
    </KaguyaWeb.SharedComponents.Badge.badge>
    """
  end

  defp user_badge_label(kind) do
    case kind |> to_string() |> String.downcase() do
      "admin" -> "Staff"
      "staff" -> "Staff"
      "developer" -> "Developer"
      other -> String.capitalize(other)
    end
  end

  defp user_badge_tone(kind) do
    case kind |> to_string() |> String.downcase() do
      "developer" -> "developer"
      _ -> "staff"
    end
  end

  # ---------------------------------------------------------------------------
  # Member-since footer (sidebar of overview tab)
  # ---------------------------------------------------------------------------

  attr :inserted_at, :any, required: true

  def member_since(assigns) do
    ~H"""
    <div
      :if={@inserted_at}
      class="flex items-center gap-2 text-sm text-[rgb(var(--foreground-tertiary))]"
    >
      <Lucide.users class="size-4" stroke-width="1.5" aria-hidden />
      <span>Joined {SharedTime.format_long_date(@inserted_at)}</span>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Avatar
  # ---------------------------------------------------------------------------

  @doc """
  Profile avatar — shim around `KaguyaWeb.SharedComponents.UserAvatar`.

  Kept for back-compat with existing call sites (`profile/header`,
  `profile_live/follows`, etc.). New code should call `<.user_avatar>`
  directly. See `docs/migrations/nextjs-liveview/plans/component-parity-plan.md` § 1.
  """
  attr :user, :map, required: true
  attr :class, :any, default: "size-10 rounded-full object-cover"
  attr :sizes, :string, default: nil
  attr :alt, :string, default: nil
  attr :fetchpriority, :string, default: nil

  attr :size, :atom,
    default: :small,
    values: [:small, :medium],
    doc: "Which avatar URL variant to use as the `src`."

  def avatar(assigns) do
    {size_class, extra_class} = split_size_class(assigns.class)
    variant = if assigns.size == :medium, do: :default, else: :default

    assigns =
      assigns
      |> assign(:size_class, size_class)
      |> assign(:extra_class, extra_class)
      |> assign(:variant, variant)

    ~H"""
    <KaguyaWeb.SharedComponents.UserAvatar.user_avatar
      user={@user}
      size={@size_class}
      class={@extra_class}
      sizes={@sizes}
      alt={@alt}
      fetchpriority={@fetchpriority}
      fallback={:default_url}
      variant={@variant}
    />
    """
  end

  # The legacy attr accepted `"size-10 rounded-full object-cover ..."` in one
  # string. Split off the size token so the shared component can apply
  # `rounded-full object-cover` itself (which it always does).
  defp split_size_class(nil), do: {"size-10", nil}

  defp split_size_class(class) when is_binary(class) do
    tokens = String.split(class, ~r/\s+/, trim: true)
    {size_tokens, rest} = Enum.split_with(tokens, &String.starts_with?(&1, "size-"))
    size = if size_tokens == [], do: "size-10", else: Enum.join(size_tokens, " ")
    rest = Enum.reject(rest, &(&1 in ["rounded-full", "object-cover"]))
    extra = if rest == [], do: nil, else: Enum.join(rest, " ")
    {size, extra}
  end

  defp split_size_class(class), do: {"size-10", class}
end
