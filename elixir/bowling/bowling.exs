defmodule Bowling do
  use GenServer

  @doc """
    Creates a new game of bowling that can be used to store the results of
    the game
  """

  @spec start() :: any
  def start do
    {:ok, pid} = GenServer.start_link(__MODULE__, :ok)
    pid
  end

  @doc """
    Records the number of pins knocked down on a single roll. Returns `any`
    unless there is something wrong with the given number of pins, in which
    case it returns a helpful message.
  """

  @spec roll(any, integer) :: any | String.t()
  def roll(_, roll) when roll < 0, do: {:error, "Negative roll is invalid"}
  def roll(_, roll) when roll > 10, do: {:error, "Pin count exceeds pins on the lane"}

  def roll(game, roll) do
    case GenServer.call(game, {:roll, roll}) do
      {:error, _} = err -> err
      _ -> game
    end
  end

  @doc """
    Returns the score of a given game of bowling if the game is complete.
    If the game isn't complete, it returns a helpful message.
  """

  @spec score(any) :: integer | String.t()
  def score(game) do
    GenServer.call(game, :score)
  end

  # Server (callbacks)
  @impl true
  def init(:ok) do
    {:ok, []}
  end

  @impl true
  def handle_call(:score, _from, results) when length(results) < 10 do
    {:reply, {:error, "Score cannot be taken until the end of the game"}, nil}
  end

  @impl true
  def handle_call(:score, _from, [{kind, _, _}, {kind_previous, _, _} | _] = results)
      when kind != :done and not (kind == :strike_pending and length(results) == 12) and
      not (kind_previous == :spare and kind == :strike_pending) and not (kind_previous == :strike and kind == :spare ) do
    {:reply, {:error, "Score cannot be taken until the end of the game"}, nil}
  end

  @impl true
  def handle_call(:score, _from, results) do
    score =
      results
      |> Enum.reverse()
      |> Enum.reject(fn
        {:pending, _, _} -> true
        _ -> false
      end)
      |> Enum.take(10)
      |> Enum.map(fn {_, _, score_frame} -> score_frame end)
      |> Enum.sum()

    {:reply, score, results}
  end

  @impl true
  def handle_call({:roll, roll}, _from, results) do
    case bowling_calculator(roll, results) do
      {:error, _} = err ->
        {:reply, err, nil}

      {score_frame, new_result} ->
        score_board = remove_pending(results)
        {:reply, score_frame, [new_result | update_frame_calculator(new_result, score_board)]}
    end
  end

  def bowling_calculator(roll, [{:done, _, _} | _] = results) when length(results) >= 10 do
    {:error, "Cannot roll after game is over"}
  end

  def bowling_calculator(_, [{:pending, _, _}, {kind, _, _} | _] = res)
      when kind != :strike and kind != :strike_pending and length(res) > 10 do
    {:error, "Pin count exceeds pins on the lane"}
  end

  def bowling_calculator(roll, [{:pending, [last_roll], _} | _]) when roll + last_roll > 10 do
    {:error, "Pin count exceeds pins on the lane"}
  end

  # strike on first roll
  def bowling_calculator(10, []) do
    {10, {:strike, [10], 10}}
  end

  # first roll
  def bowling_calculator(roll, []) do
    score_frame = roll
    {score_frame, {:pending, [roll], score_frame}}
  end

  # strike in bonus
  def bowling_calculator(10, res) when length(res) >= 10 do
    {10, {:strike_pending, [10], 10}}
  end

  # strike
  def bowling_calculator(10, _) do
    {10, {:strike, [10], 10}}
  end

  # spare
  def bowling_calculator(roll, [{:pending, [last_roll], score_frame} | _])
      when roll + last_roll == 10 do
    new_score_frame = score_frame + roll
    last_frame = {:spare, [last_roll, roll], new_score_frame}
    {new_score_frame, last_frame}
  end

  # basic roll
  def bowling_calculator(roll, [{:pending, [last_roll], score_frame} | _]) do
    new_score_frame = score_frame + roll
    last_frame = {:done, [last_roll, roll], new_score_frame}
    {new_score_frame, last_frame}
  end

  # last roll
  def bowling_calculator(roll, [{:strike, _, _} | _] = res)
      when length(res) >= 10 do
    {roll, {:pending, [roll], roll}}
  end

  def bowling_calculator(roll, res) when length(res) >= 10 do
    {roll, {:done, [roll], roll}}
  end

  def bowling_calculator(roll, _) do
    new_frame = {:pending, [roll], roll}
    {roll, new_frame}
  end

  def update_frame_calculator({:pending, _, _}, results) when length(results) <= 10 do
    results
  end

  def update_frame_calculator({kind, rolls, score_frame}, [
        {kind_previous, [10], previous_score_frame} | results
      ])
      when kind_previous == :strike or kind_previous == :strike_pending do
    [
      {kind_previous, [10], min(previous_score_frame + (rolls |> Enum.sum()), 30)}
      | update_frame_calculator({kind, rolls |> Enum.take(1), score_frame}, results)
    ]
  end

  def update_frame_calculator({_, rolls, _} = last_update, [
        {:spare, spare_rolls, score_frame} | results
      ]) do
    [
      {:spare, spare_rolls, score_frame + (rolls |> Enum.at(0))}
      | results
    ]
  end

  def update_frame_calculator(_, results) do
    results
  end

  def remove_pending([{:pending, _, _} | results]) do
    results
  end

  def remove_pending(res) do
    res
  end
end
