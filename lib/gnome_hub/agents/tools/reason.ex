defmodule GnomeHub.Agents.Tools.Reason do
  @moduledoc """
  Use structured reasoning to solve a problem.

  Employs chain-of-thought reasoning to break down complex problems
  and arrive at well-reasoned conclusions.
  """

  use Jido.Action,
    name: "reason",
    description: "Use structured reasoning to think through a problem step by step. Good for complex decisions, debugging, or planning.",
    schema: [
      problem: [type: :string, required: true, doc: "The problem or question to reason about"],
      context: [type: :string, doc: "Additional context relevant to the problem"],
      # Accept string since LLMs pass strings, coerce to atom in run/2
      strategy: [type: :string, default: "chain_of_thought", doc: "Reasoning strategy: chain_of_thought, pros_cons, or systematic"]
    ]

  @impl true
  def run(params, _context) do
    problem = Map.get(params, :problem) || Map.get(params, "problem")
    context_str = Map.get(params, :context) || Map.get(params, "context", "")
    strategy = Map.get(params, :strategy) || Map.get(params, "strategy", "chain_of_thought")
    strategy = normalize_strategy(strategy)

    prompt = build_prompt(problem, context_str, strategy)

    # Return the reasoning prompt for the agent to process
    # The actual reasoning is done by the LLM in the next turn
    {:ok, %{
      reasoning_prompt: prompt,
      strategy: strategy,
      note: "Process this reasoning prompt to arrive at a conclusion."
    }}
  end

  defp build_prompt(problem, context, :chain_of_thought) do
    """
    Problem: #{problem}

    #{if context != "", do: "Context: #{context}\n\n", else: ""}Think through this step by step:
    1. What do we know?
    2. What are the constraints?
    3. What are possible approaches?
    4. What is the best approach and why?
    5. What is the conclusion?
    """
  end

  defp build_prompt(problem, context, :pros_cons) do
    """
    Problem: #{problem}

    #{if context != "", do: "Context: #{context}\n\n", else: ""}Analyze this with pros and cons:
    1. List the options
    2. For each option, list pros
    3. For each option, list cons
    4. Weigh the trade-offs
    5. Make a recommendation
    """
  end

  defp build_prompt(problem, context, :systematic) do
    """
    Problem: #{problem}

    #{if context != "", do: "Context: #{context}\n\n", else: ""}Apply systematic analysis:
    1. Define the problem precisely
    2. Gather relevant facts
    3. Identify assumptions
    4. Consider alternatives
    5. Evaluate each alternative
    6. Select the best solution
    7. Plan implementation
    """
  end

  # Normalize strategy from various string formats to atom
  defp normalize_strategy(strategy) when is_atom(strategy), do: strategy
  defp normalize_strategy(":" <> rest), do: normalize_strategy(rest)
  defp normalize_strategy("chain_of_thought"), do: :chain_of_thought
  defp normalize_strategy("pros_cons"), do: :pros_cons
  defp normalize_strategy("systematic"), do: :systematic
  defp normalize_strategy(_), do: :chain_of_thought
end
