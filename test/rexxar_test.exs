defmodule RexxarTest do
  use ExUnit.Case
  doctest Rexxar

  test "the truth" do
    assert 1 + 1 == 2
  end

  test "parse nested array" do
    s = "*2\r\n*3\r\n:1\r\n:2\r\n:3\r\n*2\r\n+Foo\r\n+Bar\r\n"
    r = [[1,2,3], ["Foo", "Bar"]]
    {:value, result, _} = Rexxar.Connection.do_parse(s, {:head, ""}, [])
    assert result == r
  end

  test "split nested array" do
    s1 = "*2\r\n*3\r\n:1\r\n:2\r\n:"
    s2 = "3\r\n*2\r\n+Foo\r\n+Bar\r\n"
    r = [[1,2,3], ["Foo", "Bar"]]
    {:end, ctx, stack} = Rexxar.Connection.do_parse(s1, {:head, ""}, [])
    {:value, result, _} = Rexxar.Connection.do_parse(s2, ctx, stack)
    assert result == r
  end
end
