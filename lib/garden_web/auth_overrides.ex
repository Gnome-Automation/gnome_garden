defmodule GnomeGardenWeb.AuthOverrides do
  use AshAuthentication.Phoenix.Overrides

  alias AshAuthentication.Phoenix.{
    Components,
    ConfirmLive,
    MagicSignInLive,
    ResetLive,
    SignInLive
  }

  override SignInLive do
    set :root_class, "gg-auth-page"
    set :sign_in_id, "garden-sign-in"
  end

  override MagicSignInLive do
    set :root_class, "gg-auth-page"
  end

  override ResetLive do
    set :root_class, "gg-auth-page"
  end

  override ConfirmLive do
    set :root_class, "gg-auth-page"
  end

  override Components.SignIn do
    set :root_class, "gg-auth-panel"
    set :strategy_class, "gg-auth-strategy"
    set :show_banner, true
    set :authentication_error_container_class, "gg-auth-error"
    set :authentication_error_text_class, "gg-auth-error-text"
    set :strategy_display_order, :forms_first
  end

  override Components.Banner do
    set :root_class, "gg-auth-banner"
    set :href_class, "gg-auth-brand-link"
    set :href_url, "/"
    set :image_url, nil
    set :dark_image_url, nil
    set :text, "Gnome Garden"
    set :text_class, "gg-auth-brand"
  end

  override Components.MagicLink do
    set :root_class, "gg-auth-magic"
    set :label_class, "gg-auth-title"
    set :form_class, "gg-auth-form"

    set :request_flash_text,
        "If that email can sign in, a garden link is on the way."

    set :disable_button_text, "Sending link..."
  end

  override Components.MagicLink.SignIn do
    set :root_class, "gg-auth-panel"
    set :strategy_class, "gg-auth-strategy"
    set :show_banner, true
  end

  override Components.MagicLink.Form do
    set :root_class, "gg-auth-magic"
    set :label_class, "gg-auth-title"
    set :form_class, "gg-auth-form"
    set :disable_button_text, "Signing in..."
  end

  override Components.MagicLink.Input do
    set :submit_class, "gg-auth-submit"
    set :submit_label, "Send sign-in link"
    set :input_debounce, 350
    set :remember_me_class, "gg-auth-remember"
    set :remember_me_input_label, "Remember me"
    set :checkbox_class, "gg-auth-checkbox"
    set :checkbox_label_class, "gg-auth-checkbox-label"
  end

  override Components.Password do
    set :root_class, "gg-auth-password"
    set :interstitial_class, "gg-auth-links"
    set :toggler_class, "gg-auth-link"
    set :sign_in_toggle_text, "Already have an account?"
    set :register_toggle_text, nil
    set :reset_toggle_text, "Forgot password?"
    set :show_first, :sign_in
    set :hide_class, "hidden"
    set :sign_in_form_module, AshAuthentication.Phoenix.Components.Password.SignInForm
    set :reset_form_module, AshAuthentication.Phoenix.Components.Password.ResetForm
  end

  override Components.Password.SignInForm do
    set :root_class, "gg-auth-form-wrap"
    set :label_class, "gg-auth-title"
    set :form_class, "gg-auth-form"
    set :slot_class, "gg-auth-form-slot"
    set :button_text, "Sign in"
    set :disable_button_text, "Signing in..."
  end

  override Components.Password.ResetForm do
    set :root_class, "gg-auth-form-wrap"
    set :label_class, "gg-auth-title"
    set :form_class, "gg-auth-form"
    set :slot_class, "gg-auth-form-slot"
    set :button_text, "Send reset link"
    set :disable_button_text, "Sending link..."

    set :reset_flash_text,
        "If that account exists, password reset instructions are on the way."
  end

  override Components.Password.Input do
    set :field_class, "gg-auth-field"
    set :label_class, "gg-auth-label"
    set :input_class, "gg-auth-input"
    set :input_class_with_error, "gg-auth-input gg-auth-input-error"
    set :submit_class, "gg-auth-submit"
    set :identity_input_label, "Operator"
    set :identity_input_placeholder, "pc"
    set :password_input_label, "Password"
    set :password_confirmation_input_label, "Confirm password"
    set :error_ul, "gg-auth-errors"
    set :error_li, "gg-auth-error-item"
    set :input_debounce, 350
    set :remember_me_class, "gg-auth-remember"
    set :remember_me_input_label, "Remember me"
    set :checkbox_class, "gg-auth-checkbox"
    set :checkbox_label_class, "gg-auth-checkbox-label"
  end

  override Components.Flash do
    set :message_class_info, "gg-auth-flash gg-auth-flash-info"
    set :message_class_error, "gg-auth-flash gg-auth-flash-error"
  end
end
