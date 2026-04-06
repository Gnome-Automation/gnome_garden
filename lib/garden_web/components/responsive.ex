defmodule GnomeGardenWeb.Components.Responsive do
  @moduledoc """
  Responsive layout detection component using colocated JS hook.

  ## Usage

  Add to your LiveView:

      def mount(_params, _session, socket) do
        {:ok, assign(socket, :is_desktop, true)}
      end

      def handle_event("responsive-change", %{"is_desktop" => is_desktop}, socket) do
        {:noreply, assign(socket, :is_desktop, is_desktop)}
      end

  In your template:

      <.responsive_hook />

      <div :if={@is_desktop}>Desktop table</div>
      <div :if={!@is_desktop}>Mobile cards</div>
  """
  use Phoenix.Component

  @doc """
  Renders a hidden element with the responsive detection hook.
  Place this once in your template to enable responsive detection.
  """
  def responsive_hook(assigns) do
    ~H"""
    <div id="responsive-detector" phx-hook=".Responsive" phx-update="ignore" class="hidden"></div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Responsive">
      export default {
        mounted() {
          this.mql = window.matchMedia("(min-width: 1024px)")
          this.pushState(this.mql.matches)
          this.listener = (e) => this.pushState(e.matches)
          this.mql.addEventListener("change", this.listener)
        },
        destroyed() {
          if (this.mql && this.listener) {
            this.mql.removeEventListener("change", this.listener)
          }
        },
        pushState(isDesktop) {
          this.pushEvent("responsive-change", { is_desktop: isDesktop })
        }
      }
    </script>
    """
  end
end
