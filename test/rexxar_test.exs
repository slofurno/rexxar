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

  def epoch do
    :os.system_time(:milli_seconds)
  end

  test "incr bench" do
    {:ok, p} = Rexxar.Connection.start_link
    Rexxar.Connection.send(p, ["SET", "aaaa", "0"])
    t0 = epoch()
    tasks = Enum.map(1..10000, fn x ->
      Task.async(fn -> Rexxar.Connection.send(p, ["INCR", "aaaa"]) end)
    end)

    Task.yield_many(tasks)
    t1 = epoch()
    IO.inspect(t1-t0)
  end

  @new_ctx {:head, ""}
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
    Rexxar.Connection.send(p, ["SET", "aaaa", str])

    tasks = Enum.map(1..1000, fn x ->
      Task.async(fn -> Rexxar.Connection.send(p, ["GET", "aaaa"]) end)
    end)

    Task.yield_many(tasks)
    t1 = epoch()
    IO.inspect(t1-t0)
  end
end
