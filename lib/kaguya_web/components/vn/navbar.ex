defmodule KaguyaWeb.VN.Navbar do
  @moduledoc """
  Global top navigation rendered on the VN page.

  Anonymous viewers see a simple email sign-in CTA.
  Authenticated viewers see their avatar + display name and a sign-out form.

  The component is stateless — `@viewer` is `nil` when anonymous,
  otherwise a map with `:display_name` / `:username` / `:avatar_url`.
  `@current_path` is round-tripped through OAuth and sign-out so the user
  lands back on the page they came from.
  """

  use KaguyaWeb, :html

  attr :viewer, :map, default: nil
  attr :auth, :map, default: nil
  attr :current_path, :string, required: true

  def navbar(assigns) do
    ~H"""
    <header class="relative z-30 border-b border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-base))]/85 backdrop-blur">
      <div class="mx-auto flex h-14 max-w-[1149px] items-center justify-between gap-4 px-4 lg:px-6">
        <.link
          navigate="/"
          class="text-[18px] font-semibold tracking-tight text-[rgb(var(--foreground-primary))]"
        >
          Kaguya
        </.link>

        <%= cond do %>
          <% @viewer -> %>
            <.signed_in_menu viewer={@viewer} current_path={@current_path} />
          <% @auth -> %>
            <.viewer_loading />
          <% true -> %>
            <.signed_out_actions current_path={@current_path} />
        <% end %>
      </div>
    </header>
    """
  end

  defp viewer_loading(assigns) do
    ~H"""
    <div class="flex items-center gap-2 text-[12px] text-[rgb(var(--foreground-tertiary))]">
      <span class="size-2 animate-pulse rounded-full bg-[rgb(var(--foreground-tertiary))]"></span>
      Loading…
    </div>
    """
  end

  attr :viewer, :map, required: true
  attr :current_path, :string, required: true

  defp signed_in_menu(assigns) do
    ~H"""
    <div class="flex items-center gap-3">
      <%= if @viewer.avatar_url do %>
        <img
          src={@viewer.avatar_url}
          alt={@viewer.display_name || @viewer.username}
          class="size-8 rounded-full object-cover"
        />
      <% else %>
        <div class="flex size-8 items-center justify-center rounded-full bg-[rgb(var(--surface-banner))] text-xs text-[rgb(var(--foreground-secondary))]">
          {viewer_initials(@viewer)}
        </div>
      <% end %>
      <span class="hidden text-sm text-[rgb(var(--foreground-secondary))] sm:block">
        {@viewer.display_name || @viewer.username}
      </span>
      <.form for={%{}} action={~p"/auth/sign-out"} method="post" class="shrink-0">
        <input type="hidden" name="return_to" value={@current_path} />
        <button
          type="submit"
          class="rounded-full border border-[rgb(var(--chip-border-default))] px-3 py-1 text-[11px] tracking-[0.16em] text-[rgb(var(--foreground-secondary))] uppercase transition hover:border-[rgb(var(--chip-border-hover))] hover:text-[rgb(var(--foreground-primary))]"
        >
          Sign out
        </button>
      </.form>
    </div>
    """
  end

  attr :current_path, :string, required: true

  defp signed_out_actions(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <.link
        navigate={~p"/login?return_to=#{@current_path}"}
        class="flex items-center gap-2 rounded-full bg-white px-3 py-1.5 text-[13px] font-medium text-[#1c1c1c] transition hover:bg-white/90"
      >
        Sign in
      </.link>
    </div>
    """
  end

  defp viewer_initials(%{display_name: name}) when is_binary(name) and name != "",
    do: initials_from(name)

  defp viewer_initials(%{username: name}) when is_binary(name) and name != "",
    do: initials_from(name)

  defp viewer_initials(_), do: "?"

  defp initials_from(name) do
    name
    |> String.trim()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join("", fn part -> part |> String.first() |> String.upcase() end)
  end
end
