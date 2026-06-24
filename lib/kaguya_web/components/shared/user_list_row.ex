defmodule KaguyaWeb.SharedComponents.UserListRow do
  @moduledoc """
  Shared user row for raters, followers, and fans lists.
  """

  use KaguyaWeb, :html

  import KaguyaWeb.SharedComponents.UserAvatar, only: [user_avatar: 1]

  attr :user, :map, required: true
  attr :follow_value_name, :string, default: "user-id"
  slot :meta

  def user_list_row(assigns) do
    assigns =
      assigns
      |> assign(:display_name, display_name(assigns.user))
      |> assign(:username, username(assigns.user))

    ~H"""
    <div class="grid grid-cols-[165px_1fr] items-center gap-x-1.5 pt-[18px] pb-4 max-lg:-mt-1 sm:grid-cols-[215px_1fr] sm:gap-x-[76px] lg:mt-1 lg:py-3">
      <div class="flex min-w-0 items-center gap-[11px] lg:gap-2">
        <.user_avatar
          user={@user}
          size="size-8 lg:size-[42px]"
          sizes="(max-width: 768px) 32px, 40px"
          fallback={:initials}
          link
        />
        <div class="flex min-w-0 flex-col gap-0.5">
          <.link
            navigate={profile_path(@user)}
            class="line-clamp-1 text-[13px]/4 font-semibold text-[rgb(var(--foreground-primary))] hover:text-[rgb(var(--text-link-hover))] lg:text-[15px] lg:leading-[18px]"
          >
            {@display_name}
          </.link>
          <.link
            :if={@username}
            navigate={profile_path(@user)}
            class="line-clamp-1 text-[11px] leading-[13px] text-[rgb(var(--foreground-secondary))] max-lg:hidden lg:text-[13px] lg:leading-[16px]"
          >
            @{@username}
          </.link>
        </div>
      </div>

      <div class="flex items-center justify-end gap-[24px] lg:gap-[32px]">
        {render_slot(@meta)}
        <.follow_icon_button user={@user} follow_value_name={@follow_value_name} />
      </div>
    </div>
    """
  end

  attr :user, :map, required: true
  attr :follow_value_name, :string, required: true

  defp follow_icon_button(%{user: %{follow_state: :self}} = assigns) do
    ~H"""
    <div class="size-[30px] justify-self-end" />
    """
  end

  defp follow_icon_button(%{user: %{follow_state: :following}} = assigns) do
    assigns = assign(assigns, :follow_attrs, follow_value_attrs(assigns))

    ~H"""
    <button
      type="button"
      phx-click="unfollow_user"
      class="bg-button-background-brand-default text-button-text-on-brand flex size-[30px] items-center justify-center rounded-full transition hover:bg-[rgb(var(--primitives-palette-teal-base))]"
      aria-label={"Unfollow #{display_name(@user)}"}
      title={"Unfollow #{display_name(@user)}"}
      {@follow_attrs}
    >
      <Lucide.x class="size-4" aria-hidden />
    </button>
    """
  end

  defp follow_icon_button(assigns) do
    assigns = assign(assigns, :follow_attrs, follow_value_attrs(assigns))

    ~H"""
    <button
      type="button"
      phx-click="follow_user"
      class="flex size-[30px] items-center justify-center rounded-full bg-[rgb(var(--button-background-neutral-inverse-default))] text-[rgb(var(--surface-base))] transition hover:opacity-90"
      aria-label={"Follow #{display_name(@user)}"}
      title={"Follow #{display_name(@user)}"}
      {@follow_attrs}
    >
      <Lucide.plus class="size-4" aria-hidden />
    </button>
    """
  end

  defp display_name(user) when is_map(user) do
    case Map.get(user, :display_name) do
      name when is_binary(name) and name != "" -> name
      _ -> username(user) || "Unknown"
    end
  end

  defp display_name(_), do: "Unknown"

  defp username(user) when is_map(user) do
    case Map.get(user, :username) do
      username when is_binary(username) and username != "" -> username
      _ -> nil
    end
  end

  defp username(_), do: nil

  defp profile_path(user), do: if(username(user), do: "/@#{username(user)}", else: "#")

  defp follow_value_attrs(%{follow_value_name: name, user: %{id: id}}) when is_binary(name),
    do: %{"phx-value-#{name}" => id}

  defp follow_value_attrs(_), do: %{}
end
