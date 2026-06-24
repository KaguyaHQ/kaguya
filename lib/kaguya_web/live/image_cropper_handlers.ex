defmodule KaguyaWeb.ImageCropperHandlers do
  @moduledoc """
  Shared LiveView handlers for `<.image_cropper>`. Adds two `handle_event/3`
  clauses so the parent can stay focused on its own state.

      use KaguyaWeb.ImageCropperHandlers

  Behaviour:

    * `"request-image-upload"` → replies with `{upload_url, upload_id}` from
      `Kaguya.Uploads.generate_upload_url/0` so the browser can PUT directly.
    * `"image-uploaded"` → enqueues variant generation via
      `Kaguya.Uploads.process_image_upload/3`, then forwards the event to the
      LiveView via `handle_info({:image_uploaded, image_type, upload_id}, ...)`
      so callers can update their own assigns (preview URL, "ready" flag, etc.)
      without coupling to upload internals.

  The current user is resolved as `socket.assigns[:current_user]` first, then
  `socket.assigns[:user]` to cover both onboarding and edit-profile naming.
  Override `__image_cropper_user__/1` if a different lookup is needed. Override
  `__image_cropper_uploaded__/3` when a LiveView wants to store the staged
  upload ID and commit it later instead of immediately processing it. Override
  `__image_cropper_upload_failed__/3` when upload failures need local state
  cleanup.
  """

  defmacro __using__(_opts) do
    quote do
      @impl true
      def handle_event("image-cropped", %{"image_type" => image_type_str}, socket) do
        image_type = String.to_existing_atom(image_type_str)
        send(self(), {:image_cropped, image_type})
        {:noreply, socket}
      end

      def handle_event("request-image-upload", _params, socket) do
        case Kaguya.Uploads.generate_upload_url() do
          {:ok, %{upload_url: url, upload_id: id}} ->
            {:reply, %{upload_url: url, upload_id: id}, socket}

          {:error, reason} ->
            {:reply, %{error: to_string(reason)}, socket}
        end
      end

      def handle_event(
            "image-uploaded",
            %{"upload_id" => upload_id, "image_type" => image_type_str},
            socket
          ) do
        image_type = String.to_existing_atom(image_type_str)

        __image_cropper_uploaded__(socket, image_type, upload_id)
      end

      def handle_event("image-upload-failed", params, socket) do
        image_type = String.to_existing_atom(params["image_type"])
        message = params["message"] || "Upload failed. Try again."

        __image_cropper_upload_failed__(socket, image_type, message)
      end

      def __image_cropper_uploaded__(socket, image_type, upload_id) do
        user = __image_cropper_user__(socket)

        case Kaguya.Uploads.process_image_upload(upload_id, image_type, user.id) do
          {:ok, _} ->
            send(self(), {:image_uploaded, image_type, upload_id})
            {:noreply, socket}

          {:error, reason} ->
            {:noreply, Phoenix.LiveView.put_flash(socket, :error, to_string(reason))}
        end
      end

      def __image_cropper_upload_failed__(socket, _image_type, message) do
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, message)}
      end

      defp __image_cropper_user__(socket) do
        socket.assigns[:current_user] || socket.assigns[:user]
      end

      defoverridable __image_cropper_user__: 1,
                     __image_cropper_uploaded__: 3,
                     __image_cropper_upload_failed__: 3
    end
  end
end
