# UI Layout

## Mobile-First Design

GnomeHub uses a mobile-first responsive design built with DaisyUI and Tailwind CSS. The layout adapts seamlessly between mobile and desktop experiences.

---

## Breakpoints

| Breakpoint | Width | Layout |
|------------|-------|--------|
| Mobile | < 768px | Bottom nav + full-width content |
| Tablet | 768px - 1024px | Collapsible drawer + content |
| Desktop | > 1024px | Fixed drawer + content |

---

## Layout Structure

### Mobile Layout
```
┌─────────────────────────────┐
│         Header              │
│  [☰]  GnomeHub    [🔔] [👤] │
├─────────────────────────────┤
│                             │
│                             │
│         Content             │
│       (full width)          │
│                             │
│                             │
├─────────────────────────────┤
│  [🏠] [📊] [📋] [💰] [⚙️]  │
│       Bottom Nav            │
└─────────────────────────────┘
```

### Desktop Layout
```
┌──────────┬──────────────────────────────────────────────┐
│          │  Header                                      │
│          │  [Search...            ]  [🔔] [👤 User]    │
│  Drawer  ├──────────────────────────────────────────────┤
│          │                                              │
│  [Logo]  │                                              │
│          │                Content                       │
│  Menu    │              (with sidebar)                  │
│  Items   │                                              │
│          │                                              │
│          │                                              │
│          │                                              │
└──────────┴──────────────────────────────────────────────┘
```

---

## Component Structure

### Root Layout (`root.html.heex`)
```heex
<html>
  <head>
    <!-- Meta, CSS, JS -->
  </head>
  <body class="min-h-screen bg-base-200">
    <.flash_group flash={@flash} />
    {@inner_content}
  </body>
</html>
```

### App Layout (`app.html.heex`)
```heex
<div class="drawer lg:drawer-open">
  <!-- Drawer toggle -->
  <input id="drawer" type="checkbox" class="drawer-toggle" />

  <!-- Main content area -->
  <div class="drawer-content flex flex-col">
    <!-- Header -->
    <.header current_user={@current_user} />

    <!-- Page content -->
    <main class="flex-1 p-4 lg:p-6">
      {@inner_content}
    </main>

    <!-- Mobile bottom nav -->
    <.bottom_nav class="lg:hidden" />
  </div>

  <!-- Sidebar drawer -->
  <div class="drawer-side">
    <label for="drawer" class="drawer-overlay"></label>
    <.sidebar current_user={@current_user} />
  </div>
</div>
```

---

## Header Component

```heex
<header class="navbar bg-base-100 border-b">
  <!-- Mobile menu button -->
  <div class="flex-none lg:hidden">
    <label for="drawer" class="btn btn-square btn-ghost">
      <.icon name="hero-bars-3" class="h-6 w-6" />
    </label>
  </div>

  <!-- Logo -->
  <div class="flex-1">
    <a href="/" class="btn btn-ghost text-xl">GnomeHub</a>
  </div>

  <!-- Search (desktop) -->
  <div class="flex-none hidden md:block">
    <.search_input />
  </div>

  <!-- Actions -->
  <div class="flex-none gap-2">
    <.notifications_dropdown />
    <.user_menu current_user={@current_user} />
  </div>
</header>
```

---

## Sidebar Component

```heex
<aside class="bg-base-100 w-64 min-h-screen border-r">
  <!-- Logo section -->
  <div class="p-4 border-b">
    <a href="/" class="flex items-center gap-2">
      <img src="/images/logo.svg" class="h-8" />
      <span class="font-bold text-lg">GnomeHub</span>
    </a>
  </div>

  <!-- Navigation -->
  <nav class="p-4">
    <ul class="menu">
      <li><a href="/"><.icon name="hero-home" /> Dashboard</a></li>

      <li class="menu-title">Work</li>
      <li><a href="/inbox"><.icon name="hero-inbox" /> Inbox</a></li>
      <li><a href="/projects"><.icon name="hero-folder" /> Projects</a></li>
      <li><a href="/tasks"><.icon name="hero-check-circle" /> Tasks</a></li>

      <li class="menu-title">Relationships</li>
      <li><a href="/companies"><.icon name="hero-building-office" /> Companies</a></li>
      <li><a href="/contacts"><.icon name="hero-users" /> Contacts</a></li>

      <li class="menu-title">Revenue</li>
      <li><a href="/opportunities"><.icon name="hero-currency-dollar" /> Opportunities</a></li>
      <li><a href="/proposals"><.icon name="hero-document-text" /> Proposals</a></li>
      <li><a href="/invoices"><.icon name="hero-receipt-percent" /> Invoices</a></li>

      <li class="menu-title">Support</li>
      <li><a href="/tickets"><.icon name="hero-ticket" /> Tickets</a></li>
      <li><a href="/kb"><.icon name="hero-book-open" /> Knowledge Base</a></li>

      <li class="menu-title">Engineering</li>
      <li><a href="/assets"><.icon name="hero-cpu-chip" /> Assets</a></li>
      <li><a href="/plants"><.icon name="hero-building-storefront" /> Plants</a></li>
    </ul>
  </nav>
</aside>
```

