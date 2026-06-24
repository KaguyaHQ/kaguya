defmodule KaguyaWeb.AuthLive.AccountSetup do
  use KaguyaWeb, :live_view
  on_mount {KaguyaWeb.UserAuth, :default}

  use KaguyaWeb.ImageCropperHandlers

  import KaguyaWeb.AuthComponents, only: [logo: 1]
  import KaguyaWeb.Import.VndbImportComponents
  import KaguyaWeb.UI.Button, only: [button: 1]
  import KaguyaWeb.UI.ImageCropper, only: [image_cropper: 1]
  import KaguyaWeb.UI.Input, only: [input: 1]

  alias Kaguya.Users
  alias KaguyaWeb.Import.VndbImportFlow

  @impl true
  def mount(params, session, socket) do
    params = normalize_params(params)
    return_to = safe_return_to(params["return_to"] || session["signup_return_to"])
    current_user = socket.assigns.current_user

    socket =
      socket
      |> assign(:hide_navbar, true)
      |> assign(:hide_footer, true)
      |> assign(:step, 1)
      |> assign(:return_to, return_to)
      |> assign(:name_form, name_form(current_user))
      |> assign(:avatar_ready, false)
      |> assign(:avatar_upload_id, nil)
      |> assign(:show_import_instructions, true)
      |> VndbImportFlow.init()

    if is_nil(current_user) do
      {:ok, redirect(socket, to: ~p"/signup")}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_info(:poll_import, socket) do
    VndbImportFlow.poll_import(socket)
  end

  def handle_info({:finish_import, import_id}, socket) do
    {:noreply,
     socket
     |> VndbImportFlow.unsubscribe()
     |> push_navigate(to: ~p"/account/import/summary?import_id=#{import_id}")}
  end

  def handle_info({:vndb_import_updated, import}, socket) do
    VndbImportFlow.import_updated(socket, import)
  end

  def handle_info({:vndb_import_enqueued, result}, socket) do
    VndbImportFlow.import_enqueued(socket, result)
  end

  def handle_info(:import_progress_tick, socket) do
    VndbImportFlow.progress_tick(socket)
  end

  def handle_info({:complete_import_progress_tick, import_id, from, step, steps}, socket) do
    VndbImportFlow.completion_tick(socket, import_id, from, step, steps)
  end

  def handle_info({:image_cropped, :avatar}, socket) do
    {:noreply, assign(socket, :avatar_ready, true)}
  end

  def handle_info({:image_uploaded, :avatar, upload_id}, socket) do
    {:noreply, assign(socket, :avatar_upload_id, upload_id)}
  end

  @impl true
  def handle_event("validate-name", %{"setup" => %{"display_name" => display_name}}, socket) do
    {:noreply, assign(socket, :name_form, name_form(%{"display_name" => display_name}))}
  end

  def handle_event("save-name", %{"setup" => %{"display_name" => display_name}}, socket) do
    case Users.update_user(socket.assigns.current_user.id, %{display_name: display_name}) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:current_user, user_map(user))
         |> assign(:name_form, name_form(user))
         |> assign(:step, 2)}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:name_form, name_form(%{"display_name" => display_name}))
         |> put_flash(:error, first_changeset_error(changeset))}
    end
  end

  def handle_event("skip", _params, %{assigns: %{step: 3}} = socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Welcome to Kaguya! Start by adding your first visual novel.")
     |> push_navigate(to: socket.assigns.return_to)}
  end

  def handle_event("skip", _params, socket) do
    {:noreply, update(socket, :step, &min(&1 + 1, 3))}
  end

  def handle_event("avatar-next", _params, socket) do
    {:noreply, assign(socket, :step, 3)}
  end

  def handle_event("show-import-upload", _params, socket) do
    {:noreply, assign(socket, :show_import_instructions, false)}
  end

  def handle_event(
        "continue-import",
        _params,
        %{assigns: %{show_import_instructions: true}} = socket
      ) do
    {:noreply, assign(socket, :show_import_instructions, false)}
  end

  def handle_event("continue-import", _params, %{assigns: %{import_ui_status: :failed}} = socket) do
    {:noreply,
     socket
     |> VndbImportFlow.reset()
     |> assign(:show_import_instructions, false)}
  end

  def handle_event(
        "continue-import",
        _params,
        %{assigns: %{import_ui_status: :selected}} = socket
      ) do
    {:noreply,
     push_event(socket, "kaguya:submit-form", %{selector: "#account-setup-import-form"})}
  end

  def handle_event("continue-import", _params, socket), do: {:noreply, socket}

  def handle_event("reset-import", _params, socket) do
    {:noreply,
     socket
     |> VndbImportFlow.reset()
     |> assign(:show_import_instructions, false)}
  end

  def handle_event("select-import-file", params, socket) do
    {:noreply, VndbImportFlow.select_file(socket, params)}
  end

  def handle_event("request-import-upload", params, socket) do
    VndbImportFlow.request_upload(socket, params)
  end

  def handle_event("import-file-error", %{"message" => message}, socket) do
    {:noreply, VndbImportFlow.file_error(socket, message)}
  end

  def handle_event("start-import", params, socket) do
    {:noreply, VndbImportFlow.start_import(socket, socket.assigns.current_user.id, params)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.image_cropper id="onboarding-avatar-cropper" variant="profile" image_type={:avatar} />
    <div class="bg-surface-base text-foreground-primary relative flex min-h-dvh justify-center max-lg:min-h-[468px]">
      <div class={[
        "w-full px-5 py-10 max-lg:pb-10 lg:px-10 lg:pt-[68px]",
        @step == 3 && !@show_import_instructions && "max-w-[680px]",
        (@step != 3 || @show_import_instructions) && "max-w-[600px]"
      ]}>
        <div class={[
          "flex w-full flex-col pb-0 lg:mx-auto",
          @step == 3 && !@show_import_instructions && "",
          @step == 3 && @show_import_instructions && "lg:max-w-[370px]",
          @step in [1, 2] && "lg:max-w-[360px]"
        ]}>
          <div>
            <.logo
              class="max-lg:hidden lg:absolute lg:top-0 lg:left-0 lg:mt-6 lg:w-full lg:px-8"
              small
            />
            <div class="mt-4 mb-6 lg:mt-0 lg:mb-[110px]">
              <div class="flex items-center gap-2 sm:gap-2.5 lg:mx-auto lg:max-w-[250px]">
                <div class="h-2 w-full overflow-hidden rounded-full bg-white/6 max-sm:h-1.5">
                  <div
                    class="bg-button-background-brand-default h-full rounded-l-[100px] rounded-r-[100px] transition-all duration-700 ease-in-out"
                    style={"width: #{progress(@step)}%"}
                  />
                </div>
              </div>
            </div>
          </div>

          <div class="flex flex-col justify-between gap-[22px] lg:flex-1 lg:justify-start lg:gap-[56px]">
            <div class={[
              "relative w-full overflow-x-clip overflow-y-visible transition-all duration-300 ease-out",
              !(@step == 3 && !@show_import_instructions) && "max-w-[500px]"
            ]}>
              <%= case @step do %>
                <% 1 -> %>
                  <section class="step-section">
                    <h1 class="text-foreground-primary mb-2 text-xl/6 font-semibold max-sm:mb-1.5 sm:text-[28px]/9 lg:mb-4 lg:text-[32px] lg:leading-[32px] lg:whitespace-nowrap">
                      What should we call you?
                    </h1>
                    <p class="text-foreground-secondary mb-7 text-sm font-normal max-sm:leading-[150%] sm:mb-9 sm:text-base lg:text-[14px] lg:leading-[20px]">
                      Pick a display name
                    </p>
                    <.form
                      for={@name_form}
                      id="account-setup-form"
                      phx-change="validate-name"
                      phx-submit="save-name"
                      class="space-y-4 sm:space-y-6"
                    >
                      <.input
                        field={@name_form[:display_name]}
                        type="text"
                        placeholder="RedCake"
                        autocomplete="nickname"
                        autofocus
                        class="dark:bg-surface-elevated dark:lg:bg-text-field-bg focus:border-text-field-border-focus lg:bg-text-field-bg lg:border-text-field-border lg:text-foreground-secondary max-sm:border-border-divider placeholder:text-text-field-placeholder-text text-foreground-primary h-11 w-full rounded-[8px] px-4 py-2.5 text-base font-normal outline-hidden transition-colors focus:placeholder:text-transparent max-sm:h-12 max-sm:rounded-[6px] max-sm:border max-sm:text-sm sm:border-none lg:h-auto lg:rounded-[4px] lg:border lg:border-solid lg:px-[10px] lg:py-3 max-sm:dark:bg-white/2"
                      />
                    </.form>
                  </section>
                <% 2 -> %>
                  <section class="step-section">
                    <h1 class="text-foreground-primary mb-2 text-xl/6 font-semibold max-sm:mb-1.5 sm:text-[28px]/9 lg:mb-4 lg:text-[32px] lg:leading-[32px] lg:whitespace-nowrap">
                      Add a profile picture
                    </h1>
                    <p class="text-foreground-secondary mb-7 text-sm font-normal max-sm:leading-[150%] sm:mb-9 sm:text-base lg:mb-[52px] lg:text-[14px] lg:leading-[20px]">
                      This is what others see on your profile and reviews
                    </p>
                    <div class="flex flex-col items-center gap-4 max-lg:mb-[18px]">
                      <div
                        class="relative size-[170px] cursor-pointer rounded-full sm:size-[140px] lg:size-[100px]"
                        phx-click={
                          Phoenix.LiveView.JS.dispatch("kaguya:open-image-cropper",
                            detail: %{id: "onboarding-avatar-cropper"}
                          )
                        }
                      >
                        <img
                          id="onboarding-avatar-preview"
                          phx-update="ignore"
                          data-cropper-preview="avatar"
                          src="https://images.kaguya.io/users/avatars/5a3c374d-edb3-48c5-8424-bcd2c72129a9-360w.webp"
                          alt="Default avatar"
                          class="size-full rounded-full object-cover"
                        />
                        <span class="bg-foreground-primary absolute right-2 bottom-0 grid size-5 place-items-center rounded-full max-lg:right-3 max-lg:bottom-2 max-lg:size-6">
                          <Lucide.plus class="text-surface-base size-3.5 max-lg:size-4" aria-hidden />
                        </span>
                      </div>
                    </div>
                  </section>
                <% 3 -> %>
                  <section class={[
                    "step-section flex w-full flex-col",
                    !@show_import_instructions && "items-center"
                  ]}>
                    <%= if @show_import_instructions do %>
                      <.instructions />
                    <% else %>
                      <form id="account-setup-import-form" class="contents">
                        <.dropzone
                          status={@import_ui_status}
                          file_name={@selected_file_name}
                          error={@import_error}
                          progress={@import_progress}
                          input_id="account-setup-vndb-file"
                          show_actions={false}
                        />
                      </form>
                    <% end %>
                  </section>
              <% end %>
            </div>

            <div class="w-full lg:flex lg:justify-end">
              <div class="flex flex-col-reverse items-center justify-end gap-2 lg:flex-row lg:gap-5">
                <%= if @step > 1 do %>
                  <button
                    id="account-setup-skip"
                    type="button"
                    phx-click="skip"
                    class="hover:text-foreground-tertiary text-foreground-quaternary hidden text-sm font-light whitespace-nowrap transition-colors lg:block"
                  >
                    Skip for now
                  </button>
                  <button
                    id="account-setup-mobile-skip"
                    type="button"
                    phx-click="skip"
                    class="text-foreground-primary text-style-body2Medium h-12 w-full rounded-[8px] bg-white/6 transition-colors hover:bg-white/8 lg:hidden"
                  >
                    Skip
                  </button>
                <% end %>

                <%= case @step do %>
                  <% 1 -> %>
                    <.button
                      id="account-setup-name-submit"
                      type="submit"
                      variant="brand"
                      class="w-full lg:w-fit"
                      disabled={!name_ready?(@name_form)}
                      form="account-setup-form"
                    >
                      Continue
                    </.button>
                  <% 2 -> %>
                    <.button
                      id="account-setup-avatar-submit"
                      type="button"
                      variant="brand"
                      class="w-full lg:w-fit"
                      disabled={!@avatar_ready}
                      phx-click="avatar-next"
                    >
                      <span class="max-lg:hidden">Continue</span>
                      <span class="lg:hidden">
                        {if @avatar_ready, do: "Continue", else: "Add picture"}
                      </span>
                    </.button>
                  <% 3 -> %>
                    <.button
                      id="account-setup-import-primary"
                      type="button"
                      variant="brand"
                      class="w-full lg:w-fit"
                      phx-click="continue-import"
                      disabled={
                        import_primary_disabled?(@show_import_instructions, @import_ui_status)
                      }
                    >
                      {import_primary_label(@show_import_instructions, @import_ui_status)}
                    </.button>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp name_form(nil), do: to_form(%{"display_name" => ""}, as: :setup)

  defp name_form(%Users.User{} = user),
    do: to_form(%{"display_name" => user.display_name || ""}, as: :setup)

  defp name_form(user) when is_map(user),
    do:
      to_form(
        %{"display_name" => Map.get(user, :display_name) || Map.get(user, "display_name") || ""},
        as: :setup
      )

  defp name_ready?(form) do
    form[:display_name].value
    |> to_string()
    |> String.trim()
    |> Kernel.!=("")
  end

  defp import_primary_label(true, _status), do: "I have my export file"
  defp import_primary_label(false, :failed), do: "Try again"
  defp import_primary_label(false, :selected), do: "Start Importing"
  defp import_primary_label(false, _status), do: "Continue"

  defp import_primary_disabled?(true, _status), do: false
  defp import_primary_disabled?(false, status), do: status in [:not_selected, :importing]

  defp first_changeset_error(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.flat_map(fn {_field, messages} -> messages end)
    |> List.first()
    |> Kernel.||("Something went wrong. Please try again.")
  end

  defp first_changeset_error(_), do: "Something went wrong. Please try again."

  defp progress(1), do: 33
  defp progress(2), do: 66
  defp progress(_), do: 100

  defp normalize_params(:not_mounted_at_router), do: %{}
  defp normalize_params(params) when is_map(params), do: params
  defp normalize_params(_), do: %{}

  defp user_map(%Users.User{} = user), do: user |> Map.from_struct() |> Map.drop([:__meta__])

  defp safe_return_to(path) when is_binary(path) do
    if String.starts_with?(path, "/") and not String.starts_with?(path, "//"), do: path, else: "/"
  end

  defp safe_return_to(_), do: "/"
end
