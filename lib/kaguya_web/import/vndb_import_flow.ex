defmodule KaguyaWeb.Import.VndbImportFlow do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias Kaguya.{Repo, Uploads, Users}
  alias Kaguya.Users.VndbImport

  @poll_interval 2_000
  @finish_delay 400
  @completion_frame_ms 50

  def init(socket) do
    socket
    |> assign(:import, nil)
    |> assign(:import_topic, nil)
    |> assign(:import_error, nil)
    |> assign(:import_ui_status, :not_selected)
    |> assign(:import_progress, 0)
    |> assign(:selected_file_name, nil)
  end

  def poll_import(socket) do
    import = socket.assigns.import && Repo.get(VndbImport, socket.assigns.import.id)

    cond do
      is_nil(import) ->
        {:noreply, assign(socket, :import, nil)}

      import.status in ["pending", "processing"] ->
        Process.send_after(self(), :poll_import, @poll_interval)
        {:noreply, assign(socket, :import, import)}

      import.status == "completed" ->
        {:noreply, complete_import(socket, import)}

      true ->
        {:noreply,
         socket
         |> assign(:import, import)
         |> assign(:import_ui_status, :failed)
         |> assign(:import_error, failed_message(import))}
    end
  end

  def import_updated(socket, %VndbImport{} = import) do
    cond do
      stale_import_update?(socket, import) ->
        {:noreply, socket}

      import.status in ["pending", "processing"] ->
        {:noreply, assign(socket, :import, import)}

      import.status == "completed" ->
        {:noreply, complete_import(socket, import)}

      true ->
        {:noreply,
         socket
         |> assign(:import, import)
         |> assign(:import_ui_status, :failed)
         |> assign(:import_error, failed_message(import))}
    end
  end

  def import_enqueued(socket, {:ok, %VndbImport{} = import}) do
    socket = subscribe_import(socket, import.id)
    Process.send_after(self(), :poll_import, @poll_interval)

    {:noreply,
     socket
     |> assign(:import, import)
     |> assign(:import_error, nil)
     |> schedule_progress_tick()}
  end

  def import_enqueued(socket, {:error, reason}) do
    {:noreply,
     socket
     |> assign(:import_ui_status, :failed)
     |> assign(:import_error, reason)
     |> assign(:import_progress, 0)}
  end

  def progress_tick(socket) do
    if socket.assigns.import_ui_status == :importing && socket.assigns.import_progress < 95 do
      progress = min(socket.assigns.import_progress + 1, 95)

      {:noreply,
       socket
       |> assign(:import_progress, progress)
       |> schedule_progress_tick()}
    else
      {:noreply, socket}
    end
  end

  def completion_tick(socket, import_id, from, step, steps) do
    if current_import_id?(socket, import_id) && socket.assigns.import_ui_status == :importing do
      socket = assign(socket, :import_progress, completion_progress(from, step, steps))

      if step >= steps do
        Process.send_after(self(), {:finish_import, import_id}, @finish_delay)
        {:noreply, socket}
      else
        Process.send_after(
          self(),
          {:complete_import_progress_tick, import_id, from, step + 1, steps},
          @completion_frame_ms
        )

        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def select_file(socket, %{"name" => name, "size" => size}) do
    error = selection_upload_error_message(name, int_size(size))

    cond do
      is_binary(error) ->
        socket
        |> assign(:import_ui_status, :failed)
        |> assign(:import_error, error)
        |> assign(:selected_file_name, name)

      is_binary(name) and name != "" ->
        socket
        |> assign(:import_ui_status, :selected)
        |> assign(:import_error, nil)
        |> assign(:selected_file_name, name)

      true ->
        socket
        |> assign(:import_ui_status, :not_selected)
        |> assign(:import_error, nil)
        |> assign(:selected_file_name, nil)
    end
  end

  def request_upload(socket, %{"name" => name, "size" => size}) do
    size = int_size(size)

    case selection_upload_error_message(name, size) do
      nil ->
        case Uploads.generate_upload_url() do
          {:ok, %{upload_url: upload_url, upload_id: upload_id}} ->
            {:reply, %{ok: true, upload_url: upload_url, upload_id: upload_id},
             mark_importing(socket, name)}

          {:error, reason} ->
            message = format_task_error(reason)

            {:reply, %{ok: false, error: message},
             socket
             |> assign(:import_ui_status, :failed)
             |> assign(:import_error, message)
             |> assign(:import_progress, 0)}
        end

      message ->
        {:reply, %{ok: false, error: message},
         socket
         |> assign(:import_ui_status, :failed)
         |> assign(:import_error, message)
         |> assign(:selected_file_name, name)
         |> assign(:import_progress, 0)}
    end
  end

  def file_error(socket, message) when is_binary(message) do
    socket
    |> assign(:import_ui_status, :failed)
    |> assign(:import_error, message)
    |> assign(:import_progress, 0)
  end

  def start_import(socket, user_id, %{"upload_id" => upload_id} = params)
      when is_binary(upload_id) and upload_id != "" do
    file_name = Map.get(params, "name") || socket.assigns.selected_file_name

    case Users.enqueue_vndb_import(upload_id, user_id) do
      {:ok, %VndbImport{} = import} ->
        socket = subscribe_import(socket, import.id)
        Process.send_after(self(), :poll_import, @poll_interval)

        socket
        |> assign(:import, import)
        |> assign(:selected_file_name, file_name)
        |> assign(:import_error, nil)
        |> assign(:import_ui_status, :importing)
        |> assign(:import_progress, max(socket.assigns.import_progress, 1))
        |> schedule_progress_tick()

      {:error, reason} ->
        socket
        |> assign(:import_ui_status, :failed)
        |> assign(:import_error, format_task_error(reason))
        |> assign(:import_progress, 0)
    end
  end

  def start_import(socket, _user_id, _params) do
    socket
    |> assign(:import_ui_status, :failed)
    |> assign(:import_error, "Choose a file first.")
    |> assign(:import_progress, 0)
  end

  def reset(socket) do
    socket
    |> unsubscribe()
    |> assign(:import, nil)
    |> assign(:import_error, nil)
    |> assign(:import_ui_status, :not_selected)
    |> assign(:import_progress, 0)
    |> assign(:selected_file_name, nil)
  end

  def unsubscribe(%{assigns: %{import_topic: topic}} = socket) when is_binary(topic) do
    Phoenix.PubSub.unsubscribe(Kaguya.PubSub, topic)
    assign(socket, :import_topic, nil)
  end

  def unsubscribe(socket), do: socket

  defp mark_importing(%{assigns: %{import_ui_status: :importing}} = socket, file_name) do
    socket
    |> assign(:selected_file_name, file_name)
    |> assign(:import_error, nil)
  end

  defp mark_importing(socket, file_name) do
    socket
    |> assign(:selected_file_name, file_name)
    |> assign(:import_error, nil)
    |> assign(:import_ui_status, :importing)
    |> assign(:import_progress, 1)
    |> schedule_progress_tick()
  end

  defp selection_upload_error_message(name, size) do
    cond do
      too_large_size?(size) -> upload_error_to_string(:too_large)
      not xml_file_name?(name) -> upload_error_to_string(:not_accepted)
      true -> nil
    end
  end

  defp too_large_size?(size) when is_integer(size), do: size > Uploads.max_vndb_xml_bytes()
  defp too_large_size?(_size), do: false

  defp xml_file_name?(name) when is_binary(name),
    do: String.downcase(Path.extname(name)) == ".xml"

  defp xml_file_name?(_name), do: false

  defp upload_error_to_string(:too_large), do: "This XML file is larger than the upload limit."
  defp upload_error_to_string(:not_accepted), do: "Please upload an XML file exported from VNDB."

  defp int_size(size) when is_integer(size), do: size

  defp int_size(size) when is_binary(size) do
    case Integer.parse(size) do
      {value, _rest} -> value
      :error -> 0
    end
  end

  defp int_size(_size), do: 0

  defp schedule_progress_tick(socket) do
    Process.send_after(
      self(),
      :import_progress_tick,
      progress_delay(socket.assigns.import_progress)
    )

    socket
  end

  defp progress_delay(progress) when progress < 40, do: 250
  defp progress_delay(progress) when progress < 70, do: 500
  defp progress_delay(progress) when progress < 85, do: 1_000
  defp progress_delay(_progress), do: 2_000

  defp subscribe_import(socket, import_id) do
    socket = unsubscribe(socket)
    topic = "vndb_import:#{import_id}"

    Phoenix.PubSub.subscribe(Kaguya.PubSub, topic)
    assign(socket, :import_topic, topic)
  end

  defp stale_import_update?(%{assigns: %{import: %VndbImport{id: active_id}}}, %VndbImport{id: id}),
       do: id != active_id

  defp stale_import_update?(_socket, _import), do: false

  defp current_import_id?(%{assigns: %{import: %VndbImport{id: active_id}}}, id),
    do: active_id == id

  defp current_import_id?(_socket, _id), do: false

  defp format_task_error(%Ecto.Changeset{} = changeset), do: first_changeset_error(changeset)
  defp format_task_error(reason) when is_binary(reason), do: reason
  defp format_task_error(reason), do: inspect(reason)

  defp complete_import(socket, import) do
    socket
    |> assign(:import, import)
    |> assign(:import_ui_status, :importing)
    |> schedule_completion_progress(import.id)
  end

  defp schedule_completion_progress(socket, import_id) do
    from = min(socket.assigns.import_progress, 99)
    gap = 100 - from
    duration = max(600, min(2_200, round(gap * 35)))
    steps = max(1, div(duration, @completion_frame_ms))

    Process.send_after(
      self(),
      {:complete_import_progress_tick, import_id, from, 1, steps},
      @completion_frame_ms
    )

    socket
  end

  defp completion_progress(from, step, steps) do
    eased = ease_in_out(step / steps)
    min(100, round(from + (100 - from) * eased))
  end

  defp ease_in_out(t) when t < 0.5, do: 2 * t * t
  defp ease_in_out(t), do: 1 - :math.pow(-2 * t + 2, 2) / 2

  defp first_changeset_error(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.flat_map(fn {_field, messages} -> messages end)
    |> List.first()
    |> Kernel.||("Something went wrong. Please try again.")
  end

  defp first_changeset_error(_), do: "Something went wrong. Please try again."
  defp failed_message(%VndbImport{status: "failed", error_message: message}), do: message
  defp failed_message(_), do: nil
end
