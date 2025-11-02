defmodule TaskOverlordWeb.Dashboard.CommandSearch do
  @moduledoc """
  Fuzzy search for commands using Levenshtein distance.
  Implements a 4-tier search strategy:
  1. Exact match
  2. 1-2 Levenshtein distance
  3. 3-4 Levenshtein distance
  4. 5-6 Levenshtein distance

  Stops at the first tier that returns results.
  """

  alias TaskOverlordWeb.Dashboard.Commands

  @doc """
  Search for commands matching the input query.
  Returns a list of command names ordered by relevance.

  Returns empty list if:
  - Query is empty
  - Query starts with backslash (special command prefix)
  """
  @spec search(String.t()) :: [String.t()]
  def search(query) when is_binary(query) do
    query = String.trim(query)

    cond do
      # Empty query - no suggestions
      query == "" ->
        []

      # Backslash prefix - special handling, no autocomplete
      String.starts_with?(query, "\\") ->
        []

      # Normal search
      true ->
        perform_fuzzy_search(String.downcase(query))
    end
  end

  defp perform_fuzzy_search(query) do
    all_names = Commands.all_command_names()

    # Tier 1: Exact match
    case exact_match(query, all_names) do
      [] ->
        # Tier 2: 1-2 distance
        case distance_match(query, all_names, 1, 2) do
          [] ->
            # Tier 3: 3-4 distance
            case distance_match(query, all_names, 3, 4) do
              [] ->
                # Tier 4: 5-6 distance
                distance_match(query, all_names, 5, 6)

              results ->
                results
            end

          results ->
            results
        end

      results ->
        results
    end
  end

  # Exact match search
  defp exact_match(query, all_names) do
    all_names
    |> Enum.filter(fn name ->
      String.starts_with?(name, query) or name == query
    end)
    |> Enum.sort_by(&String.length/1)
  end

  # Levenshtein distance-based matching
  defp distance_match(query, all_names, min_distance, max_distance) do
    all_names
    |> Enum.map(fn name ->
      distance = String.jaro_distance(query, name)
      {name, distance}
    end)
    # Convert Jaro distance to approximate Levenshtein for threshold
    # Jaro distance of 1.0 = perfect match, lower values = more different
    # We'll use a threshold-based approach instead
    |> Enum.filter(fn {name, _distance} ->
      lev_distance = levenshtein_distance(query, name)
      lev_distance >= min_distance and lev_distance <= max_distance
    end)
    |> Enum.sort_by(fn {_name, distance} -> distance end, :desc)
    |> Enum.map(fn {name, _distance} -> name end)
  end

  # Calculate Levenshtein distance between two strings
  defp levenshtein_distance(source, target) do
    source_length = String.length(source)
    target_length = String.length(target)

    # Create a matrix
    matrix =
      for i <- 0..source_length do
        for j <- 0..target_length do
          cond do
            i == 0 -> j
            j == 0 -> i
            true -> 0
          end
        end
      end

    # Calculate distances
    calculate_distance(source, target, source_length, target_length, matrix)
  end

  defp calculate_distance(source, target, source_length, target_length, matrix) do
    source_chars = String.graphemes(source)
    target_chars = String.graphemes(target)

    matrix =
      Enum.reduce(1..source_length, matrix, fn i, acc_matrix ->
        Enum.reduce(1..target_length, acc_matrix, fn j, inner_matrix ->
          cost = if Enum.at(source_chars, i - 1) == Enum.at(target_chars, j - 1), do: 0, else: 1

          deletion = get_cell(inner_matrix, i - 1, j) + 1
          insertion = get_cell(inner_matrix, i, j - 1) + 1
          substitution = get_cell(inner_matrix, i - 1, j - 1) + cost

          min_cost = Enum.min([deletion, insertion, substitution])
          set_cell(inner_matrix, i, j, min_cost)
        end)
      end)

    get_cell(matrix, source_length, target_length)
  end

  defp get_cell(matrix, i, j) do
    matrix |> Enum.at(i) |> Enum.at(j)
  end

  defp set_cell(matrix, i, j, value) do
    List.update_at(matrix, i, fn row ->
      List.replace_at(row, j, value)
    end)
  end

  @doc """
  Check if a command input is the special help command.
  """
  @spec is_help_command?(String.t()) :: boolean()
  def is_help_command?(query) when is_binary(query) do
    trimmed = String.trim(query)
    trimmed == "\\?" or trimmed == "help" or trimmed == "?"
  end
end
