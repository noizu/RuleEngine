defmodule Noizu.RuleEngine.Op.ComparisonOp do
  @type t :: %__MODULE__{
    name: String.t | nil,
    description: String.t | nil,
    identifier: String.t | list | tuple, # Materialized Path.
    arguments: list,
    comparison: :"==" | :"<>" | :"<=" | :">=" | :"<" | :">",
    settings: Keyword.t,
  }

  defstruct [
    name: nil,
    description: nil,
    identifier: nil,
    arguments: [],
    settings: [short_circuit?: :auto, async?: :auto, raise_on_timeout?: :auto, comparison_strategy: :default]
  ]
end

defimpl Noizu.RuleEngine.ScriptProtocol, for: Noizu.RuleEngine.Op.ComparisonOp do
  alias Noizu.RuleEngine.Helper

  #-----------------
  # execute!/3
  #-----------------
  def execute!(this, state, context), do: execute!(this, state, context, %{})

  #-----------------
  # execute!/4
  #-----------------
  def execute!(this, state, context, options) do
    cond do
      this.settings[:short_circuit?] == :required -> execute!(:short_circuit, this, state, context, options) # Ignore Async settings when short_circuit is mandatory
      Enum.member?([true, :auto, :required], this.settings[:async?]) && (options[:settings][:supports_async?] == true) -> execute!(:async, this, state, context, options)
      this.settings[:async?] == :required -> raise "[ScriptError] Unable to perform required async execute on #{this.__struct__} - #{identifier(this, state, context)}"
      Enum.member?([true, :auto, nil], this.settings[:short_circuit?]) -> execute!(:short_circuit, this, state, context, options)
      true -> execute!(:all, this, state, context, options)
    end
  end

  #-----------------
  # execute!/5
  #-----------------
  def execute!(:short_circuit, this, state, context, options) do
    n_children = length(this.arguments || [])
    cond do
      n_children < 2 -> {false, state}
      true ->
        [h|t] = this.arguments
        p = Noizu.RuleEngine.ScriptProtocol.execute!(h, state, context, options)
        cs = this.settings[:comparison_strategy] || :default
        {sentinel, {_o, updated_state}} = Enum.reduce(t, {true, p},
          fn(child, {sentinel, {o, s}}) ->
            if sentinel do
              {c_o, c_s} = Noizu.RuleEngine.ScriptProtocol.execute!(child, s, context, options)
              cond do
                cs == :default ->
                    c = case this.comparison do
                      :"==" -> o == c_o
                      :"<>" -> o != c_o
                      :"<" -> o < c_o
                      :">" -> o > c_o
                      :"<=" -> o <= c_o
                      :">=" -> o >= c_o
                    end
                    {c, {c_o, c_s}}

                is_tuple(cs) ->
                  {m, f, a} = cs
                  cond do
                    a == 2 ->
                      cc = :erlang.apply(m, f, [o, c_o])
                      c = cc == this.comparison
                      {c, c_o}

                    a == 5 ->
                      {cc, cc_s} = :erlang.apply(m, f, [o, c_o, state, context, options])
                      c = cc == this.comparison
                      {c, {c_o, cc_s}}
                  end

                is_function(cs, 2) ->
                  cc = cs.(o, c_o)
                  c = cc == this.comparison
                  {c, {c_o, c_s}}

                is_function(cs, 5) ->
                  {cc, cc_s} = cs.(o, c_o, state, context, options)
                  c = cc == this.comparison
                  {c, {c_o, cc_s}}
                true ->
                  {false, {o, s}}
              end
            else
              {sentinel, {o, s}}
            end
          end
        )
        {sentinel, updated_state}
    end
  end

  def execute!(:all, this, state, context, options) do
    n_children = length(this.arguments || [])
    cond do
      n_children < 2 -> {false, state}
      true ->
        [h|t] = this.arguments
        p = Noizu.RuleEngine.ScriptProtocol.execute!(h, state, context, options)
        cs = this.settings[:comparison_strategy] || :default
        {sentinel, {_o, updated_state}} = Enum.reduce(t, {true, p},
          fn(child, {sentinel, {o, s}}) ->
            if sentinel do
              {c_o, c_s} = Noizu.RuleEngine.ScriptProtocol.execute!(child, s, context, options)
              cond do
                cs == :default ->
                  c = case this.comparison do
                    :"==" -> o == c_o
                    :"<>" -> o != c_o
                    :"<" -> o < c_o
                    :">" -> o > c_o
                    :"<=" -> o <= c_o
                    :">=" -> o >= c_o
                  end
                  {c, {c_o, c_s}}

                is_tuple(cs) ->
                  {m, f, a} = cs
                  cond do
                    a == 2 ->
                      cc = :erlang.apply(m, f, [o, c_o])
                      c = cc == this.comparison
                      {c, c_o}

                    a == 5 ->
                      {cc, cc_s} = :erlang.apply(m, f, [o, c_o, state, context, options])
                      c = cc == this.comparison
                      {c, {c_o, cc_s}}
                  end

                is_function(cs, 2) ->
                  cc = cs.(o, c_o)
                  c = cc == this.comparison
                  {c, {c_o, c_s}}

                is_function(cs, 5) ->
                  {cc, cc_s} = cs.(o, c_o, state, context, options)
                  c = cc == this.comparison
                  {c, {c_o, cc_s}}
                true ->
                  {false, {o, s}}
              end
            else
              {_, c_s} = Noizu.RuleEngine.ScriptProtocol.execute!(child, s, context, options)
              {sentinel, {o, c_s}}
            end
          end
        )
        {sentinel, updated_state}
    end
  end

  def execute!(:async, this, state, context, options) do
    n_children = length(this.arguments || [])
    cond do
      n_children < 2 -> {false, state}
      true ->
        yield_wait = this.settings[:timeout] || options[:timeout] || 15_000
        children = this.arguments
                   |> Enum.map(fn(child) -> Task.async(&(Noizu.RuleEngine.ScriptProtocol.execute!(child, state, context, options))) end)
                   |> Task.yield_mand(yield_wait)
                   |> Enum.reduce([],
                        fn({task, res}, acc) ->
                          case res do
                            {:ok, {o, _s}} ->
                              case acc do
                                {:error, {Noizu.RuleEngine.ScriptProtocol, {:timeout, _task}}} -> acc
                                _ -> acc ++ [o]
                              end
                            _ ->
                              Task.shutdown(task, yield_wait)
                              {:error, {Noizu.RuleEngine.ScriptProtocol, {:timeout, task}}}
                          end
                        end)

        case children do
          {:error, {Noizu.RuleEngine.ScriptProtocol, {:timeout, task}}} ->
              raise "[ScriptError] - #{identifier(this)} Execute Child Task Failed to Complete #{inspect task}"
          [h|t] ->
            cs = this.settings[:comparison_strategy] || :default
            {outcome, _} = Enum.reduce(t, {true, h},
              fn(c_o, {sentinel, o}) ->
                if sentinel do
                  cond do
                    cs == :default ->
                      c = case this.comparison do
                        :"==" -> o == c_o
                        :"<>" -> o != c_o
                        :"<" -> o < c_o
                        :">" -> o > c_o
                        :"<=" -> o <= c_o
                        :">=" -> o >= c_o
                      end
                      {c, c_o}
                    is_tuple(cs) ->
                      {m, f, a} = cs
                      cond do
                        a == 2 ->
                          cc = :erlang.apply(m, f, [o, c_o])
                          c = cc == this.comparison
                          {c, c_o}

                        a == 5 ->
                          {cc, _cc_s} = :erlang.apply(m, f, [o, c_o, state, context, options])
                          c = cc == this.comparison
                          {c, c_o}
                      end

                    is_function(cs, 2) ->
                      cc = cs.(o, c_o)
                      c = cc == this.comparison
                      {c, c_o}

                    is_function(cs, 5) ->
                      {cc, _cc_s} = cs.(o, c_o, state, context, options)
                      c = cc == this.comparison
                      {c, c_o}
                  end
                else
                  {sentinel, o}
                end
              end
            )
            {outcome, state}
        end
    end
  end

  #---------------------
  # identifier/3
  #---------------------
  def identifier(node, _state, _context), do: Noizu.RuleEngine.Script.Helper.identifier(node)

  #---------------------
  # identifier/4
  #---------------------
  def identifier(node, _state, _context, _options), do: Noizu.RuleEngine.Script.Helper.identifier(node)

  #---------------------
  # render/3
  #---------------------
  def render(node, state, context), do: Helper.render_arg_list("[CMP #{node.comparison}]", identifier(node), node.arguments || [], state, context, %{})

  #---------------------
  # render/4
  #---------------------
  def render(node, state, context, options), do: Helper.render_arg_list("[CMP #{node.comparison}]", identifier(node), node.arguments || [], state, context, options)
end