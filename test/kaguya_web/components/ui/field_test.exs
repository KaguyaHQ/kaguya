defmodule KaguyaWeb.UI.FieldTest do
  use ExUnit.Case, async: true
  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias KaguyaWeb.UI.{Field, Input}

  test "connects a label, hint and validation messages to its input" do
    html =
      render_component(&example/1, errors: ["Enter a valid email."], hint: "Used for sign-in.")

    dom = LazyHTML.from_fragment(html)

    assert present?(dom, "label[for='email']")

    assert present?(
             dom,
             "input#email[required][aria-invalid='true'][aria-describedby='email-errors email-hint']"
           )

    assert present?(dom, "#email-hint")
    assert present?(dom, "#email-errors[aria-live='polite']")
  end

  test "does not leave validation references on a field without messages" do
    dom = render_component(&example/1, errors: [], hint: nil) |> LazyHTML.from_fragment()
    assert present?(dom, "input#email[required]")
    refute present?(dom, "input[aria-invalid]")
    refute present?(dom, "input[aria-describedby]")
    refute present?(dom, "#email-errors")
  end

  test "input preserves form binding and native attributes with the roomy size" do
    form = to_form(%{"email" => "reader@example.com"}, as: :account)

    dom =
      render_component(&Input.input/1,
        field: form[:email],
        control_size: "roomy",
        type: "email",
        autocomplete: "email",
        size: 30
      )
      |> LazyHTML.from_fragment()

    assert present?(
             dom,
             "input#account_email[name='account[email]'][value='reader@example.com'][autocomplete='email'][size='30']"
           )

    refute present?(dom, "input[control_size]")
  end

  defp example(assigns) do
    ~H"""
    <Field.field :let={attrs} id="email" label="Email" hint={@hint} errors={@errors} required>
      <Input.input name="email" type="email" control_size="roomy" {attrs} />
    </Field.field>
    """
  end

  defp present?(dom, selector), do: dom |> LazyHTML.query(selector) |> Enum.any?()
end
