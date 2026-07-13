defmodule GnomeGarden.Browser.LoginForm do
  @moduledoc false

  @username_selector "input[type='email'], input[name*='email' i], input[id*='email' i], input[name*='user' i], input[id*='user' i], input[type='text']"
  @password_selector "input[type='password'], input[name*='password' i], input[id*='password' i]"

  def username_selector, do: @username_selector
  def password_selector, do: @password_selector

  def submit_if_present(browser, credentials) do
    with {:ok, surface} <- browser.evaluate(surface_script()) do
      case surface do
        %{"has_login_form" => false} ->
          {:ok, :absent}

        %{"has_login_form" => true} ->
          with {:ok, _typed} <- browser.type(username_selector(), credentials.username),
               {:ok, _typed} <- browser.type(password_selector(), credentials.password),
               {:ok, result} <- browser.evaluate(submit_script()),
               :ok <- submitted?(result) do
            {:ok, :submitted}
          end

        _surface ->
          {:ok, :absent}
      end
    end
  end

  def surface_script do
    """
    (() => {
      const clean = value => (value || '').replace(/\\s+/g, ' ').trim();
      const userInput = document.querySelector(#{Jason.encode!(@username_selector)});
      const passInput = document.querySelector(#{Jason.encode!(@password_selector)});

      if (!userInput || !passInput) {
        const loginLink = Array.from(document.querySelectorAll('a[href], button')).find(element => {
          const text = clean(element.innerText || element.value || element.getAttribute('aria-label'));
          const href = element.href || '';
          return /login|log in|sign in|vendor|supplier|account/i.test(`${text} ${href}`);
        });

        return {
          has_login_form: false,
          login_url: loginLink && loginLink.href ? loginLink.href : null,
          reason: loginLink ? 'login_link_found' : 'no_login_form'
        };
      }

      return {has_login_form: true};
    })()
    """
  end

  def submit_script do
    """
    (() => {
      const passInput = document.querySelector(#{Jason.encode!(@password_selector)});
      const form = passInput && passInput.closest('form');

      if (!passInput || !form) return {submitted: false, reason: 'no_login_form'};

      const submit = form.querySelector(
        'button[type="submit"], input[type="submit"], input[type="button"], button[id*="login" i], button[class*="login" i], button'
      );

      if (submit) {
        submit.click();
        return {submitted: true, method: 'form_button'};
      }

      if (form.requestSubmit) {
        form.requestSubmit();
        return {submitted: true, method: 'request_submit'};
      }

      form.dispatchEvent(new Event('submit', {bubbles: true, cancelable: true}));
      return {submitted: true, method: 'submit_event'};
    })()
    """
  end

  def submitted?(%{"submitted" => true}), do: :ok
  def submitted?(%{"reason" => reason}), do: {:error, reason}
  def submitted?(_result), do: {:error, "Could not submit the login form."}
end
