defmodule GnomeGardenWeb.Auth.PasswordSignInForm do
  @moduledoc false

  use AshAuthentication.Phoenix.Web, :live_component

  alias AshAuthentication.Phoenix.Components.Password.Input
  alias AshAuthentication.Phoenix.Components.Password.SignInForm

  import AshAuthentication.Phoenix.Components.Helpers, only: [auth_path: 5]

  @impl true
  defdelegate update(assigns, socket), to: SignInForm

  @impl true
  defdelegate handle_event(event, params, socket), to: SignInForm

  @impl true
  def render(assigns) do
    ~H"""
    <div class="gg-auth-form-wrap">
      <.form
        :let={form}
        for={@form}
        id={@form.id}
        phx-change="change"
        phx-submit="submit"
        phx-trigger-action={@trigger_action}
        phx-target={@myself}
        action={auth_path(@socket, @subject_name, @auth_routes_prefix, @strategy, :sign_in)}
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
        <Input.password_field
          strategy={@strategy}
          form={form}
          overrides={@overrides}
          gettext_fn={@gettext_fn}
        />
        <%= if @inner_block do %>
          <div class="gg-auth-form-slot">
            {render_slot(@inner_block, form)}
          </div>
        <% end %>

        <Input.remember_me_field
          :if={@remember_me_field}
          name={@remember_me_field}
          form={form}
          overrides={@overrides}
          gettext_fn={@gettext_fn}
        />

        <Input.submit
          strategy={@strategy}
          id={@form.id <> "-submit"}
          form={form}
          action={:sign_in}
          label="Sign in"
          disable_text="Signing in..."
          overrides={@overrides}
          gettext_fn={@gettext_fn}
        />
      </.form>
    </div>
    """
  end
end
