defmodule RexxarTest do
  use ExUnit.Case
  doctest Rexxar

  alias Rexxar.Parser

  test "the truth" do
    assert 1 + 1 == 2
  end

  test "parse nested array" do
    s = "*2\r\n*3\r\n:1\r\n:2\r\n:3\r\n*2\r\n+Foo\r\n+Bar\r\n"
    r = [[1,2,3], ["Foo", "Bar"]]
    parser = Parser.new()
    {:value, result, _} = Parser.parse(parser, s)
    assert result == r
  end

  test "split nested array" do
    s1 = "*2\r\n*3\r\n:1\r\n:2\r\n:"
    s2 = "3\r\n*2\r\n+Foo\r\n+Bar\r\n"
    r = [[1,2,3], ["Foo", "Bar"]]
    parser = Parser.new()
    {:end, parser} = Parser.parse(parser, s1)
    {:value, value, _} = Parser.parse(parser, s2)
    assert value == r
  end

  test "parse missing key" do
    parser = Parser.new()
    {:value, :nil, ""} = Parser.parse(parser, "$-1\r\n")
  end

  def epoch do
    :os.system_time(:milli_seconds)
  end

  #  test "incr bench" do
  #    {:ok, p} = Rexxar.Connection.start_link
  #    Rexxar.Connection.command(p, ["SET", "aaaa", "0"])
  #    t0 = epoch()
  #    tasks = Enum.map(1..10000, fn x ->
  #      Task.async(fn -> Rexxar.Connection.command(p, ["INCR", "aaaa"]) end)
  #    end)
  #
  #    Task.yield_many(tasks)
  #    t1 = epoch()
  #    IO.inspect(t1-t0)
  #  end

  test "binary safe string w/ crlf" do
    msg = "ASDF\r\nGGGG"
    pmsg = "$10\r\n" <> msg <> "\r\n"

    parser = Parser.new()
    {:value, value, ""} = Parser.parse(parser, pmsg)
    assert value == msg
  end

  test "get long string bench" do
    {:ok, p} = Rexxar.Connection.start_link
    t0 = epoch()

    str = Enum.reduce(1..10, "ASDF ASDF GDF gdfg dfg\r\n", fn _, a -> a <> a end)
    Rexxar.Connection.command(p, ["SET", "aaaa", str])

    tasks = Enum.map(1..100, fn x ->
      Task.async(fn -> Rexxar.Connection.command(p, ["GET", "aaaa"]) end)
    end)

    Task.yield_many(tasks)
    t1 = epoch()
    IO.inspect(t1-t0)
  end


  defp parse_all(parser, [x|xs]) do
    case Parser.parse(parser, x) do
      {:value, value, ""} -> value
      {:end, parser} -> parse_all(parser, xs)
    end
  end

  #1315, 1364, 1305, 1311, 1306
  #1242
  test "bulk string bench" do
    str = Enum.reduce(1..10, "ASDF ASDF GDF gdfg dfg\r\n", fn _, a -> a <> a end)
    parts = ["$#{byte_size(str)*5}\r\n",
     str,
     str,
     str,
     str,
     str,
     "\r\n"
   ]
    parser = Parser.new()
    t0 = epoch()
    Enum.each(1..100, fn _ -> parse_all(parser, parts) end)
    t1 = epoch()
    IO.inspect(t1-t0)
  end

  # we dont always get the expected incr results, but that
  # is because some of our calls are received out of order
  #  test "pipelining recv order" do
  #    {:ok, p} = Rexxar.Connection.start_link
  #    Rexxar.Connection.command(p, ~w(SET aaaa 0))
  #
  #    tasks = Enum.map(1..1000, fn x ->
  #      Task.async(fn ->
  #        Rexxar.Connection.command(p, ~w(INCR aaaa), x)
  #      end)
  #    end)
  #
  #    results = Task.yield_many(tasks)
  #    |> Enum.map(fn {_, {:ok, result}} -> result end)
  #
  #    {_, _, _, _, xs} = GenServer.call(p, :state)
  #
  #    Enum.zip(1..1000, Enum.reverse(xs))
  #    |> Enum.filter(fn {result, order} ->
  #      result != order
  #    end)
  #    |> IO.inspect
  #  end

  test "pipeline resp order" do
    {:ok, p} = Rexxar.Connection.start_link
    keys = for a <- ?A..?Z, b <- ?A..?Z, c <- ?A..?G, do: <<a, b, c>>

    Enum.each(keys, fn x ->
      Rexxar.Connection.command(p, ~w(SET #{x} #{x}))
    end)

    tasks = Enum.map(keys, fn x ->
      Task.async(fn ->
        assert Rexxar.Connection.command(p, ~w(GET #{x})) == x
      end)
    end)

    Task.yield_many(tasks)
  end
end
