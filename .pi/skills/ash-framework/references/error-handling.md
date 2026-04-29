# Ash Error Handling Patterns

## In Code (Services, Actions, etc.)

### Bang Methods — Use When You Expect Success

```elixir
# Raises on failure — use in scripts, seeds, when failure is unexpected
post = GnomeGarden.Content.get_post!(id)
GnomeGarden.Content.create_post!(%{title: "Test"}, actor: user)
```

### Ok Tuple — Use When Handling Errors

```elixir
case GnomeGarden.Content.create_post(params, actor: user) do
  {:ok, post} ->
    # Success path
    {:ok, post}

  {:error, %Ash.Error.Invalid{} = error} ->
    # Validation errors (required fields, constraints, etc.)
    errors = Ash.Error.to_error_class(error)
    {:error, errors}

  {:error, %Ash.Error.Forbidden{}} ->
    # Authorization failed
    {:error, :unauthorized}

  {:error, %Ash.Error.NotFound{}} ->
    # Record not found
    {:error, :not_found}
end
```

## In LiveViews with AshPhoenix Forms

Form errors are automatically populated when using `AshPhoenix.Form.submit/2`:

```elixir
def handle_event("save", %{"form" => params}, socket) do
  case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
    {:ok, record} ->
      {:noreply,
       socket
       |> put_flash(:info, "Created successfully")
       |> push_navigate(to: ~p"/records/#{record.id}")}

    {:error, form_with_errors} ->
      # form_with_errors has error messages attached
      # The template will render errors via <.input> automatically
      {:noreply, assign(socket, form: to_form(form_with_errors))}
  end
end
```

## In Templates

The `<.input>` component automatically displays Ash validation errors:

```heex
<.input field={@form[:title]} label="Title" />
<%!-- Errors render automatically below the input --%>
```

To show form-level errors:

```heex
<%= if @form.source.submitted_once? do %>
  <div :for={error <- AshPhoenix.Form.errors(@form.source)} class="text-red-500 text-sm">
    {error}
  </div>
<% end %>
```

## Custom Error Messages in Validations

```elixir
validations do
  validate present(:title, message: "Please provide a title")
  validate string_length(:title, min: 3, message: "Title must be at least 3 characters")
end
```

## Error Types Reference

| Error Module | When It Occurs |
|---|---|
| `Ash.Error.Invalid` | Validation failures, bad input |
| `Ash.Error.Forbidden` | Policy authorization denied |
| `Ash.Error.NotFound` | Record not found |
| `Ash.Error.Framework` | Misconfiguration, DSL errors |
| `Ash.Error.Unknown` | Unexpected errors |

## Getting Human-Readable Errors

```elixir
# Full error class with all nested errors
error_class = Ash.Error.to_error_class(error)

# List of error messages as strings
messages = Ash.Error.to_error_class(error) |> Map.get(:errors) |> Enum.map(&Exception.message/1)
```
