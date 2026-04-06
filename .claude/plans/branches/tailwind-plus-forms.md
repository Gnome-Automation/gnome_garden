# Branch: feature/tailwind-plus-forms

## Goal
Restyle all forms to use Tailwind Plus stacked form patterns with proper dark mode. Replace DaisyUI form classes with Tailwind Plus throughout. Use emerald accent color (garden theme).

## Approach

### 1. Update `<.input>` in CoreComponents
This is the single point of change that affects every form. The current `<.input>` component uses DaisyUI classes.

**File:** `lib/garden_web/components/core_components.ex`

**New input classes:**
```
rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-gray-500 dark:focus:outline-emerald-500
```

**Label classes:** `block text-sm/6 font-medium text-gray-900 dark:text-white`

**Select:** Same as input + `appearance-none` with chevron SVG overlay in a grid wrapper

**Textarea:** Same input classes, ensure proper sizing

**Error styling:** Red outline + error message below

### 2. Update form layouts
Each form page should use sectioned grid layout:

```heex
<div class="border-b border-gray-900/10 pb-12 dark:border-white/10">
  <h2 class="text-base/7 font-semibold text-gray-900 dark:text-white">Section Title</h2>
  <p class="mt-1 text-sm/6 text-gray-600 dark:text-gray-400">Description</p>
  <div class="mt-10 grid grid-cols-1 gap-x-6 gap-y-8 sm:grid-cols-6">
    <!-- fields -->
  </div>
</div>
```

**Button classes:**
- Primary: `rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500 dark:bg-emerald-500`
- Cancel: `text-sm/6 font-semibold text-gray-900 dark:text-white`

### 3. Forms to update
- `lib/garden_web/live/crm/company_live/form.ex`
- `lib/garden_web/live/crm/contact_live/form.ex`
- `lib/garden_web/live/crm/lead_live/form.ex`
- `lib/garden_web/live/crm/opportunity_live/form.ex`
- `lib/garden_web/live/crm/task_live/form.ex`
- Review Queue dialogs in `lib/garden_web/live/crm/review_live.ex`
- Bid detail dialogs in `lib/garden_web/live/agents/sales/bid_live/show.ex`

### 4. AshPhoenix form pattern
All forms must use the AshPhoenix pattern:
```elixir
# Mount
form = Sales.form_to_create_company(actor: actor)
assign(socket, form: to_form(form))

# Validate
form = AshPhoenix.Form.validate(socket.assigns.form, params)

# Submit
AshPhoenix.Form.submit(socket.assigns.form, params: params)
```

Exception: pursue/pass/park dialogs use plain `<form>` since they call `accept_review_item` directly (not AshPhoenix.Form.submit).

## Key Reference
See CLAUDE.md for the full style specification. The user provided the Tailwind Plus "stacked form" layout as the reference pattern.

## Testing
1. Check every form in light + dark mode
2. Verify AshPhoenix validation shows errors properly
3. Verify select dropdowns have the chevron SVG
4. Mobile responsive — forms should stack properly
5. Dialog forms (pursue/pass/park) match the same style
