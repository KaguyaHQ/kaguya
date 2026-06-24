defmodule KaguyaWeb.VNLive.Show.ReviewActions do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias KaguyaWeb.VNLive.PageData
  alias KaguyaWeb.VNLive.Show.Data

  # Minimum review length — kept in lockstep
  # with `Kaguya.Reviews.Review`'s server-side changeset so the user sees the
  # same minimum communicated by the inline error and the server.
  @min_review_length 40

  def toggle_review_like(socket, %{"review-id" => review_id}) do
    case socket.assigns.current_user do
      %{id: _} = user ->
        liked? = review_id in Data.liked_review_ids(socket.assigns.viewer_vn)

        optimistic_reviews =
          %{
            socket.assigns.reviews
            | items:
                Enum.map(socket.assigns.reviews.items, fn review ->
                  if to_string(review.id) == to_string(review_id) do
                    %{
                      review
                      | likes_count: max(0, review.likes_count + if(liked?, do: -1, else: 1)),
                        liked_by_me: !liked?
                    }
                  else
                    review
                  end
                end)
          }

        optimistic_bundle =
          update_in(socket.assigns.viewer_bundle, [:viewer_vn, :my_review_likes], fn ids ->
            if liked? do
              Enum.reject(ids, &(to_string(&1) == to_string(review_id)))
            else
              [review_id | ids]
            end
          end)

        socket =
          assign(socket,
            reviews: optimistic_reviews,
            viewer_bundle: optimistic_bundle,
            viewer_vn: optimistic_bundle.viewer_vn
          )

        case PageData.toggle_review_like(review_id, liked?, user) do
          {:ok, %{id: id, likes_count: lc, liked_by_me: lbm}} ->
            reviews =
              %{
                socket.assigns.reviews
                | items:
                    Enum.map(socket.assigns.reviews.items, fn review ->
                      if to_string(review.id) == to_string(id) do
                        %{review | likes_count: lc, liked_by_me: lbm}
                      else
                        review
                      end
                    end)
              }

            {:noreply, assign(socket, reviews: reviews)}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, inspect(reason))}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Sign in to like reviews")}
    end
  end

  def open_review_dialog(socket, _params) do
    case socket.assigns.current_user do
      %{id: _} ->
        form = build_review_form(socket)

        {:noreply,
         assign(socket,
           review_dialog_open: true,
           review_date_picker_open?: false,
           action_drawer_open: false,
           review_form: form,
           review_save_error: nil,
           review_min_length_error?: false
         )}

      _ ->
        {:noreply, put_flash(socket, :error, "Sign in to write a review")}
    end
  end

  # Tapping outside, Escape, or the X simply closes the editor. Nothing is lost:
  # the content textarea is mirrored to localStorage on every keystroke (see the
  # MarkdownEditor hook's `data-draft-key` persistence) and restored on reopen.
  # Throwing work away is an explicit, deliberate act — the "Delete review"
  # button — not an accident of dismissing a modal.
  def close_review_dialog(socket, _params), do: {:noreply, close_review_dialog(socket)}

  def update_review_form(socket, %{"review" => attrs}) do
    form = normalize_review_form(attrs)

    {:noreply,
     assign(socket,
       review_form: form,
       # Clear the min-length error once the user crosses the threshold.
       review_min_length_error?:
         Map.get(socket.assigns, :review_min_length_error?, false) and
           content_length(form) < @min_review_length
     )}
  end

  def set_review_form_rating(socket, %{"rating" => rating}) do
    form =
      socket.assigns.review_form
      |> normalize_review_form()
      |> Map.put("rating", rating)

    {:noreply, assign(socket, review_form: form)}
  end

  def apply_review_date_change(socket, %{date_started: started, date_finished: finished}) do
    form =
      socket.assigns.review_form
      |> normalize_review_form()
      |> Map.put("date_started", started || "")
      |> Map.put("date_finished", finished || "")

    {:noreply, assign(socket, review_form: form)}
  end

  def save_review(socket, %{"review" => attrs}) do
    form = normalize_review_form(attrs)
    length = content_length(form)

    case socket.assigns.current_user do
      %{id: _} = user ->
        # Don't round-trip to the
        # server when content is non-empty but under the minimum. Flag the
        # error so the inline message shows; the user can keep typing and
        # the error clears via `update_review_form` once they cross 40.
        if length > 0 and length < @min_review_length do
          {:noreply, assign(socket, review_min_length_error?: true, review_form: form)}
        else
          case PageData.save_review(socket.assigns.slug, user, form) do
            {:ok, bundle} ->
              socket =
                socket
                |> Data.assign_viewer_bundle(bundle)
                |> Data.refresh_reviews_section()
                |> close_review_dialog()

              {:noreply, socket}

            {:error, reason} ->
              {:noreply, assign(socket, review_save_error: Data.format_error(reason))}
          end
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Sign in to write a review")}
    end
  end

  defp content_length(form) when is_map(form),
    do: form |> Map.get("content", "") |> to_string() |> String.trim() |> String.length()

  defp content_length(_form), do: 0

  def delete_review(socket, _params) do
    with %{id: _} = user <- socket.assigns.current_user,
         %{id: review_id} <- get_in(socket.assigns, [:viewer_vn, :my_review]),
         {:ok, bundle} <- PageData.delete_review(socket.assigns.slug, user, review_id) do
      {:noreply,
       socket
       |> Data.assign_viewer_bundle(bundle)
       |> Data.refresh_reviews_section()
       |> close_review_dialog()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not delete review")}
    end
  end

  def build_review_form(socket) do
    my_review = get_in(socket.assigns, [:viewer_vn, :my_review])
    my_status = get_in(socket.assigns, [:viewer_vn, :my_reading_status])

    %{
      "content" => (my_review && my_review.content) || "",
      "is_spoiler" => (my_review && my_review.is_spoiler) || false,
      "status" => (my_status && my_status.status) || "READ",
      "rating" => rating_form_value(get_in(socket.assigns, [:viewer_vn, :my_rating])),
      "date_started" => date_form_value(my_status && my_status.date_started),
      "date_finished" => date_form_value(my_status && my_status.date_finished),
      "note" => (my_status && my_status.note) || ""
    }
  end

  def normalize_review_form(attrs) when is_map(attrs) do
    attrs
    |> Map.put_new("content", "")
    |> Map.put_new("note", "")
    |> Map.put_new("date_started", "")
    |> Map.put_new("date_finished", "")
    |> Map.put_new("status", "READ")
    |> Map.put_new("rating", "")
    |> Map.update("is_spoiler", false, &truthy?/1)
  end

  defp close_review_dialog(socket) do
    assign(socket,
      review_dialog_open: false,
      review_delete_dialog_open?: false,
      review_date_picker_open?: false,
      review_form: %{},
      review_save_error: nil,
      review_min_length_error?: false
    )
  end

  defp truthy?(value) when value in [true, "true", "on", "1", 1], do: true
  defp truthy?(_), do: false

  defp rating_form_value(nil), do: ""

  defp rating_form_value(value) when is_number(value),
    do: :erlang.float_to_binary(value * 1.0, decimals: 1)

  defp date_form_value(nil), do: ""
  defp date_form_value(%Date{} = date), do: Date.to_iso8601(date)
  defp date_form_value(value), do: to_string(value)
end
