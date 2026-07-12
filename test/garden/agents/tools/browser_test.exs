defmodule GnomeGarden.BrowserTest do
  use ExUnit.Case, async: false

  alias GnomeGarden.Browser
  alias GnomeGarden.Browser.{Error, SessionManager}
  alias Jido.Browser.Session

  @moduletag :tmp_dir

  defmodule FakeAdapter do
    @behaviour Jido.Browser.Adapter

    @impl true
    def start_session(opts) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      send(test_pid, {:browser_started, opts})
      Session.new!(%{adapter: __MODULE__, connection: %{test_pid: test_pid}})
    end

    @impl true
    def end_session(session) do
      send(test_pid(session), :browser_ended)
      :ok
    end

    @impl true
    def navigate(session, url, opts) do
      send(test_pid(session), {:browser_navigate, url, opts})
      {:ok, session, %{"url" => url, "title" => "Adapter Title"}}
    end

    @impl true
    def evaluate(session, script, opts) do
      send(test_pid(session), {:browser_evaluate, script, opts})

      result =
        cond do
          String.contains?(script, "querySelectorAll('a[href]')") ->
            %{
              "url" => "https://example.test/final",
              "title" => "Snapshot Title",
              "text" => "abcdefghij",
              "links" => [%{"href" => "/1"}, %{"href" => "/2"}, %{"href" => "/3"}],
              "headings" => ["One", "Two"],
              "forms" => [%{"action" => "/submit"}]
            }

          String.contains?(script, "arrayBuffer") ->
            %{"ok" => true, "base64" => Base.encode64("downloaded")}

          true ->
            %{"evaluated" => true}
        end

      {:ok, session, %{"result" => result}}
    end

    @impl true
    def click(session, _selector, _opts), do: {:ok, session, %{}}

    @impl true
    def type(session, _selector, _text, _opts), do: {:ok, session, %{}}

    @impl true
    def screenshot(session, _opts), do: {:ok, session, %{bytes: <<>>, mime: "image/png"}}

    @impl true
    def extract_content(session, _opts), do: {:ok, session, %{content: "", format: :text}}

    defp test_pid(session), do: session.connection.test_pid
  end

  defmodule FailingAdapter do
    @behaviour Jido.Browser.Adapter

    @impl true
    def start_session(opts) do
      Session.new!(%{
        adapter: __MODULE__,
        connection: %{test_pid: Keyword.fetch!(opts, :test_pid)}
      })
    end

    @impl true
    def end_session(_session), do: :ok

    @impl true
    def navigate(_session, _url, _opts), do: {:error, :navigation_failed}

    @impl true
    def click(session, _selector, _opts), do: {:ok, session, %{}}

    @impl true
    def type(session, _selector, _text, _opts), do: {:ok, session, %{}}

    @impl true
    def screenshot(session, _opts), do: {:ok, session, %{bytes: <<>>, mime: "image/png"}}

    @impl true
    def extract_content(session, _opts), do: {:ok, session, %{content: "", format: :text}}
  end

  defmodule FakeFetchClient do
    def web_fetch(url, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:web_fetch, url, opts})
      {:ok, %{url: url, content: "abcdefghij", truncated: false, format: :text}}
    end
  end

  setup do
    original_client = Application.get_env(:gnome_garden, :browser_client)
    original_adapter = Application.get_env(:gnome_garden, :browser_adapter)
    original_options = Application.get_env(:gnome_garden, :browser_session_options)

    :ok = SessionManager.reset()
    Application.put_env(:gnome_garden, :browser_client, Jido.Browser)
    Application.put_env(:gnome_garden, :browser_adapter, FakeAdapter)
    Application.put_env(:gnome_garden, :browser_session_options, test_pid: self())

    on_exit(fn ->
      _ = SessionManager.reset()
      restore_env(:browser_client, original_client)
      restore_env(:browser_adapter, original_adapter)
      restore_env(:browser_session_options, original_options)
    end)

    :ok
  end

  test "reuses one explicit Jido session across navigation and evaluation" do
    assert {:ok, navigation} = Browser.navigate("https://example.test", wait_for_network: false)
    assert navigation.title == "Adapter Title"
    assert_received {:browser_started, _opts}
    assert_received {:browser_navigate, "https://example.test", navigate_opts}
    assert navigate_opts[:wait_until] == "load"

    assert {:ok, %{"evaluated" => true}} = Browser.evaluate("document.title")
    assert_received {:browser_evaluate, "document.title", _opts}
    refute_received {:browser_started, _opts}

    assert :ok = Browser.close()
    assert_received :browser_ended
  end

  test "isolates concurrent callers and closes sessions when owners exit" do
    tasks =
      for index <- 1..2 do
        Task.async(fn -> Browser.navigate("https://example.test/#{index}") end)
      end

    results = Enum.map(tasks, &Task.await/1)
    assert Enum.all?(results, &match?({:ok, _navigation}, &1))
    assert_receive {:browser_started, _opts}
    assert_receive {:browser_started, _opts}
    assert_receive :browser_ended
    assert_receive :browser_ended
  end

  test "returns a bounded browser snapshot" do
    assert {:ok, snapshot} =
             Browser.inspect_page("https://example.test", max_links: 2, max_text_chars: 5)

    assert snapshot.final_url == "https://example.test/final"
    assert snapshot.title == "Snapshot Title"
    assert snapshot.text == "abcde"
    assert length(snapshot.links) == 2
    assert length(snapshot.forms) == 1
  end

  test "downloads through the authenticated page session", %{tmp_dir: tmp_dir} do
    target = Path.join(tmp_dir, "download.bin")

    assert :ok = Browser.download("#download", target)
    assert File.read!(target) == "downloaded"
    assert_received {:browser_evaluate, script, _opts}
    assert script =~ ~s|document.querySelector("#download")|
    assert script =~ "credentials: \"include\""
  end

  test "bounds stateless Jido web fetch output" do
    assert {:ok, result} =
             Browser.web_fetch("https://example.test/document",
               client: FakeFetchClient,
               test_pid: self(),
               max_content_chars: 5,
               format: :text
             )

    assert result.content == "abcde"
    assert result.truncated
    assert_received {:web_fetch, "https://example.test/document", opts}
    assert opts[:max_content_tokens] == 1
  end

  test "normalizes adapter failures into structured facade errors" do
    assert {:error, %Error{operation: :navigate, reason: :navigation_failed}} =
             Browser.navigate("https://example.test", adapter: FailingAdapter)
  end

  defp restore_env(key, nil), do: Application.delete_env(:gnome_garden, key)
  defp restore_env(key, value), do: Application.put_env(:gnome_garden, key, value)
end
