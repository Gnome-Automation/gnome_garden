defmodule GnomeGardenWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use GnomeGardenWeb, :html

  import GnomeGardenWeb.Execution.Helpers,
    only: [
      format_amount: 1,
      format_atom: 1,
      format_date: 1,
      format_datetime: 1,
      format_minutes: 1
    ]

  embed_templates "page_html/*"
end
