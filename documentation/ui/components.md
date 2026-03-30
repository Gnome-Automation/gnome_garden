# UI Components

## DaisyUI Components Used

GnomeGarden uses DaisyUI as the primary component library, extended with custom Phoenix components.

---

## Layout Components

### Card
```heex
<div class="card bg-base-100 shadow-xl">
  <figure><img src="/images/project.jpg" alt="Project" /></figure>
  <div class="card-body">
    <h2 class="card-title">Project Name</h2>
    <p>Project description goes here.</p>
    <div class="card-actions justify-end">
      <button class="btn btn-primary">View</button>
    </div>
  </div>
</div>
```

### Drawer
```heex
<div class="drawer lg:drawer-open">
  <input id="my-drawer" type="checkbox" class="drawer-toggle" />
  <div class="drawer-content">
    <!-- Main content -->
  </div>
  <div class="drawer-side">
    <label for="my-drawer" class="drawer-overlay"></label>
    <ul class="menu bg-base-100 w-64 p-4">
      <li><a>Menu Item</a></li>
    </ul>
  </div>
</div>
```

### Modal
```heex
<dialog id="my_modal" class="modal">
  <div class="modal-box">
    <h3 class="font-bold text-lg">Modal Title</h3>
    <p class="py-4">Modal content here.</p>
    <div class="modal-action">
      <form method="dialog">
        <button class="btn">Close</button>
      </form>
    </div>
  </div>
</dialog>
```

---

## Navigation Components

### Navbar
```heex
<div class="navbar bg-base-100">
  <div class="flex-1">
    <a class="btn btn-ghost text-xl">GnomeGarden</a>
  </div>
  <div class="flex-none gap-2">
    <div class="dropdown dropdown-end">
      <div tabindex="0" class="btn btn-ghost btn-circle avatar">
        <div class="w-10 rounded-full">
          <img src="/avatar.jpg" />
        </div>
      </div>
      <ul tabindex="0" class="dropdown-content menu bg-base-100 rounded-box z-[1] w-52 p-2 shadow">
        <li><a>Settings</a></li>
        <li><a>Logout</a></li>
      </ul>
    </div>
  </div>
</div>
```

### Bottom Navigation
```heex
<div class="btm-nav">
  <button class="active">
    <.icon name="hero-home" />
    <span class="btm-nav-label">Home</span>
  </button>
  <button>
    <.icon name="hero-folder" />
    <span class="btm-nav-label">Projects</span>
  </button>
  <button>
    <.icon name="hero-cog-6-tooth" />
    <span class="btm-nav-label">Settings</span>
  </button>
</div>
```

### Tabs
```heex
<div role="tablist" class="tabs tabs-bordered">
  <a role="tab" class="tab tab-active">Overview</a>
  <a role="tab" class="tab">Details</a>
  <a role="tab" class="tab">Activity</a>
</div>
```

### Breadcrumbs
```heex
<div class="text-sm breadcrumbs">
  <ul>
    <li><a>Home</a></li>
    <li><a>Companies</a></li>
    <li>Acme Corp</li>
  </ul>
</div>
```

---

## Data Display Components

### Table
```heex
<div class="overflow-x-auto">
  <table class="table table-zebra">
    <thead>
      <tr>
        <th>Name</th>
        <th>Email</th>
        <th>Status</th>
        <th></th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td>John Doe</td>
        <td>john@example.com</td>
        <td><span class="badge badge-success">Active</span></td>
        <td><button class="btn btn-ghost btn-xs">Edit</button></td>
      </tr>
    </tbody>
  </table>
</div>
```

### Stats
```heex
<div class="stats shadow">
  <div class="stat">
    <div class="stat-title">Revenue</div>
    <div class="stat-value">$89,400</div>
    <div class="stat-desc">↗︎ 14% from last month</div>
  </div>
  <div class="stat">
    <div class="stat-title">Projects</div>
    <div class="stat-value">24</div>
    <div class="stat-desc">3 in progress</div>
  </div>
</div>
```

### Badge
```heex
<span class="badge">Default</span>
<span class="badge badge-primary">Primary</span>
<span class="badge badge-success">Success</span>
<span class="badge badge-warning">Warning</span>
<span class="badge badge-error">Error</span>
```

### Avatar
```heex
<div class="avatar">
  <div class="w-12 rounded-full">
    <img src="/avatar.jpg" />
  </div>
</div>

<!-- Placeholder -->
<div class="avatar placeholder">
  <div class="bg-neutral text-neutral-content rounded-full w-12">
    <span>JD</span>
  </div>
</div>
```

---

## Form Components

### Input
```heex
<label class="form-control w-full max-w-xs">
  <div class="label">
    <span class="label-text">Email</span>
  </div>
  <input type="email" placeholder="email@example.com" class="input input-bordered w-full" />
  <div class="label">
    <span class="label-text-alt text-error">Email is required</span>
  </div>
</label>
```

### Select
```heex
<select class="select select-bordered w-full max-w-xs">
  <option disabled selected>Select status</option>
  <option>Active</option>
  <option>Inactive</option>
</select>
```

### Textarea
```heex
<textarea class="textarea textarea-bordered w-full" placeholder="Description"></textarea>
```

### Checkbox
```heex
<label class="label cursor-pointer">
  <span class="label-text">Remember me</span>
  <input type="checkbox" class="checkbox checkbox-primary" />
</label>
```

