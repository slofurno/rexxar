defmodule Rexxar.Connection do
  use GenServer
  import Record

  defrecord :state, [:port]

  def start_link() do
    GenServer.start_link(__MODULE__, [])
  end

  def init(_) do
    {:ok, port} = :gen_tcp.connect('localhost', 6379, [])
    :inet.setopts(port, [:binary, {:active, true}])
    {:ok, state(port: port)}
  end

  def handle_cast({:send, msg}, state(port: port) = s) do
    :ok = :gen_tcp.send(port, msg)
    {:noreply, s}
  end

  def handle_info({:tcp, tcp_port, msg}, state(port: port) = s) when tcp_port == port do
    IO.inspect(msg)
    {:noreply, s}
  end

  def parse(<<"\n", t::binary>>, {:head, head}) do
    case parse_head(head) do
      {:array, n} -> {:array, n, t}
      {:bulk, n} -> {:bulk, n, t}
      n -> {:ok, n, t}
    end
  end

  def parse(<<"\r", t::binary>>, stack) do
    parse(t, stack)
  end

  def parse(<<"\n", t::binary>>, stack) do
    {:ok, stack, t}
  end

  def parse(<<h, t::binary>>, {:head, head} = ctx) do
    parse(t, {:head, <<head::binary, h>>})
  end

  def parse(<<h, t::binary>>, {:bulk, value, 1} = ctx) do
    parse(t, {:bulk, <<value::binary, h>>})
  end

  def parse(<<h, t::binary>>, {:bulk, value, left} = ctx) do
    parse(t, {:bulk, <<value::binary, h>>, left-1})
  end

  def parse(<<>>, ctx) do
    {:end, ctx}
  end

  @new_ctx {:head, ""}

  def do_parse(t, ctx, stack) do
    case parse(t, ctx) do
      {:array, len, t} -> do_parse(t, {:head, ""}, [{[], len}|stack])

      {:bulk, len, t} -> do_parse(t, {:bulk, "", len}, stack)
      #end of frame, keep parsing next frame
      {:end, ctx} -> {:end, ctx, stack}
      #done parsing this value
      {:ok, ctx, t} ->
        case merge(ctx, stack) do
          #done with a simple value
          {:ok, value} -> {:value, value, t}
          #inserted into array, but not done
          {:merged, stack} -> do_parse(t, @new_ctx, stack)
        end
    end
  end

  def parse_head("+" <> line) do
    {:string, line}
  end
  def parse_head(":" <> line) do
    {:int, parse_int(line)}
  end
  def parse_head("$" <> line) do
    {:bulk, parse_int(line)}
  end
  def parse_head("*" <> line) do
    {:array, parse_int(line)}
  end

  def merge({type, value}, []) do
    case type do
      :bulk -> {:ok, value}
      :string -> {:ok, value}
      :int -> {:ok, parse_int(value)}
      :array -> {:ok, value}
    end
  end

  #insert into array, pop and insert into parent
  def merge({type, value}, [{children, 1}|t]) do
    res = Enum.reverse([value|children])
    merge({:array, res}, t)
  end

  #insert into array, keep going
  def merge({type, value}, [{children, n}|t]) do
    {:merged, [ {[value| children], n-1} | t]}
  end

  defp parse_int(n) do
    {i, _} = Integer.parse(n)
    i
  end
end
