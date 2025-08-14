defmodule Blockchain.Utils.Functional do
  @moduledoc """
  Functional programming utilities to promote idiomatic Elixir code.
  Provides common patterns and helpers for functional transformations.
  """

  @doc """
  Applies a function to a value and returns the result wrapped in {:ok, result}.
  Returns {:error, reason} if the function raises an exception.
  
  ## Examples
      
      iex> safe_apply(fn x -> x * 2 end, 5)
      {:ok, 10}
      
      iex> safe_apply(fn _ -> raise "error" end, 5)
      {:error, %RuntimeError{message: "error"}}
  """
  @spec safe_apply((any() -> any()), any()) :: {:ok, any()} | {:error, Exception.t()}
  def safe_apply(fun, value) do
    {:ok, fun.(value)}
  rescue
    exception -> {:error, exception}
  end

  @doc """
  Chains multiple operations using the pipe operator, stopping on first error.
  Similar to `with` but using a pipeline approach.
  
  ## Examples
      
      iex> pipe_while_ok(5, [
      ...>   fn x -> {:ok, x * 2} end,
      ...>   fn x -> {:ok, x + 1} end,
      ...>   fn x -> {:ok, x * 3} end
      ...> ])
      {:ok, 33}
      
      iex> pipe_while_ok(5, [
      ...>   fn x -> {:ok, x * 2} end,
      ...>   fn _ -> {:error, :failed} end,
      ...>   fn x -> {:ok, x * 3} end
      ...> ])
      {:error, :failed}
  """
  @spec pipe_while_ok(any(), [(any() -> {:ok, any()} | {:error, any()})]) :: 
        {:ok, any()} | {:error, any()}
  def pipe_while_ok(initial_value, functions) do
    Enum.reduce_while(functions, {:ok, initial_value}, fn fun, {:ok, value} ->
      case fun.(value) do
        {:ok, result} -> {:cont, {:ok, result}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  @doc """
  Maps over a list and collects results, returning {:ok, results} if all succeed,
  or {:error, first_error} if any fail.
  
  ## Examples
      
      iex> map_all_ok([1, 2, 3], fn x -> {:ok, x * 2} end)
      {:ok, [2, 4, 6]}
      
      iex> map_all_ok([1, 2, 3], fn
      ...>   2 -> {:error, :two_not_allowed}
      ...>   x -> {:ok, x * 2}
      ...> end)
      {:error, :two_not_allowed}
  """
  @spec map_all_ok(list(), (any() -> {:ok, any()} | {:error, any()})) :: 
        {:ok, list()} | {:error, any()}
  def map_all_ok(list, fun) do
    list
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, result} -> {:cont, {:ok, [result | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      error -> error
    end
  end

  @doc """
  Converts nested function calls into a pipeline.
  Useful for refactoring imperative-style code.
  
  ## Examples
      
      iex> pipeline(5, [
      ...>   {:*, 2},
      ...>   {:+, 3},
      ...>   {:|>, [&Integer.to_string/1]}
      ...> ])
      "13"
  """
  @spec pipeline(any(), list()) :: any()
  def pipeline(initial_value, operations) do
    Enum.reduce(operations, initial_value, fn
      {:|>, [fun]}, acc -> fun.(acc)
      {fun, args}, acc when is_atom(fun) -> apply(Kernel, fun, [acc | args])
      fun, acc when is_function(fun) -> fun.(acc)
    end)
  end

  @doc """
  Pattern matches on multiple conditions using guards in a functional way.
  Replaces nested if/else with pattern matching.
  
  ## Examples
      
      iex> cond_pattern(10, [
      ...>   {fn x -> x < 5 end, :small},
      ...>   {fn x -> x < 15 end, :medium},
      ...>   {fn _ -> true end, :large}
      ...> ])
      :medium
  """
  @spec cond_pattern(any(), [{(any() -> boolean()), any()}]) :: any()
  def cond_pattern(value, patterns) do
    patterns
    |> Enum.find(fn {guard_fun, _} -> guard_fun.(value) end)
    |> elem(1)
  end

  @doc """
  Composes multiple functions into a single function.
  Functions are applied from right to left (mathematical composition).
  
  ## Examples
      
      iex> add_one = fn x -> x + 1 end
      iex> double = fn x -> x * 2 end
      iex> composed = compose([add_one, double])
      iex> composed.(5)
      11
  """
  @spec compose([function()]) :: function()
  def compose(functions) do
    fn initial ->
      functions
      |> Enum.reverse()
      |> Enum.reduce(initial, fn fun, acc -> fun.(acc) end)
    end
  end

  @doc """
  Memoizes a function to cache its results.
  Useful for expensive computations that are called repeatedly.
  
  ## Examples
      
      iex> expensive = memoize(fn x -> 
      ...>   Process.sleep(100)
      ...>   x * 2
      ...> end)
      iex> expensive.(5) # Takes 100ms
      10
      iex> expensive.(5) # Returns immediately
      10
  """
  @spec memoize(function()) :: function()
  def memoize(fun) do
    {:ok, cache} = Agent.start_link(fn -> %{} end)
    
    fn args ->
      Agent.get_and_update(cache, fn cache_map ->
        case Map.get(cache_map, args) do
          nil ->
            result = fun.(args)
            {result, Map.put(cache_map, args, result)}
          
          cached_result ->
            {cached_result, cache_map}
        end
      end)
    end
  end
end