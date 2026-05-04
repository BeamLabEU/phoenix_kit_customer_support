defmodule PhoenixKitCustomerSupport.DataCase do
  @moduledoc """
  Test case for tests requiring database access. Tests using this case are
  tagged `:integration` and will be automatically excluded when the database
  is unavailable.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      @moduletag :integration

      alias PhoenixKitCustomerSupport.Test.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
    end
  end

  alias Ecto.Adapters.SQL.Sandbox
  alias PhoenixKitCustomerSupport.Test.Repo, as: TestRepo

  setup tags do
    pid = Sandbox.start_owner!(TestRepo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    :ok
  end
end