---

## Bottom Navigation (Mobile)

```heex
<nav class="btm-nav btm-nav-sm">
  <button class={if @active == :home, do: "active"}>
    <.icon name="hero-home" />
    <span class="btm-nav-label">Home</span>
  </button>
  <button class={if @active == :projects, do: "active"}>
    <.icon name="hero-folder" />
    <span class="btm-nav-label">Projects</span>
  </button>
  <button class={if @active == :inbox, do: "active"}>
    <.icon name="hero-inbox" />
    <span class="btm-nav-label">Inbox</span>
  </button>
  <button class={if @active == :money, do: "active"}>
    <.icon name="hero-currency-dollar" />
    <span class="btm-nav-label">Money</span>
  </button>
  <button class={if @active == :more, do: "active"}>
    <.icon name="hero-ellipsis-horizontal" />
    <span class="btm-nav-label">More</span>
  </button>
</nav>
```

---

## Page Templates

### List Page
```heex
<div class="space-y-4">
  <!-- Page header -->
  <div class="flex justify-between items-center">
    <h1 class="text-2xl font-bold">Companies</h1>
    <.link navigate={~p"/companies/new"} class="btn btn-primary">
      <.icon name="hero-plus" /> Add Company
    </.link>
  </div>

  <!-- Filters -->
  <div class="card bg-base-100">
    <div class="card-body p-4">
      <.filter_form />
    </div>
  </div>

  <!-- Table/List -->
  <div class="card bg-base-100">
    <div class="overflow-x-auto">
      <table class="table">
        <!-- ... -->
      </table>
    </div>
  </div>

  <!-- Pagination -->
  <.pagination page={@page} total_pages={@total_pages} />
</div>
```

### Detail Page
```heex
<div class="space-y-4">
  <!-- Breadcrumb -->
  <.breadcrumb items={[
    %{label: "Companies", href: ~p"/companies"},
    %{label: @company.name}
  ]} />

  <!-- Page header -->
  <div class="flex justify-between items-center">
    <h1 class="text-2xl font-bold">{@company.name}</h1>
    <div class="flex gap-2">
      <.link navigate={~p"/companies/#{@company}/edit"} class="btn btn-ghost">
        <.icon name="hero-pencil" /> Edit
      </.link>
      <.dropdown>
        <:trigger>
          <button class="btn btn-ghost">
            <.icon name="hero-ellipsis-vertical" />
          </button>
        </:trigger>
        <:menu>
          <li><a>Archive</a></li>
          <li><a class="text-error">Delete</a></li>
        </:menu>
      </.dropdown>
    </div>
  </div>

  <!-- Content with tabs -->
  <.tabs active={@tab}>
    <:tab id="overview" label="Overview">
      <!-- Overview content -->
    </:tab>
    <:tab id="contacts" label="Contacts">
      <!-- Contacts list -->
    </:tab>
    <:tab id="activity" label="Activity">
      <!-- Activity feed -->
    </:tab>
  </.tabs>
</div>
```

---

## Responsive Utilities

```css
/* Mobile-first visibility */
.mobile-only { @apply lg:hidden; }
.desktop-only { @apply hidden lg:block; }

/* Touch-friendly targets */
.touch-target { @apply min-h-[44px] min-w-[44px]; }

/* Safe area padding (notched phones) */
.safe-bottom { @apply pb-safe; }
```

---

## Theme Support

DaisyUI themes are configured in `tailwind.config.js`:

```javascript
module.exports = {
  daisyui: {
    themes: [
      {
        gnomehub: {
          "primary": "#2563eb",
          "secondary": "#7c3aed",
          "accent": "#f59e0b",
          "neutral": "#1f2937",
          "base-100": "#ffffff",
          "info": "#3b82f6",
          "success": "#22c55e",
          "warning": "#f59e0b",
          "error": "#ef4444",
        },
      },
      "dark",
    ],
  },
}
```

### Dark Mode Toggle
```heex
<label class="swap swap-rotate">
  <input type="checkbox" class="theme-controller" value="dark" />
  <.icon name="hero-sun" class="swap-on h-6 w-6" />
  <.icon name="hero-moon" class="swap-off h-6 w-6" />
</label>
```
