defmodule MyApp.RegistrationLive do
  @moduledoc """
  A registration form with real-time validation.

  Demonstrates ignite-change (per-field validation on input)
  and ignite-submit (full form validation on submit).
  """

  use Ignite.LiveView

  def mount(_params, _session) do
    {:ok, %{name: "", email: "", password: "", errors: %{}, submitted: false}}
  end

  def handle_event("validate", %{"field" => field, "value" => value}, assigns) do
    # Update the field value and validate it
    assigns = Map.put(assigns, String.to_existing_atom(field), value)
    error = validate_field(field, value)

    errors =
      if error do
        Map.put(assigns.errors, field, error)
      else
        Map.delete(assigns.errors, field)
      end

    {:noreply, %{assigns | errors: errors}}
  end

  def handle_event("reset", _params, _assigns) do
    {:noreply, %{name: "", email: "", password: "", errors: %{}, submitted: false}}
  end

  def handle_event("submit", params, assigns) do
    # Update all fields from form data
    assigns = %{assigns | name: params["name"] || "", email: params["email"] || "", password: params["password"] || ""}

    # Validate all fields (required on submit)
    errors =
      %{}
      |> put_error("name", validate_required("name", assigns.name))
      |> put_error("email", validate_required("email", assigns.email))
      |> put_error("password", validate_required("password", assigns.password))

    if map_size(errors) == 0 do
      {:noreply, %{assigns | errors: %{}, submitted: true}}
    else
      {:noreply, %{assigns | errors: errors, submitted: false}}
    end
  end

  def render(assigns) do
    if assigns.submitted do
      """
      <div id="registration">
        <h1>Registration</h1>
        <div style="background: #d4edda; border: 1px solid #c3e6cb; padding: 20px; border-radius: 8px; margin: 20px auto; max-width: 400px;">
          <h2 style="color: #155724; margin-top: 0;">Welcome, #{html_escape(assigns.name)}!</h2>
          <p style="color: #155724;">Your account has been created successfully.</p>
        </div>
        <button ignite-click="reset">Register another</button>
      </div>
      """
    else
      """
      <div id="registration">
        <h1>Registration</h1>
        <form ignite-submit="submit" style="max-width: 400px; margin: 0 auto; text-align: left;">
          <div style="margin-bottom: 15px;">
            <label for="name" style="display: block; margin-bottom: 4px; font-weight: bold;">Name</label>
            <input type="text" id="name" name="name" value="#{html_escape(assigns.name)}"
                   ignite-change="validate" placeholder="Your name"
                   style="width: 100%; padding: 8px; box-sizing: border-box;#{field_border(assigns.errors, "name")}" />
            #{error_tag(assigns.errors, "name")}
          </div>

          <div style="margin-bottom: 15px;">
            <label for="email" style="display: block; margin-bottom: 4px; font-weight: bold;">Email</label>
            <input type="text" id="email" name="email" value="#{html_escape(assigns.email)}"
                   ignite-change="validate" placeholder="you@example.com"
                   style="width: 100%; padding: 8px; box-sizing: border-box;#{field_border(assigns.errors, "email")}" />
            #{error_tag(assigns.errors, "email")}
          </div>

          <div style="margin-bottom: 15px;">
            <label for="password" style="display: block; margin-bottom: 4px; font-weight: bold;">Password</label>
            <input type="password" id="password" name="password" value="#{html_escape(assigns.password)}"
                   ignite-change="validate" placeholder="At least 6 characters"
                   style="width: 100%; padding: 8px; box-sizing: border-box;#{field_border(assigns.errors, "password")}" />
            #{error_tag(assigns.errors, "password")}
          </div>

          <button type="submit" style="width: 100%; padding: 10px; background: #4CAF50; color: white; border: none; border-radius: 4px; cursor: pointer; font-size: 16px;">
            Register
          </button>
        </form>
      </div>
      """
    end
  end

  # --- Validation ---

  defp validate_field("name", value) do
    cond do
      String.length(value) == 0 -> nil
      String.length(value) < 2 -> "must be at least 2 characters"
      true -> nil
    end
  end

  defp validate_field("email", value) do
    cond do
      String.length(value) == 0 -> nil
      not String.contains?(value, "@") or not String.contains?(value, ".") -> "must be a valid email (contain @ and .)"
      true -> nil
    end
  end

  defp validate_field("password", value) do
    cond do
      String.length(value) == 0 -> nil
      String.length(value) < 6 -> "must be at least 6 characters"
      true -> nil
    end
  end

  defp validate_field(_, _), do: nil

  # Like validate_field but treats empty as an error (for submit)
  defp validate_required(_field, ""), do: "is required"
  defp validate_required(field, value), do: validate_field(field, value) || nil

  # --- Helpers ---

  defp put_error(errors, _field, nil), do: errors
  defp put_error(errors, field, msg), do: Map.put(errors, field, msg)

  defp error_tag(errors, field) do
    case Map.get(errors, field) do
      nil -> ""
      msg -> "<p style=\"color: #dc3545; margin: 4px 0 0 0; font-size: 14px;\">#{msg}</p>"
    end
  end

  defp field_border(errors, field) do
    if Map.has_key?(errors, field) do
      " border: 1px solid #dc3545;"
    else
      ""
    end
  end

  defp html_escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
