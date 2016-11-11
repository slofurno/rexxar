defmodule Rexxar.Connection do
  use GenServer
  import Record, only: [defrecord: 2]

  alias Rexxar.Parser

  defrecord :state, [:port, :froms, :parser]

  def start_link() do
    GenServer.start_link(__MODULE__, [])
  end

  def init(_) do
    {:ok, port} = :gen_tcp.connect('localhost', 6379, [])
    :ok = :inet.setopts(port, [:binary, {:active, :once}])
    {:ok, state(port: port, froms: :queue.new, parser: Parser.new)}
  end

  def command(pid, command) do
    GenServer.call(pid, {:command, command}, :infinity)
  end

  def handle_call({:command, command}, from, state(port: port, froms: froms) = s) do
    :ok = :gen_tcp.send(port, Parser.format_message(command))
    {:noreply, state(s, froms: :queue.in(from, froms))}
  end

  def handle_call(:state, _from, s) do
    {:reply, s, s}
  end

  def handle_info({:tcp, tcp_port, msg}, state(port: port, parser: parser, froms: froms) = s)
      when tcp_port == port do
    :ok = :inet.setopts(port, [{:active, :once}])
    {:ok, parser, froms} = parse_and_reply(parser, msg, froms)
    {:noreply, state(s, parser: parser, froms: froms)}
  end

  #TODO: extract connect, backoff, either error or retry for existing sends
  def handle_info({:tcp_closed, tcp_port}, state(port: port)) when tcp_port == port do
    {:ok, s} = init(0)
    {:noreply, s}
  end

  def handle_info({:do_connect}, s) do
    {:noreply, s}
  end

  def handle_info(_, s) do
    {:noreply, s}
  end

  def parse_and_reply(%Parser{} = parser, msg, froms) do
    case Parser.parse(parser, msg) do
      {:value, result, t} ->
        {{:value, from}, froms} = :queue.out(froms)
        GenServer.reply(from, result)
        parse_and_reply(Parser.new, t, froms)

      {:end, parser} -> {:ok, parser, froms}
    end
  end

end