### Toggle
```heex
<input type="checkbox" class="toggle toggle-primary" checked />
```

---

## Action Components

### Button
```heex
<button class="btn">Default</button>
<button class="btn btn-primary">Primary</button>
<button class="btn btn-secondary">Secondary</button>
<button class="btn btn-accent">Accent</button>
<button class="btn btn-ghost">Ghost</button>
<button class="btn btn-link">Link</button>

<!-- Sizes -->
<button class="btn btn-lg">Large</button>
<button class="btn btn-sm">Small</button>
<button class="btn btn-xs">Extra Small</button>

<!-- Loading -->
<button class="btn loading">Loading</button>
```

### Dropdown
```heex
<div class="dropdown">
  <div tabindex="0" class="btn m-1">Actions</div>
  <ul tabindex="0" class="dropdown-content menu bg-base-100 rounded-box z-[1] w-52 p-2 shadow">
    <li><a>Edit</a></li>
    <li><a>Duplicate</a></li>
    <li><a class="text-error">Delete</a></li>
  </ul>
</div>
```

---

## Feedback Components

### Alert
```heex
<div role="alert" class="alert alert-success">
  <.icon name="hero-check-circle" />
  <span>Company saved successfully!</span>
</div>

<div role="alert" class="alert alert-error">
  <.icon name="hero-x-circle" />
  <span>Error saving company.</span>
</div>
```

### Toast
```heex
<div class="toast toast-end">
  <div class="alert alert-info">
    <span>New message received.</span>
  </div>
</div>
```

### Loading
```heex
<span class="loading loading-spinner loading-lg"></span>
<span class="loading loading-dots loading-md"></span>
<span class="loading loading-ring loading-sm"></span>
```

### Progress
```heex
<progress class="progress progress-primary w-56" value="70" max="100"></progress>
```

---

## Custom Phoenix Components

### Status Badge
```elixir
attr :status, :atom, required: true

def status_badge(assigns) do
  color = case assigns.status do
    :active -> "badge-success"
    :pending -> "badge-warning"
    :inactive -> "badge-ghost"
    :error -> "badge-error"
    _ -> "badge-neutral"
  end

  assigns = assign(assigns, :color, color)

  ~H"""
  <span class={"badge #{@color}"}>
    <%= humanize(@status) %>
  </span>
  """
end
```

### Empty State
```elixir
attr :title, :string, required: true
attr :description, :string, default: nil
attr :icon, :string, default: "hero-inbox"
slot :action

def empty_state(assigns) do
  ~H"""
  <div class="flex flex-col items-center justify-center py-12 text-center">
    <.icon name={@icon} class="h-12 w-12 text-base-content/50 mb-4" />
    <h3 class="text-lg font-semibold"><%= @title %></h3>
    <%= if @description do %>
      <p class="text-base-content/70 mt-1"><%= @description %></p>
    <% end %>
    <%= if @action do %>
      <div class="mt-4">
        <%= render_slot(@action) %>
      </div>
    <% end %>
  </div>
  """
end
```

### Data Table
```elixir
attr :rows, :list, required: true
attr :row_click, :any, default: nil
slot :col, required: true do
  attr :label, :string, required: true
  attr :field, :atom
end

def data_table(assigns) do
  ~H"""
  <div class="overflow-x-auto">
    <table class="table">
      <thead>
        <tr>
          <%= for col <- @col do %>
            <th><%= col.label %></th>
          <% end %>
        </tr>
      </thead>
      <tbody>
        <%= for row <- @rows do %>
          <tr class={@row_click && "hover cursor-pointer"} phx-click={@row_click && @row_click.(row)}>
            <%= for col <- @col do %>
              <td><%= render_slot(col, row) %></td>
            <% end %>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>
  """
end
```

### Pagination
```elixir
attr :page, :integer, required: true
attr :total_pages, :integer, required: true
attr :path, :string, required: true

def pagination(assigns) do
  ~H"""
  <div class="join">
    <.link
      navigate={"#{@path}?page=#{@page - 1}"}
      class={"join-item btn #{if @page == 1, do: "btn-disabled"}"}
    >
      «
    </.link>
    <button class="join-item btn">Page <%= @page %></button>
    <.link
      navigate={"#{@path}?page=#{@page + 1}"}
      class={"join-item btn #{if @page == @total_pages, do: "btn-disabled"}"}
    >
      »
    </.link>
  </div>
  """
end
```

---

## Design Tokens

### Colors
```css
/* Primary palette */
--p: primary
--pf: primary-focus
--pc: primary-content

/* Status colors */
--su: success
--wa: warning
--er: error
--in: info

/* Base colors */
--b1: base-100 (background)
--b2: base-200
--b3: base-300
--bc: base-content (text)
```

### Spacing
```
0: 0px
1: 0.25rem (4px)
2: 0.5rem (8px)
3: 0.75rem (12px)
4: 1rem (16px)
6: 1.5rem (24px)
8: 2rem (32px)
```

### Typography
```css
/* Font sizes */
text-xs: 0.75rem
text-sm: 0.875rem
text-base: 1rem
text-lg: 1.125rem
text-xl: 1.25rem
text-2xl: 1.5rem

/* Font weights */
font-normal: 400
font-medium: 500
font-semibold: 600
font-bold: 700
```
