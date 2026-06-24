defmodule KaguyaWeb.UserAuth do
  @moduledoc false

  import Plug.Conn

  alias Kaguya.Auth
  alias Kaguya.Users

  @session_key "user_token"

  def session_key, do: @session_key

  def init(opts), do: opts

  def call(conn, opts), do: fetch_current_user(conn, opts)

  def fetch_current_user(conn, _opts) do
    assign(conn, :current_user, current_user_from_session(conn))
  end

  def on_mount(:default, _params, session, socket) do
    current_user = current_user_from_session(session)

    set_observability_context(current_user, socket)

    unread_count = load_unread_count(socket, current_user)

    socket =
      socket
      |> Phoenix.Component.assign(:current_user, current_user)
      |> Phoenix.Component.assign(
        :nav_viewer,
        KaguyaWeb.AppNavbar.normalize_viewer(current_user, unread_count)
      )
      |> Phoenix.Component.assign_new(:current_path, fn -> "/" end)
      |> Phoenix.Component.assign_new(:auth_prompt_message, fn -> "Sign in to Kaguya" end)
      |> maybe_attach_handle_params_hook()
      |> maybe_subscribe_notifications(current_user)
      |> Phoenix.LiveView.attach_hook(
        :auth_prompt,
        :handle_event,
        &handle_auth_prompt_event/3
      )

    {:cont, socket}
  end

  # Unread notification count powers the navbar bell badge. Only computed on the
  # connected mount — the dead HTTP render renders the empty bell and the real
  # count fills in once the socket connects (a few hundred ms later).
  defp load_unread_count(socket, %{id: user_id}) when is_binary(user_id) do
    if Phoenix.LiveView.connected?(socket), do: Kaguya.Social.unread_count(user_id), else: 0
  end

  defp load_unread_count(_socket, _current_user), do: 0

  # Subscribe the connected socket to the user's unread-count topic and attach a
  # global handle_info hook so the bell badge stays live across every LiveView
  # without each one re-implementing the handler.
  defp maybe_subscribe_notifications(socket, %{id: user_id}) when is_binary(user_id) do
    if Phoenix.LiveView.connected?(socket) do
      Phoenix.PubSub.subscribe(Kaguya.PubSub, Kaguya.Social.notifications_topic(user_id))

      Phoenix.LiveView.attach_hook(
        socket,
        :nav_unread_notifications,
        :handle_info,
        &handle_unread_count_info/2
      )
    else
      socket
    end
  end

  defp maybe_subscribe_notifications(socket, _current_user), do: socket

  defp handle_unread_count_info({:unread_count, count}, socket) do
    case socket.assigns[:nav_viewer] do
      %{} = viewer ->
        viewer = Map.put(viewer, :unread_notifications_count, count)
        {:halt, Phoenix.Component.assign(socket, :nav_viewer, viewer)}

      _ ->
        {:halt, socket}
    end
  end

  defp handle_unread_count_info(_message, socket), do: {:cont, socket}

  # `:handle_params` hooks are only valid when the LiveView is mounted via the
  # `live/3` router macro — controller-rendered LVs (e.g. `SignupController`
  # using `Phoenix.LiveView.Controller.live_render/3`) raise on attach. Skip
  # the hook in that case; URL-derived assigns are not relevant when the
  # LiveView can't be patched.
  defp maybe_attach_handle_params_hook(socket) do
    if Map.get(socket, :router) do
      Phoenix.LiveView.attach_hook(
        socket,
        :assign_current_path,
        :handle_params,
        &assign_current_path/3
      )
    else
      socket
    end
  end

  # Pushes user_id + LiveView module/action into both Logger.metadata and
  # Sentry's per-process context, so every log line emitted from inside
  # this LV process gets enriched and any crash routed through the
  # `[:phoenix, :live_view, *, :exception]` telemetry handlers already
  # has the right tags attached.
  defp set_observability_context(current_user, socket) do
    user_id = current_user && Map.get(current_user, :id)

    Logger.metadata(
      user_id: user_id,
      live_view: inspect(socket.view),
      live_action: socket.assigns[:live_action]
    )

    Sentry.Context.set_user_context(%{id: user_id})

    Sentry.Context.set_tags_context(%{
      "source" => "liveview",
      "live_view" => inspect(socket.view)
    })

    :ok
  rescue
    # Belt-and-braces: this runs in mount, so anything that crashes here
    # would crash the page. Logger.metadata is non-throwing; Sentry's
    # context setters can only fail if the process dict is corrupted.
    _ -> :ok
  end

  defp handle_auth_prompt_event("show_auth_prompt", params, socket) do
    message =
      params
      |> Map.get("message")
      |> normalize_auth_prompt_message()

    {:halt, Phoenix.Component.assign(socket, :auth_prompt_message, message)}
  end

  defp handle_auth_prompt_event(_event, _params, socket), do: {:cont, socket}

  defp normalize_auth_prompt_message(message) when is_binary(message) do
    message
    |> String.trim()
    |> case do
      "" -> "Sign in to Kaguya"
      value -> String.slice(value, 0, 120)
    end
  end

  defp normalize_auth_prompt_message(_), do: "Sign in to Kaguya"

  defp assign_current_path(_params, uri, socket) do
    parsed = URI.parse(uri || "/")
    path = parsed.path || "/"
    full = if parsed.query, do: path <> "?" <> parsed.query, else: path
    {:cont, Phoenix.Component.assign(socket, :current_path, full)}
  end

  def log_in_user(conn, %Kaguya.Users.User{} = user) do
    token = Auth.generate_user_session_token(user)

    conn
    |> renew_session()
    |> put_session(@session_key, token)
    |> put_session(:live_socket_id, user_session_topic(token))
  end

  def log_out_user(conn) do
    token = get_session(conn, @session_key)
    Auth.delete_user_session_token(token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      KaguyaWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> configure_session(drop: true)
  end

  defp renew_session(conn) do
    Plug.CSRFProtection.delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp current_user_from_session(%Plug.Conn{} = conn) do
    session = %{
      @session_key => get_session(conn, @session_key),
      "current_user_id" => get_session(conn, "current_user_id")
    }

    current_user_from_session(session)
  end

  defp current_user_from_session(session) when is_map(session) do
    user_from_session_token(session) || user_from_user_id(session)
  end

  defp user_from_session_token(session) do
    with token when is_binary(token) <- Map.get(session, @session_key),
         {%Kaguya.Users.User{} = user, _inserted_at} <- Auth.get_user_by_session_token(token) do
      normalize_user(user)
    else
      _ -> nil
    end
  end

  # Test-only fallback: lets `Plug.Test.init_test_session(%{"current_user_id" => id})`
  # produce a viewer in LiveView mounts without forging a JWT. ListLive uses the
  # same convention internally; centralizing it here keeps each LV stateless.
  defp user_from_user_id(%{"current_user_id" => user_id}) when is_binary(user_id) do
    case Users.get_user(user_id) do
      {:ok, user} -> normalize_user(user)
      _ -> nil
    end
  end

  defp user_from_user_id(%{current_user_id: user_id}) when is_binary(user_id) do
    user_from_user_id(%{"current_user_id" => user_id})
  end

  defp user_from_user_id(_), do: nil

  defp normalize_user(user) do
    user
    |> Map.from_struct()
    |> Map.drop([:__meta__])
  end

  defp user_session_topic(token), do: "users_sessions:#{Base.url_encode64(token)}"
end
