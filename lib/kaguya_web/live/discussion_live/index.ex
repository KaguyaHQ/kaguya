defmodule KaguyaWeb.DiscussionLive.Index do
  use KaguyaWeb, :live_view

  alias Kaguya.Discussions
  alias KaguyaWeb.Components.Shared.NotFoundPage
  alias KaguyaWeb.DiscussionLive.Data
  alias KaguyaWeb.AuthPromptComponents
  alias KaguyaWeb.Discussions.IndexComponents

  @empty_new_post_form %{"title" => "", "content" => "", "target_query" => ""}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Discussions • Kaguya",
       meta_description: "Join the conversation about visual novels with the Kaguya community.",
       posts: [],
       pinned_posts: [],
       category: nil,
       sort: "recent",
       has_next: false,
       next_cursor: nil,
       loading_more: false,
       categories: Data.categories(),
       can_discuss: false,
       can_moderate_discussions: false,
       active_slug: nil,
       not_found?: false,
       load_error?: false,
       current_path: "/discussions",
       new_post_dialog_open: false,
       new_post_discard_open: false,
       new_post_form: @empty_new_post_form,
       new_post_errors: %{},
       new_post_selected_target: nil,
       new_post_target_query: "",
       new_post_target_results: [],
       new_post_target_picker_open: false,
       new_post_creating: false,
       new_post_error_message: nil,
       new_post_show_errors?: false
     )}
  end

  @impl true
  def handle_params(params, _uri, %{assigns: %{live_action: :category}} = socket) do
    case Data.load_category_page(params["category_slug"], params, socket.assigns.current_user) do
      {:ok, payload} ->
        {:noreply,
         assign(socket,
           category: payload.category,
           posts: payload.posts,
           pinned_posts: payload.pinned_posts,
           sort: payload.sort,
           has_next: payload.has_next,
           next_cursor: payload.next_cursor,
           categories: payload.categories,
           can_discuss: payload.can_discuss,
           can_moderate_discussions: payload.can_moderate_discussions,
           active_slug: payload.category.slug,
           not_found?: false,
           load_error?: false,
           loading_more: false,
           current_path: discussions_path(payload.category.slug, payload.sort),
           page_title: "#{payload.category.name} • Discussions • Kaguya",
           meta_description: "#{payload.category.name} discussions on Kaguya"
         )}

      {:error, :not_found} ->
        {:noreply,
         assign(socket,
           not_found?: true,
           load_error?: false,
           page_title: "Discussions • Kaguya"
         )}

      _ ->
        {:noreply, assign(socket, :load_error?, true)}
    end
  end

  def handle_params(params, _uri, socket) do
    case Data.load_index_page(params, socket.assigns.current_user) do
      {:ok, payload} ->
        {:noreply,
         socket
         |> assign(payload)
         |> assign(
           category: nil,
           active_slug: nil,
           not_found?: false,
           load_error?: false,
           loading_more: false,
           current_path: discussions_path(nil, payload.sort),
           page_title: "Discussions • Kaguya",
           meta_description:
             "Join the conversation about visual novels with the Kaguya community."
         )}

      _ ->
        {:noreply, assign(socket, :load_error?, true)}
    end
  end

  @impl true
  def handle_event("open_new_post", _params, %{assigns: %{current_user: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("open_new_post", _params, %{assigns: %{can_discuss: false}} = socket) do
    {:noreply, push_toast(socket, :error, "Your discussion privileges have been revoked")}
  end

  def handle_event("open_new_post", _params, socket) do
    selected_target = initial_category_target(socket.assigns)

    {:noreply,
     assign(socket,
       new_post_dialog_open: true,
       new_post_discard_open: false,
       new_post_form: @empty_new_post_form,
       new_post_errors: %{},
       new_post_selected_target: selected_target,
       new_post_target_query: "",
       new_post_target_results: target_results("", socket.assigns),
       new_post_target_picker_open: is_nil(selected_target),
       new_post_creating: false,
       new_post_error_message: nil,
       new_post_show_errors?: false
     )}
  end

  def handle_event("close_new_post", _params, socket) do
    if new_post_dirty?(socket.assigns) do
      {:noreply, assign(socket, :new_post_discard_open, true)}
    else
      {:noreply, close_new_post(socket)}
    end
  end

  def handle_event("discard_new_post", _params, socket) do
    {:noreply, close_new_post(socket)}
  end

  def handle_event("keep_editing_new_post", _params, socket) do
    {:noreply, assign(socket, :new_post_discard_open, false)}
  end

  def handle_event("open_category_target_picker", _params, socket) do
    {:noreply,
     assign(socket,
       new_post_target_picker_open: true,
       new_post_target_results:
         target_results(socket.assigns.new_post_target_query, socket.assigns)
     )}
  end

  def handle_event("search_category_targets", params, socket) do
    query = Map.get(params, "target_query") || Map.get(params, "value") || ""

    {:noreply,
     assign(socket,
       new_post_target_query: query,
       new_post_target_picker_open: true,
       new_post_target_results: target_results(query, socket.assigns)
     )}
  end

  def handle_event("clear_category_target", _params, socket) do
    {:noreply,
     assign(socket,
       new_post_selected_target: nil,
       new_post_target_query: "",
       new_post_target_picker_open: true,
       new_post_target_results: target_results("", socket.assigns)
     )}
  end

  def handle_event("select_category_target", params, socket) do
    target = %{
      category_type: params["category_type"],
      entity_id: blank_to_nil(params["entity_id"]),
      name: params["name"],
      slug: params["slug"],
      image_url: nil
    }

    {:noreply,
     assign(socket,
       new_post_selected_target: target,
       new_post_target_query: "",
       new_post_target_picker_open: false,
       new_post_error_message: nil,
       new_post_errors:
         if(socket.assigns.new_post_show_errors?,
           do: validate_new_post(socket.assigns.new_post_form, target),
           else: socket.assigns.new_post_errors
         )
     )}
  end

  def handle_event("validate_new_post", params, socket) do
    form = normalize_new_post_form(params)
    query = Map.get(form, "target_query", "")

    errors =
      if socket.assigns.new_post_show_errors? do
        validate_new_post(form, socket.assigns.new_post_selected_target)
      else
        %{}
      end

    socket =
      socket
      |> assign(
        new_post_form: form,
        new_post_errors: errors,
        new_post_target_query: query
      )

    socket =
      if is_nil(socket.assigns.new_post_selected_target) do
        assign(socket,
          new_post_target_picker_open: true,
          new_post_target_results: target_results(query, socket.assigns)
        )
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("submit_new_post", params, %{assigns: %{current_user: nil}} = socket) do
    {:noreply, assign(socket, :new_post_form, normalize_new_post_form(params))}
  end

  def handle_event("submit_new_post", params, %{assigns: %{can_discuss: false}} = socket) do
    {:noreply,
     socket
     |> assign(:new_post_form, normalize_new_post_form(params))
     |> push_toast(:error, "Your discussion privileges have been revoked")}
  end

  def handle_event("submit_new_post", params, socket) do
    form = normalize_new_post_form(params)
    selected_target = socket.assigns.new_post_selected_target
    errors = validate_new_post(form, selected_target)

    if errors != %{} do
      {:noreply,
       assign(socket,
         new_post_form: form,
         new_post_errors: errors,
         new_post_show_errors?: true
       )}
    else
      create_new_post(socket, form, selected_target)
    end
  end

  def handle_event("load_more_posts", _params, %{assigns: %{has_next: false}} = socket) do
    {:noreply, socket}
  end

  def handle_event("load_more_posts", _params, %{assigns: %{next_cursor: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("load_more_posts", _params, %{assigns: %{loading_more: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("load_more_posts", _params, socket) do
    category_type = socket.assigns.category && socket.assigns.category.type

    socket = assign(socket, :loading_more, true)

    case Data.load_more_posts(
           category_type,
           socket.assigns.sort,
           socket.assigns.next_cursor,
           socket.assigns.current_user
         ) do
      {:ok, payload} ->
        {:noreply,
         socket
         |> assign(:posts, socket.assigns.posts ++ payload.posts)
         |> assign(:has_next, payload.has_next)
         |> assign(:next_cursor, payload.next_cursor)
         |> assign(:loading_more, false)}

      _ ->
        {:noreply, assign(socket, :loading_more, false)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <div
        :if={@load_error?}
        class="text-foreground-secondary mx-auto mt-8 max-w-[1100px] px-4 text-sm lg:px-0"
      >
        Discussions could not be loaded. Please try again.
      </div>

      <NotFoundPage.not_found_page :if={@not_found?} variant={:overlay} />

      <IndexComponents.discussions_index
        :if={!@load_error? && !@not_found? && @live_action == :index}
        posts={@posts}
        pinned_posts={@pinned_posts}
        categories={@categories}
        current_user={@current_user}
        sort={@sort}
        has_next={@has_next}
        loading_more={@loading_more}
        can_discuss={@can_discuss}
        can_moderate_discussions={@can_moderate_discussions}
        active_slug={@active_slug}
      />

      <IndexComponents.discussions_category
        :if={!@load_error? && !@not_found? && @live_action == :category}
        posts={@posts}
        pinned_posts={@pinned_posts}
        category={@category}
        categories={@categories}
        current_user={@current_user}
        sort={@sort}
        has_next={@has_next}
        loading_more={@loading_more}
        can_discuss={@can_discuss}
        can_moderate_discussions={@can_moderate_discussions}
      />

      <IndexComponents.new_post_dialog
        open={@new_post_dialog_open}
        discard_open={@new_post_discard_open}
        form={@new_post_form}
        errors={@new_post_errors}
        selected_target={@new_post_selected_target}
        target_query={@new_post_target_query}
        target_results={@new_post_target_results}
        target_picker_open={@new_post_target_picker_open}
        creating={@new_post_creating}
        error_message={@new_post_error_message}
        show_errors?={@new_post_show_errors?}
      />

      <AuthPromptComponents.auth_prompt_modal
        id="discussions-auth-prompt"
        message="Sign in to start a discussion"
        return_to={@current_path}
      />
    </main>
    """
  end

  defp create_new_post(socket, form, selected_target) do
    current_user = socket.assigns.current_user
    category_type = category_type_atom(selected_target.category_type)

    attrs = %{
      title: String.trim(form["title"] || ""),
      content: blank_to_nil(form["content"]),
      category_type: category_type,
      entity_id: selected_target.entity_id
    }

    attrs =
      if is_nil(attrs.entity_id) do
        Map.delete(attrs, :entity_id)
      else
        attrs
      end

    socket = assign(socket, new_post_creating: true, new_post_error_message: nil)

    case Discussions.create_post(current_user.id, attrs, role: current_user.role) do
      {:ok, post} ->
        url = created_post_url(post, current_user)
        {:noreply, push_navigate(close_new_post(socket), to: url)}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           new_post_creating: false,
           new_post_error_message: new_post_error(reason)
         )}
    end
  end

  defp close_new_post(socket) do
    assign(socket,
      new_post_dialog_open: false,
      new_post_discard_open: false,
      new_post_form: @empty_new_post_form,
      new_post_errors: %{},
      new_post_selected_target: nil,
      new_post_target_query: "",
      new_post_target_results: [],
      new_post_target_picker_open: false,
      new_post_creating: false,
      new_post_error_message: nil,
      new_post_show_errors?: false
    )
  end

  defp initial_category_target(%{active_slug: nil} = assigns) do
    case Enum.find(assigns.categories, &(&1.type == :general)) do
      %{type: type} = category -> standalone_target(type, category)
      nil -> nil
    end
  end

  defp initial_category_target(assigns) do
    case Enum.find(assigns.categories, &(&1.slug == assigns.active_slug)) do
      %{admin_only: true} = category ->
        if assigns.can_moderate_discussions, do: standalone_target(category.type, category)

      %{type: type} = category when type in [:general, :announcements, :site_discussions] ->
        standalone_target(type, category)

      _category ->
        nil
    end
  end

  defp standalone_target(type, category) do
    %{
      category_type: type,
      entity_id: nil,
      name: category.name,
      slug: category.slug,
      image_url: nil
    }
  end

  defp target_results("", assigns), do: target_results(nil, assigns)

  defp target_results(nil, assigns) do
    user_id = assigns[:current_user] && assigns.current_user.id

    case Discussions.search_category_targets("") do
      {:ok, targets} ->
        vn_targets = Discussions.user_vn_targets(user_id)
        allowed = Enum.filter(targets, &allowed_target?(&1, assigns))
        allowed ++ vn_targets

      _ ->
        []
    end
  end

  defp target_results(query, assigns) do
    query
    |> Discussions.search_category_targets()
    |> case do
      {:ok, targets} -> Enum.filter(targets, &allowed_target?(&1, assigns))
      _ -> []
    end
  end

  defp allowed_target?(%{category_type: :announcements}, %{can_moderate_discussions: false}),
    do: false

  defp allowed_target?(_target, _assigns), do: true

  defp normalize_new_post_form(params) do
    %{
      "title" => Map.get(params, "title", ""),
      "content" => Map.get(params, "content", ""),
      "target_query" => Map.get(params, "target_query", "")
    }
  end

  defp validate_new_post(form, selected_target) do
    title = String.trim(form["title"] || "")
    content = form["content"] || ""

    %{}
    |> maybe_error(:target, is_nil(selected_target), "Select a topic")
    |> maybe_error(:title, String.length(title) < 3, "Title must be at least 3 characters")
    |> maybe_error(:title, String.length(title) > 200, "Title is too long")
    |> maybe_error(:content, String.length(content) > 20_000, "Content is too long")
  end

  defp maybe_error(errors, key, true, message), do: Map.put_new(errors, key, message)
  defp maybe_error(errors, _key, false, _message), do: errors

  defp new_post_dirty?(assigns) do
    form = assigns.new_post_form

    String.trim(form["title"] || "") != "" or String.trim(form["content"] || "") != "" or
      not is_nil(assigns.new_post_selected_target)
  end

  defp category_type_atom(value) when is_atom(value), do: value

  defp category_type_atom(value) when is_binary(value) do
    value
    |> String.replace("-", "_")
    |> String.to_existing_atom()
  end

  defp created_post_url(post, current_user) do
    case Data.load_post_page(post.short_id, current_user) do
      {:ok, %{post: %{url: url}}} -> url
      _ -> "/discussions/p/#{post.short_id}/#{post.slug || "post"}"
    end
  end

  defp discussions_path(nil, "recent"), do: "/discussions"
  defp discussions_path(nil, sort), do: "/discussions?sort=#{sort}"
  defp discussions_path(slug, "recent"), do: "/discussions/#{slug}"
  defp discussions_path(slug, sort), do: "/discussions/#{slug}?sort=#{sort}"

  defp new_post_error("Rate limit" <> _),
    do: "You can only create 5 posts per hour. Please try again later."

  defp new_post_error(%Ecto.Changeset{} = changeset), do: first_changeset_error(changeset)
  defp new_post_error(error) when is_binary(error), do: error
  defp new_post_error(_error), do: "Failed to create post"

  defp first_changeset_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.flat_map(fn {_field, messages} -> messages end)
    |> List.first()
    |> Kernel.||("Failed to create post")
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp push_toast(socket, variant, message) do
    push_event(socket, "toast", %{variant: Atom.to_string(variant), message: message})
  end
end
