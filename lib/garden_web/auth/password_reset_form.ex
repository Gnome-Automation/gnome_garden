defmodule GnomeGardenWeb.Auth.PasswordResetForm do
  @moduledoc false

  use AshAuthentication.Phoenix.Web, :live_component

  alias AshAuthentication.Phoenix.Components.Password.Input
  alias AshAuthentication.Phoenix.Components.Password.ResetForm

  import AshAuthentication.Phoenix.Components.Helpers, only: [auth_path: 5]

  @impl true
  defdelegate update(assigns, socket), to: ResetForm

  @impl true
  defdelegate handle_event(event, params, socket), to: ResetForm

  @impl true
  def render(assigns) do
    ~H"""
    <div class="gg-auth-form-wrap">
      <.form
        :let={form}
        for={@form}
        phx-submit="submit"
        phx-change="change"
        phx-target={@myself}
        action={auth_path(@socket, @subject_name, @auth_routes_prefix, @strategy, :reset_request)}
        method="POST"
        class="gg-auth-form"
      >
        <Input.identity_field
          strategy={@strategy}
          form={form}
          input_type={:text}
          overrides={@overrides}
          gettext_fn={@gettext_fn}
        />

        <%= if @inner_block do %>
          <div class="gg-auth-form-slot">
            {render_slot(@inner_block, form)}
          </div>
        <% end %>

        <Input.submit
          strategy={@strategy}
          form={form}
          action={:request_reset}
          label="Send reset link"
          disable_text="Sending link..."
          overrides={@overrides}
          gettext_fn={@gettext_fn}
        />
      </.form>
    </div>
    """
  end
end
