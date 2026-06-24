defmodule KaguyaWeb.CharacterLive.Edit do
  use KaguyaWeb, :live_view

  alias Kaguya.Authorization
  alias Kaguya.Characters
  alias Kaguya.Revisions
  alias KaguyaWeb.Components.Shared.NotFoundPage

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(KaguyaWeb.SEO.noindex())
     |> assign(
       slug: nil,
       page_title: "Character editor",
       character: nil,
       state: :loading,
       can_moderate: false,
       form: empty_form()
     )}
  end

  @impl true
  def handle_params(_params, _uri, %{assigns: %{live_action: :new}} = socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply,
         assign(socket,
           slug: nil,
           character: nil,
           state: :auth_required,
           page_title: "New character",
           form: empty_form()
         )}

      current_user ->
        if can_edit?(current_user) do
          {:noreply,
           assign(socket,
             slug: nil,
             character: nil,
             state: :creating,
             can_moderate: Authorization.can_moderate_db?(current_user),
             page_title: "New character",
             form: empty_form()
           )}
        else
          {:noreply,
           assign(socket,
             slug: nil,
             character: nil,
             state: :forbidden,
             page_title: "New character"
           )}
        end
    end
  end

  @impl true
  def handle_params(%{"slug" => slug}, _uri, socket) do
    socket = assign(socket, :slug, slug)

    case socket.assigns.current_user do
      nil ->
        {:noreply, assign(socket, state: :auth_required)}

      current_user ->
        case Characters.get_character_page_by_slug(slug, current_user) do
          {:ok, page} ->
            can_moderate = Authorization.can_moderate_db?(current_user)

            cond do
              # Lock check first so non-mods on locked entries see the specific
              # reason instead of a generic "no permission." Mods bypass —
              # they unlock from the form's Moderation fieldset.
              page.character.is_locked and not can_moderate ->
                {:noreply,
                 assign(socket,
                   state: :locked,
                   character: page.character,
                   page_title: "#{page.character.name} · Edit"
                 )}

              !can_edit?(current_user) ->
                {:noreply,
                 assign(socket,
                   state: :forbidden,
                   character: page.character,
                   page_title: "#{page.character.name} · Edit"
                 )}

              true ->
                {:noreply,
                 assign(socket,
                   state: :editing,
                   character: page.character,
                   can_moderate: can_moderate,
                   page_title: "Edit #{page.character.name}",
                   form: form_from_character(page.character)
                 )}
            end

          {:error, :not_found} ->
            {:noreply,
             assign(socket,
               state: :not_found,
               page_title: "Character not found · Kaguya"
             )}
        end
    end
  end

  @impl true
  def handle_event("validate", %{"character" => attrs}, socket) do
    {:noreply, assign(socket, :form, normalize_form(attrs, socket.assigns.form))}
  end

  @impl true
  def handle_event("save", %{"character" => attrs}, socket) do
    form = normalize_form(attrs, socket.assigns.form)
    summary = form["summary"] |> ensure_summary(socket.assigns.live_action)

    case socket.assigns.live_action do
      :new ->
        attrs = %{
          name: form["name"],
          description: form["description"]
        }

        case Revisions.create_entity(:character, attrs, summary, socket.assigns.current_user) do
          {:ok, %{entity: character}} ->
            {:noreply,
             socket
             |> assign(form: form)
             |> put_flash(:info, "Character created.")
             |> push_navigate(to: "/character/#{character.slug}")}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:form, form)
             |> put_flash(:error, format_revision_error(reason))}
        end

      :edit ->
        changes =
          %{description: form["description"]}
          |> maybe_put_hidden_at(socket.assigns.character, form)
          |> maybe_put_is_locked(socket.assigns.character, form)

        case Revisions.submit_edit(
               :character,
               socket.assigns.character.id,
               changes,
               summary,
               socket.assigns.current_user
             ) do
          {:ok, _change} ->
            {:noreply,
             socket
             |> assign(form: form)
             |> put_flash(:info, "Character updated.")
             |> push_navigate(to: "/character/#{socket.assigns.slug}")}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:form, form)
             |> put_flash(:error, format_revision_error(reason))}
        end
    end
  end

  @impl true
  def render(%{state: :not_found} = assigns) do
    ~H"""
    <NotFoundPage.not_found_page variant={:overlay} />
    """
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto mt-6 max-w-[748px] px-4 pb-20 lg:mt-10 lg:px-0">
      <button
        :if={@live_action == :new}
        type="button"
        onclick="history.back()"
        class="hover:text-foreground-secondary text-foreground-tertiary text-style-captionRegular mb-8 inline-flex items-center gap-1.5 transition-colors"
      >
        ← Back
      </button>
      <.link
        :if={@live_action != :new}
        navigate={back_path(assigns)}
        class="hover:text-foreground-secondary text-foreground-tertiary text-style-captionRegular mb-8 inline-flex items-center gap-1.5 transition-colors"
      >
        ← {back_label(assigns)}
      </.link>

      <h1 class="text-foreground-primary text-style-heading2Medium mb-1">
        {heading(assigns)}
      </h1>

      <section
        :if={@state == :auth_required}
        class="bg-surface-base border-border-divider mt-6 rounded-[8px] border p-4 text-sm text-[rgb(var(--foreground-secondary))]"
      >
        {auth_message(assigns)}
      </section>

      <section
        :if={@state == :forbidden}
        class="bg-surface-base border-border-divider mt-6 rounded-[8px] border p-4 text-sm text-[rgb(var(--foreground-secondary))]"
      >
        {forbidden_message(assigns)}
      </section>

      <section
        :if={@state == :locked}
        class="bg-surface-base border-border-divider mt-6 rounded-[8px] border p-4 text-sm text-[rgb(var(--foreground-secondary))]"
      >
        This character is locked and cannot be edited.
      </section>

      <form
        :if={@state in [:editing, :creating]}
        id="character-edit"
        class="bg-surface-base border-border-divider mt-6 rounded-[8px] border p-4"
        phx-change="validate"
        phx-submit="save"
      >
        <div class="space-y-4">
          <label
            :if={@live_action == :new}
            class="flex flex-col gap-1.5 text-sm text-[rgb(var(--foreground-secondary))]"
          >
            <span class="font-medium text-[rgb(var(--foreground-primary))]">Name</span>
            <input
              type="text"
              name="character[name]"
              value={@form["name"]}
              maxlength="255"
              class="bg-surface-elevated border-border-divider rounded-[6px] border px-3 py-2 text-[rgb(var(--foreground-primary))] outline-none"
            />
          </label>

          <label
            :if={@live_action == :edit}
            class="flex flex-col gap-1.5 text-sm text-[rgb(var(--foreground-secondary))]"
          >
            <span class="font-medium text-[rgb(var(--foreground-primary))]">Character</span>
            <input
              type="text"
              value={@character.name}
              class="bg-surface-elevated border-border-divider rounded-[6px] border px-3 py-2 text-[rgb(var(--foreground-primary))] outline-none"
              readonly
            />
          </label>

          <label class="flex flex-col gap-1.5 text-sm text-[rgb(var(--foreground-secondary))]">
            <span class="font-medium text-[rgb(var(--foreground-primary))]">Description</span>
            <textarea
              name="character[description]"
              rows="8"
              maxlength="5000"
              class="bg-surface-elevated border-border-divider min-h-[180px] rounded-[6px] border px-3 py-2 text-[rgb(var(--foreground-primary))] outline-none"
            ><%= @form["description"] %></textarea>
          </label>

          <fieldset
            :if={@can_moderate and @live_action == :edit}
            class="space-y-3 rounded-[8px] border border-amber-500/20 bg-amber-500/6 p-3"
          >
            <legend class="px-1 text-xs font-medium tracking-[0.06em] text-amber-400 uppercase">
              Moderation
            </legend>

            <label class="flex items-start gap-2.5 text-sm text-[rgb(var(--foreground-secondary))]">
              <input type="hidden" name="character[is_hidden]" value="false" />
              <input
                type="checkbox"
                name="character[is_hidden]"
                value="true"
                checked={@form["is_hidden"]}
                class="bg-surface-elevated border-border-divider mt-0.5 size-4 rounded"
              />
              <span class="flex flex-col gap-0.5">
                <span class="font-medium text-[rgb(var(--foreground-primary))]">Hide entry</span>
                <span class="text-xs text-[rgb(var(--foreground-tertiary))]">
                  Removes from public lists and search. The audit summary doubles as the reason.
                </span>
              </span>
            </label>

            <label class="flex items-start gap-2.5 text-sm text-[rgb(var(--foreground-secondary))]">
              <input type="hidden" name="character[is_locked]" value="false" />
              <input
                type="checkbox"
                name="character[is_locked]"
                value="true"
                checked={@form["is_locked"]}
                class="bg-surface-elevated border-border-divider mt-0.5 size-4 rounded"
              />
              <span class="flex flex-col gap-0.5">
                <span class="font-medium text-[rgb(var(--foreground-primary))]">Lock entry</span>
                <span class="text-xs text-[rgb(var(--foreground-tertiary))]">
                  Prevents non-moderators from submitting further edits.
                </span>
              </span>
            </label>
          </fieldset>

          <label class="flex flex-col gap-1.5 text-sm text-[rgb(var(--foreground-secondary))]">
            <span class="font-medium text-[rgb(var(--foreground-primary))]">Summary</span>
            <input
              type="text"
              name="character[summary]"
              value={@form["summary"]}
              placeholder="Brief change summary"
              minlength="2"
              maxlength="5000"
              class="bg-surface-elevated border-border-divider rounded-[6px] border px-3 py-2 text-[rgb(var(--foreground-primary))] outline-none"
            />
          </label>

          <button
            type="submit"
            class="rounded-[6px] border border-[rgb(var(--chip-border-default))] px-3 py-2 text-sm text-[rgb(var(--foreground-primary))] transition-colors hover:border-[rgb(var(--chip-border-hover))]"
          >
            {submit_label(assigns)}
          </button>
        </div>
      </form>
    </div>
    """
  end

  defp can_edit?(%{can_edit: false}), do: false
  defp can_edit?(%{id: _}), do: true
  defp can_edit?(_), do: false

  defp normalize_text(nil), do: ""
  defp normalize_text(value), do: String.trim(to_string(value))

  defp empty_form do
    %{
      "name" => "",
      "description" => "",
      "summary" => "",
      "is_hidden" => false,
      "is_locked" => false
    }
  end

  defp form_from_character(character) do
    %{
      "name" => character.name,
      "description" => character.description || "",
      "summary" => "",
      "is_hidden" => not is_nil(character.hidden_at),
      "is_locked" => character.is_locked || false
    }
  end

  defp normalize_form(attrs, current_form) do
    %{
      "name" => normalize_text(Map.get(attrs, "name", current_form["name"])),
      "description" => normalize_text(Map.get(attrs, "description", current_form["description"])),
      "summary" => normalize_text(Map.get(attrs, "summary", current_form["summary"])),
      "is_hidden" => truthy?(Map.get(attrs, "is_hidden", Map.get(current_form, "is_hidden"))),
      "is_locked" => truthy?(Map.get(attrs, "is_locked", Map.get(current_form, "is_locked")))
    }
  end

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?("on"), do: true
  defp truthy?(_), do: false

  # Mirrors the producer Edit form. The server-side sanitize in
  # `Kaguya.Revisions.submit_edit/6` is the actual permission boundary; this
  # only avoids sending no-op changes for non-mods.
  defp maybe_put_hidden_at(changes, character, form) do
    new_value = Map.get(form, "is_hidden")
    current_value = not is_nil(character.hidden_at)

    if new_value != current_value do
      Map.put(changes, :hidden_at, hidden_at_value(new_value))
    else
      changes
    end
  end

  defp maybe_put_is_locked(changes, character, form) do
    new_value = Map.get(form, "is_locked")

    if new_value != (character.is_locked || false) do
      Map.put(changes, :is_locked, new_value)
    else
      changes
    end
  end

  defp hidden_at_value(true), do: DateTime.utc_now() |> DateTime.truncate(:second)
  defp hidden_at_value(_), do: nil

  defp ensure_summary("", :new), do: "Created character"
  defp ensure_summary("", _action), do: "Updated character"
  defp ensure_summary(summary, _action), do: summary

  defp heading(%{live_action: :new}), do: "Create character"
  defp heading(_assigns), do: "Edit character"

  defp submit_label(%{live_action: :new}), do: "Create character"
  defp submit_label(_assigns), do: "Save changes"

  defp auth_message(%{live_action: :new}), do: "Sign in to create a character."
  defp auth_message(_assigns), do: "Sign in to edit this character."

  defp forbidden_message(%{live_action: :new}),
    do: "You do not have permission to create characters."

  defp forbidden_message(_assigns), do: "You do not have permission to edit this character."

  defp back_path(%{slug: slug}), do: "/character/#{slug}"

  defp back_label(_assigns), do: "Back to character"

  defp format_revision_error({:error, reason}), do: format_revision_error(reason)
  defp format_revision_error(reason) when is_binary(reason), do: reason
  defp format_revision_error(%Ecto.Changeset{} = changeset), do: format_changeset_error(changeset)
  defp format_revision_error(_), do: "Unable to save character."

  defp format_changeset_error(changeset) do
    Enum.map_join(changeset.errors, ", ", fn {field, {message, _opts}} ->
      "#{field} #{message}"
    end)
  end
end
