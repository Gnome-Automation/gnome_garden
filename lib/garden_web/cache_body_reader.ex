defmodule GnomeGardenWeb.CacheBodyReader do
  @moduledoc """
  Plug body reader that caches the raw request body into `conn.assigns[:raw_body]`
  before Plug.Parsers consumes it.

  Required for Mercury webhook signature verification, which must compare an HMAC
  computed over the exact raw bytes Mercury sent.
  """

  @spec read_body(Plug.Conn.t(), keyword()) :: {:ok, binary(), Plug.Conn.t()}
  def read_body(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
    conn = Plug.Conn.assign(conn, :raw_body, body)
    {:ok, body, conn}
  end
end
