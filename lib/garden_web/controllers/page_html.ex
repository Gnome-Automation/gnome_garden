defmodule GnomeGardenWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use GnomeGardenWeb, :html
  import GnomeGardenWeb.Execution.Helpers, only: [format_date: 1]

  embed_templates "page_html/*"
end
