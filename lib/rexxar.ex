defmodule Rexxar do
  def start_link() do
    Rexxar.Connection.start_link()
  end

  def command(conn, command) do
    Rexxar.Connection.command(conn, command)
  end
end
