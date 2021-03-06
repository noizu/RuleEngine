#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.RuleEngine.State.AgentStateManager do
  @type t :: %__MODULE__{
                agent: nil, # process
             }

  defstruct [
    agent: nil,
  ]

  def new(inner) do
    {:ok, p} = Agent.start_link fn -> inner end
    %__MODULE__{agent: p}
  end
end

defimpl Noizu.RuleEngine.StateProtocol, for: Noizu.RuleEngine.State.AgentStateManager do
  #-------------------------
  #
  #-------------------------
  def settings(entry, context), do: Agent.get(entry.agent, &(Noizu.RuleEngine.StateProtocol.settings(&1, context)))

  #-------------------------
  #
  #-------------------------
  def setting(entry, setting, context), do: Agent.get(entry.agent, &(Noizu.RuleEngine.StateProtocol.setting(&1, setting, context)))

  #-------------------------
  #
  #-------------------------
  def put!(entry, field, value, context) do
    Agent.update(entry.agent, &(Noizu.RuleEngine.StateProtocol.put!(&1, field, value, context)))
    entry
  end

  #-------------------------
  #
  #-------------------------
  def put!(entry, entity, field, value, context) do
    Agent.update(entry.agent, &(Noizu.RuleEngine.StateProtocol.put!(&1, entity, field, value, context)))
    entry
  end

  #-------------------------
  #
  #-------------------------
  def get!(entry, field, context) do
    {Agent.get(entry.agent, &(Noizu.RuleEngine.StateProtocol.get!(&1, field, context) |> elem(0) )), entry}
  end

  #-------------------------
  #
  #-------------------------
  def get!(entry, entity, field, context) do
    {Agent.get(entry.agent, &(Noizu.RuleEngine.StateProtocol.get!(&1, entity, field, context) |> elem(0) )), entry}
  end
end