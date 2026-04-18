defmodule GnomeGardenWeb.CinderTheme do
  @moduledoc """
  Protocol-inspired Cinder theme.
  Clean zinc neutrals with emerald accent, matching Tailwind Plus table patterns.
  """
  use Cinder.Theme

  # Container - white table on zinc background
  set :container_class, "bg-white py-6 dark:bg-zinc-900"

  # Table wrapper for horizontal scroll
  set :table_wrapper_class, "overflow-x-auto"

  # Table - clean and minimal with whitespace-nowrap
  set :table_class, "w-full text-left whitespace-nowrap"

  # Header styling - border-b separator, semibold text
  set :thead_class,
      "border-b border-zinc-200 text-sm/6 text-zinc-900 dark:border-white/15 dark:text-white"

  set :th_class, "py-2 pr-8 pl-4 font-semibold sm:pl-6 lg:pl-8"
  set :header_row_class, ""

  # Body and rows - divide-y for clean separators
  set :tbody_class, "divide-y divide-zinc-100 dark:divide-white/10"
  set :row_class, ""
  set :td_class, "py-4 pr-8 pl-4 text-sm/6 text-zinc-500 sm:pl-6 lg:pl-8 dark:text-zinc-400"

  # Selected rows
  set :selected_row_class, "bg-emerald-50/50 dark:bg-emerald-500/5"

  # Pagination - clean style
  set :pagination_container_class,
      "flex items-center justify-between px-4 py-4 border-t border-zinc-200 sm:px-6 lg:px-8 dark:border-white/15"

  set :pagination_button_class,
      "inline-flex items-center gap-1 rounded-md px-3 py-1.5 text-sm font-medium text-zinc-600 transition hover:bg-zinc-100 hover:text-zinc-900 dark:text-zinc-400 dark:hover:bg-white/10 dark:hover:text-white"

  set :pagination_info_class, "text-sm text-zinc-500 dark:text-zinc-400"

  # Page size dropdown
  set :page_size_container_class, "flex items-center gap-2 text-sm text-zinc-500"

  set :page_size_dropdown_class,
      "rounded-md border-0 bg-transparent py-1 pl-2 pr-8 text-sm text-zinc-600 ring-1 ring-inset ring-zinc-300 focus:ring-2 focus:ring-emerald-500 dark:text-zinc-400 dark:ring-white/15"

  # Controls/filters section - minimal, just search
  set :controls_class, "px-4 pb-4 sm:px-6 lg:px-8"
  set :filter_header_class, "hidden"
  set :filter_title_class, "hidden"
  set :filter_container_class, ""
  set :filter_group_class, ""
  set :filter_count_class, "hidden"
  set :filter_label_class, "hidden"

  # Search - clean rounded input
  set :search_container_class, ""

  set :search_input_class,
      "w-full max-w-md rounded-md border-0 bg-zinc-100 px-4 py-2 text-sm text-zinc-900 ring-1 ring-inset ring-zinc-300 placeholder:text-zinc-400 focus:bg-white focus:ring-2 focus:ring-emerald-500 dark:bg-white/5 dark:text-white dark:ring-white/15 dark:placeholder:text-zinc-500 dark:focus:bg-white/10"

  # Sort controls
  set :sort_indicator_class, "inline-block ml-1"
  set :sort_asc_icon_class, "size-3 inline text-zinc-400"
  set :sort_desc_icon_class, "size-3 inline text-zinc-400"
  set :sort_none_icon_class, "size-3 inline text-zinc-300 dark:text-zinc-600"

  # Loading - small inline spinner in top right
  set :loading_overlay_class, "absolute top-4 right-4"

  set :loading_container_class,
      "flex items-center gap-2 text-sm text-emerald-600 dark:text-emerald-400"

  set :loading_spinner_class, "size-4 animate-spin"
  set :loading_spinner_circle_class, "opacity-25"
  set :loading_spinner_path_class, "opacity-75"

  # Empty state
  set :empty_class, "py-12"
  set :empty_container_class, "text-center text-zinc-500 dark:text-zinc-400"

  # Grid layout for cards
  set :grid_class, "grid gap-6 p-4 sm:p-6 lg:p-8"
  set :grid_item_class, ""
end
