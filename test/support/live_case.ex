defmodule PhoenixKitCustomerSupport.LiveCase do
  @moduledoc """
  Test case for the public guest pages: the test endpoint,
  `Phoenix.LiveViewTest`, and the SQL sandbox (tagged `:integration`).
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      @moduletag :integration
      @endpoint PhoenixKitCustomerSupport.Test.Endpoint

      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest

      alias PhoenixKitCustomerSupport.Test.Repo
    end
  end

  alias Ecto.Adapters.SQL.Sandbox
  alias PhoenixKitCustomerSupport.Test.Repo, as: TestRepo

  setup tags do
    pid = Sandbox.start_owner!(TestRepo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    {:ok, conn: Phoenix.ConnTest.build_conn() |> Plug.Test.init_test_session(%{})}
  end
end
