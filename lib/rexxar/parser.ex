defmodule Rexxar.Parser do
  defstruct [:ctx, :stack]

  @new_ctx {:head, ""}
  @initial_parse_state {@new_ctx, []}

  def new do
    %Rexxar.Parser{ctx: @new_ctx, stack: []}
  end

  def push_array(%__MODULE__{stack: t} = s, len) do
    %__MODULE__{s| stack: [{[], len}| t], ctx: @new_ctx}
  end

  def push_bulk(%__MODULE__{} = s, len) do
    %__MODULE__{s| ctx: {:bulk, "", len}}
  end

  def parse(<<"\n", t::binary>>, {:head, head}) do
    case parse_head(head) do
      {:array, n} -> {:array, n, t}
      {:bulk, n} -> {:bulk, n, t}
      n -> {:ok, n, t}
    end
  end

  #binaries can have \r\n
  def parse(<<h, t::binary>>, {:bulk, value, 1} = ctx) do
    parse(t, {:bulk, <<value::binary, h>>})
  end
  def parse(<<h, t::binary>>, {:bulk, value, left} = ctx) do
    parse(t, {:bulk, <<value::binary, h>>, left-1})
  end

  def parse(<<"\r", t::binary>>, ctx) do
    parse(t, ctx)
  end
  def parse(<<"\n", t::binary>>, ctx) do
    {:ok, ctx, t}
  end

  def parse(<<h, t::binary>>, {:head, head} = ctx) do
    parse(t, {:head, <<head::binary, h>>})
  end

  def parse(<<>>, ctx) do
    {:end, ctx}
  end

  def parse(%__MODULE__{ctx: ctx, stack: stack} = parser, t) do
    case parse(t, ctx) do
      {:array, len, t} -> parse(push_array(parser, len), t)

      {:bulk, len, t} -> parse(push_bulk(parser, len), t)

      #end of frame, keep parsing next frame
      {:end, ctx} -> {:end, %__MODULE__{parser| ctx: ctx}}

      #done parsing current value
      {:ok, ctx, t} ->
        case merge(ctx, stack) do
          #done with a simple value or array
          {:ok, value} -> {:value, value, t}

          #inserted into array, but not done
          {:merged, stack} -> parse(%__MODULE__{stack: stack, ctx: @new_ctx}, t)
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
  #TODO: return error to caller
  def parse_head("-" <> line) do
    {:string, line}
  end

  def merge({type, value}, []) do
    case type do
      :bulk -> {:ok, value}
      :string -> {:ok, value}
      :int -> {:ok, value}
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
