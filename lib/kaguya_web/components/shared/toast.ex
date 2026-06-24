defmodule KaguyaWeb.SharedComponents.Toast do
  @moduledoc """
  Shared toast surface matching production's `showToast` visual contract.

  Server-rendered flashes use this component. LiveViews can also call
  `push_event(socket, "toast", %{variant: "success", message: "Saved"})` and
  the browser-side toast helper in `assets/js/app.js` will render the same UI.
  """

  use KaguyaWeb, :html

  alias Phoenix.LiveView.JS

  attr :flash, :map, required: true

  def flash_group(assigns) do
    ~H"""
    <div
      id="kaguya-toast-root"
      phx-hook="ToastRoot"
      class="kaguya-toast-root"
      aria-live="polite"
      aria-atomic="false"
    >
      <.toast
        :if={Phoenix.Flash.get(@flash, :info)}
        id="flash-info"
        kind={:info}
        variant="success"
        message={Phoenix.Flash.get(@flash, :info)}
      />
      <.toast
        :if={Phoenix.Flash.get(@flash, :error)}
        id="flash-error"
        kind={:error}
        variant="error"
        message={Phoenix.Flash.get(@flash, :error)}
        duration={5000}
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :kind, :atom, default: nil
  attr :variant, :string, default: "success", values: ["success", "error", "warning", "info"]
  attr :message, :string, required: true
  attr :description, :string, default: nil
  attr :duration, :integer, default: 3000

  def toast(assigns) do
    ~H"""
    <div
      id={@id}
      data-kaguya-toast
      data-duration={@duration}
      class={["kaguya-toast", "kaguya-toast-#{@variant}"]}
      role={if @variant == "error", do: "alert", else: "status"}
      phx-remove={@kind && JS.transition("closing", time: 240)}
    >
      <span class="kaguya-toast-icon">
        <.toast_icon variant={@variant} />
      </span>
      <span class="kaguya-toast-copy">
        <span class="kaguya-toast-title">{@message}</span>
        <span :if={@description} class="kaguya-toast-description">{@description}</span>
      </span>
      <button
        type="button"
        class="kaguya-toast-close"
        data-kaguya-toast-close
        aria-label="Dismiss"
        phx-click={
          @kind &&
            JS.add_class("closing", to: "##{@id}")
            |> JS.push("lv:clear-flash", value: %{key: Atom.to_string(@kind)})
        }
      >
        <.close_icon />
      </button>
    </div>
    """
  end

  attr :variant, :string, required: true

  defp toast_icon(%{variant: "success"} = assigns) do
    ~H"""
    <Lucide.check aria-hidden />
    """
  end

  defp toast_icon(%{variant: "error"} = assigns) do
    ~H"""
    <Lucide.circle_x aria-hidden />
    """
  end

  defp toast_icon(%{variant: "warning"} = assigns) do
    ~H"""
    <Lucide.triangle_alert aria-hidden />
    """
  end

  defp toast_icon(assigns) do
    ~H"""
    <Lucide.info aria-hidden />
    """
  end

  defp close_icon(assigns) do
    ~H"""
    <Lucide.x aria-hidden />
    """
  end
end
