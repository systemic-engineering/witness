defmodule Witness.Repo do
  @moduledoc """
  Macro for defining a Witness-backed Ecto.Repo.

  ## Usage

      defmodule MyApp.WitnessRepo do
        use Witness.Repo
      end

  Defaults to `Witness.Adapter.Mnesia` (in-memory). For git-backed persistence:

      defmodule MyApp.WitnessRepo do
        use Witness.Repo, adapter: Fragmentation.Store.Git
      end
  """

  defmacro __using__(opts \\ []) do
    adapter = Keyword.get(opts, :adapter, Witness.Adapter.Mnesia)
    otp_app = Keyword.get(opts, :otp_app, :witness)

    quote do
      use Ecto.Repo,
        otp_app: unquote(otp_app),
        adapter: unquote(adapter)
    end
  end
end
