defmodule Rexxar.Parser do

  @type bulk_ctx :: {:bulk, String.t, integer}
  @type head_ctx :: {:head, String.t}

  @type stack_frame :: {[any()], integer}

  defstruct [:ctx, :stack]

  @type t :: %__MODULE__{
    ctx: bulk_ctx | head_ctx,
    stack: [stack_frame] | []
  }

  @head_ctx {:head, ""}

  def new do
    %__MODULE__{ctx: @head_ctx, stack: []}
  end

  @type end_of_line :: {:end, t}
  @type parsed_value :: {:value, any(), String.t}

  @spec parse(t, String.t) :: end_of_line | parsed_value
  def parse(%__MODULE__{ctx: ctx, stack: stack}, t) do
    case parse_one(t, ctx, stack) do
      #end of frame, keep parsing next frame
      {:end, ctx, stack} -> {:end, %__MODULE__{ctx: ctx, stack: stack}}

      {:value, value, t} -> {:value, value, t}
    end
  end
  defp make_stack_frame(n) do
    {[], n}
  end

  defp parse_one(<<"\n", t::binary>>, {:head, head}, stack) do
    case parse_head(head) do
      {:array, n} -> parse_one(t, @head_ctx, [make_stack_frame(n)|stack])
      {:bulk, n} -> parse_one(t, {:bulk, "", n}, stack)
      ctx -> merge(t, ctx, stack)
    end
  end
  #binaries can have \r\n - match on len
  defp parse_one(<<h, t::binary>>, {:bulk, value, 1}, stack) do
    parse_one(t, {:bulk, <<value::binary, h>>}, stack)
  end
  #nil value has no body
  defp parse_one(t, {:bulk, value, -1} = ctx, stack) do
    merge(t, {:bulk, :nil}, stack)
  end
  defp parse_one(<<h, t::binary>>, {:bulk, value, left}, stack) do
    parse_one(t, {:bulk, <<value::binary, h>>, left-1}, stack)
  end
  defp parse_one(<<"\r", t::binary>>, ctx, stack) do
    parse_one(t, ctx, stack)
  end
  defp parse_one(<<"\n", t::binary>>, ctx, stack) do
    merge(t, ctx, stack)
  end
  defp parse_one(<<h, t::binary>>, {:head, head}, stack) do
    parse_one(t, {:head, <<head::binary, h>>}, stack)
  end
  defp parse_one(<<>>, ctx, stack) do
    {:end, ctx, stack}
  end

  defp parse_head("+" <> line) do
    {:string, line}
  end
  defp parse_head(":" <> line) do
    {:int, parse_int(line)}
  end
  defp parse_head("$" <> line) do
    {:bulk, parse_int(line)}
  end
  defp parse_head("*" <> line) do
    {:array, parse_int(line)}
  end
  #TODO: return error to caller
  defp parse_head("-" <> line) do
    {:string, line}
  end

  defp merge(<<t::binary>>, {type, value}, []) do
    case type do
      :bulk -> {:value, value, t}
      :string -> {:value, value, t}
      :int -> {:value, value, t}
      :array -> {:value, value, t}
    end
  end

  #insert into array, pop and insert into parent
  defp merge(<<t::binary>>, {_type, value}, [{children, 1}| rest]) do
    res = Enum.reverse([value|children])
    merge(t, {:array, res}, rest)
  end
  #insert into array, keep going
  defp merge(<<t::binary>>, {_type, value}, [{children, n}| rest]) do
    stack = [ {[value| children], n-1} | rest]
    parse_one(t, @head_ctx, stack)
  end
  defp parse_int(n) do
    {i, _} = Integer.parse(n)
    i
  end

  def format_message(msg) when is_list(msg) do
    ["*#{Enum.count(msg)}\r\n"| Enum.map(msg, &format_message/1)]
  end
  def format_message(msg) when is_binary(msg) do
    "$#{byte_size(msg)}\r\n" <> msg <> "\r\n"
  end
  def format_message(msg) when is_integer(msg) do
    ":#{msg}\r\n"
  end
end
