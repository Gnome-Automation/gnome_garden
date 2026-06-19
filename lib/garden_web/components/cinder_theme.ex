defmodule GnomeGardenWeb.CinderTheme do
  @moduledoc """
  Garden Cinder theme — uses daisyUI semantic tokens so tables follow the
  active theme (cool-teal garden palette in dark mode).
  """
  use Cinder.Theme

  # Container
  set :container_class, "rounded-xl border border-base-content/10 bg-base-200"
  set :table_wrapper_class, "overflow-x-auto"

  # Table
  set :table_class, "w-full text-left whitespace-nowrap"

  # Header
  set :thead_class,
      "border-b border-base-content/10 text-[11px] font-semibold uppercase tracking-wider text-base-content/50"

  set :th_class, "px-4 py-2.5 sm:px-5"
  set :header_row_class, ""

  # Body + rows
  set :tbody_class, "divide-y divide-base-content/5"
  set :row_class, "hover:bg-base-300/40"
  set :td_class, "px-4 py-3 text-sm text-base-content/80 sm:px-5"
  set :selected_row_class, "bg-primary/5"

  # Pagination
  set :pagination_container_class,
      "flex items-center justify-between gap-3 px-4 py-3 border-t border-base-content/10 sm:px-5"

  set :pagination_button_class,
      "inline-flex items-center gap-1 rounded-md px-2.5 py-1 text-xs font-medium text-base-content/70 hover:bg-base-300 hover:text-base-content"

  set :pagination_info_class, "text-xs text-base-content/50"

  # Page size dropdown
  set :page_size_container_class, "flex items-center gap-2 text-xs text-base-content/50"

  set :page_size_dropdown_class,
      "rounded-md border border-base-content/10 bg-base-100 px-2 py-1 text-xs text-base-content focus:border-primary focus:outline-none"

  # Controls / filters section — search only, filters hidden
  set :controls_class, "px-4 py-3 sm:px-5"
  set :filter_header_class, "hidden"
  set :filter_title_class, "hidden"
  set :filter_container_class, ""
  set :filter_inputs_class, "flex flex-col gap-2 sm:flex-row sm:flex-wrap sm:items-center"
  set :filter_group_class, ""
  set :filter_count_class, "hidden"
  set :filter_label_class, "hidden"
  set :filter_input_wrapper_class, "min-w-0"

  # Search input
  set :search_container_class, ""

  set :search_input_class,
      "w-full max-w-md rounded-md border border-base-content/10 bg-base-100 py-1.5 pl-9 pr-3 text-sm text-base-content placeholder:text-base-content/40 focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"

  set :search_icon_class, "size-4 text-base-content/35"

  set :filter_clear_button_class,
      "ml-2 inline-flex size-8 items-center justify-center rounded-md text-base-content/45 hover:bg-base-300 hover:text-base-content"

  set :filter_select_container_class, "relative min-w-0 sm:min-w-36"

  set :filter_select_input_class,
      "w-full rounded-md border border-base-content/10 bg-base-100 px-3 py-1.5 text-sm text-base-content transition hover:bg-base-200 focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"

  set :filter_select_dropdown_class,
      "absolute z-50 mt-1 max-h-60 w-full overflow-auto rounded-md border border-base-content/10 bg-base-100 py-1 shadow-lg"

  set :filter_select_option_class,
      "px-3 py-2 text-sm text-base-content hover:bg-base-200"

  set :filter_select_label_class, "min-w-0 flex-1 cursor-pointer select-none truncate"
  set :filter_select_empty_class, "px-3 py-2 text-sm italic text-base-content/50"
  set :filter_select_arrow_class, "ml-2 size-4 shrink-0 text-base-content/35"
  set :filter_select_placeholder_class, "text-base-content/50"

  # Sort controls for list/grid layouts
  set :sort_container_class,
      "mt-3 rounded-lg border border-base-content/10 bg-base-100/70"

  set :sort_controls_class, "flex flex-col gap-2 p-3 sm:flex-row sm:items-center sm:gap-3"
  set :sort_controls_label_class, "text-xs font-semibold uppercase text-base-content/45"
  set :sort_buttons_class, "flex flex-wrap gap-1.5"
  set :sort_button_class, "rounded-md border px-2.5 py-1 text-xs font-semibold transition-colors"

  set :sort_button_active_class,
      "border-primary/40 bg-primary/10 text-primary"

  set :sort_button_inactive_class,
      "border-base-content/10 bg-base-200 text-base-content/65 hover:bg-base-300 hover:text-base-content"

  set :sort_icon_class, "ml-1 text-primary"

  # Sort indicators
  set :sort_indicator_class, "inline-block ml-1"
  set :sort_asc_icon_class, "size-3 inline text-primary"
  set :sort_desc_icon_class, "size-3 inline text-primary"
  set :sort_none_icon_class, "size-3 inline text-base-content/30"

  # Loading
  set :loading_overlay_class, "absolute top-3 right-3"
  set :loading_container_class, "flex items-center gap-2 text-xs text-primary"
  set :loading_spinner_class, "size-4 animate-spin"
  set :loading_spinner_circle_class, "opacity-25"
  set :loading_spinner_path_class, "opacity-75"

  # Empty
  set :empty_class, "py-10"
  set :empty_container_class, "text-center text-sm text-base-content/50"

  # List layout
  set :list_container_class, "space-y-2 p-3 sm:p-4"
  set :list_item_class, ""
  set :list_item_clickable_class, "cursor-pointer transition hover:bg-base-200"
  set :list_selection_container_class, "mb-2"

  # Grid layout
  set :grid_container_class, "grid gap-4 p-4 sm:p-5"
  set :grid_item_class, ""
  set :grid_item_clickable_class, "cursor-pointer transition hover:bg-base-200"
end
