defmodule KaguyaWeb.ProfileLive.Events do
  @moduledoc """
  Shared `handle_event/3` helpers for every profile tab.

  Tab LiveViews delegate `toggle_follow` and other cross-cutting events to
  this module so persistence + flash messaging stays in one place. The
  parent LiveView is responsible for refreshing its own header assigns
  after a mutation — see `refresh_header/2` below.
  """

  import Phoenix.LiveView, only: [put_flash: 3]
  import Phoenix.Component, only: [assign: 3]

  alias Kaguya.Social
  alias KaguyaWeb.ProfileLive.Data

  @doc """
  Toggle follow/unfollow for the profile target.

  Expects the socket to carry:
    * `:current_user` — the signed-in viewer (or `nil`)
    * `:profile` — the header view-model from `Data.load_header/2`
  """
  def toggle_follow(socket, %{"user-id" => target_id}) do
    viewer = socket.assigns[:current_user]
    profile = socket.assigns[:profile]

    cond do
      is_nil(viewer) ->
        {:noreply, put_flash(socket, :error, "Sign in to follow.")}

      is_nil(profile) ->
        {:noreply, socket}

      viewer.id == target_id ->
        {:noreply, socket}

      true ->
        case do_toggle(viewer.id, target_id, profile.viewer.follow_state) do
          {:ok, _} ->
            {:noreply, refresh_header(socket, profile.username)}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, error_message(reason))}
        end
    end
  end

  def toggle_follow(socket, _params), do: {:noreply, socket}

  @doc """
  Reload the header view-model after a mutation. The header is the single
  source of truth for follower counts, follow state, etc. — every event
  that affects those values must call this.
  """
  def refresh_header(socket, username) do
    case Data.load_header(username, socket.assigns[:current_user]) do
      {:ok, profile} -> assign(socket, :profile, profile)
      _ -> socket
    end
  end

  defp do_toggle(viewer_id, target_id, :following), do: Social.unfollow_user(viewer_id, target_id)
  defp do_toggle(viewer_id, target_id, _), do: Social.follow_user(viewer_id, target_id)

  defp error_message(reason) when is_binary(reason), do: reason
  defp error_message(_), do: "Could not update follow."
end
