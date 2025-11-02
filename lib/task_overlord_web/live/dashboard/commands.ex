defmodule TaskOverlordWeb.Dashboard.Commands do
  @moduledoc """
  Command registry for the terminal interface.
  Defines all available commands with metadata and handlers.
  """

  defmodule Command do
    @moduledoc """
    Represents a terminal command with metadata.
    """
    defstruct [
      :name,
      :aliases,
      :description,
      :keyboard_shortcut,
      :usage_example,
      :handler
    ]

    @type t :: %__MODULE__{
            name: String.t(),
            aliases: [String.t()],
            description: String.t(),
            keyboard_shortcut: String.t() | nil,
            usage_example: String.t(),
            handler: atom()
          }
  end

  @doc """
  Returns all available commands.
  """
  @spec all_commands() :: [Command.t()]
  def all_commands do
    [
      # Quick Actions (F-keys)
      %Command{
        name: "new_task",
        aliases: ["new", "create"],
        description: "Create a new task",
        keyboard_shortcut: "F1",
        usage_example: "new_task",
        handler: :new_task
      },
      %Command{
        name: "stop_all",
        aliases: ["stop", "kill_all"],
        description: "Stop all running tasks",
        keyboard_shortcut: "F2",
        usage_example: "stop_all",
        handler: :stop_all
      },
      %Command{
        name: "clear_done",
        aliases: ["clear", "clean"],
        description: "Remove all completed tasks and streams",
        keyboard_shortcut: "F3",
        usage_example: "clear_done",
        handler: :clear_done
      },
      %Command{
        name: "export",
        aliases: ["save", "download"],
        description: "Export task data",
        keyboard_shortcut: "F4",
        usage_example: "export",
        handler: :export
      },

      # Task/Stream Management
      %Command{
        name: "list_tasks",
        aliases: ["tasks", "lt"],
        description: "Show all tasks in live feed",
        keyboard_shortcut: nil,
        usage_example: "list_tasks",
        handler: :list_tasks
      },
      %Command{
        name: "list_streams",
        aliases: ["streams", "ls"],
        description: "Show all streams in live feed",
        keyboard_shortcut: nil,
        usage_example: "list_streams",
        handler: :list_streams
      },
      %Command{
        name: "list_all",
        aliases: ["all", "la"],
        description: "Show all tasks and streams",
        keyboard_shortcut: nil,
        usage_example: "list_all",
        handler: :list_all
      },
      %Command{
        name: "stats",
        aliases: ["statistics", "metrics"],
        description: "Show system statistics",
        keyboard_shortcut: nil,
        usage_example: "stats",
        handler: :stats
      },
      %Command{
        name: "refresh",
        aliases: ["reload", "r"],
        description: "Refresh the dashboard",
        keyboard_shortcut: nil,
        usage_example: "refresh",
        handler: :refresh
      },

      # Navigation
      %Command{
        name: "cards",
        aliases: ["view_cards", "kanban"],
        description: "Navigate to Cards view",
        keyboard_shortcut: nil,
        usage_example: "cards",
        handler: :navigate_cards
      },
      %Command{
        name: "timeline",
        aliases: ["view_timeline", "tl"],
        description: "Navigate to Timeline view",
        keyboard_shortcut: nil,
        usage_example: "timeline",
        handler: :navigate_timeline
      },
      %Command{
        name: "terminal",
        aliases: ["view_terminal", "term"],
        description: "Navigate to Terminal view",
        keyboard_shortcut: nil,
        usage_example: "terminal",
        handler: :navigate_terminal
      },

      # View Control
      %Command{
        name: "filter_running",
        aliases: ["running", "active"],
        description: "Show only running items",
        keyboard_shortcut: nil,
        usage_example: "filter_running",
        handler: :filter_running
      },
      %Command{
        name: "filter_done",
        aliases: ["done", "completed"],
        description: "Show only completed items",
        keyboard_shortcut: nil,
        usage_example: "filter_done",
        handler: :filter_done
      },
      %Command{
        name: "filter_errors",
        aliases: ["errors", "failed"],
        description: "Show only failed items",
        keyboard_shortcut: nil,
        usage_example: "filter_errors",
        handler: :filter_errors
      },
      %Command{
        name: "filter_all",
        aliases: ["show_all", "no_filter"],
        description: "Show all items (remove filters)",
        keyboard_shortcut: nil,
        usage_example: "filter_all",
        handler: :filter_all
      },

      # System/Help
      %Command{
        name: "help",
        aliases: ["?", "commands"],
        description: "Show all available commands",
        keyboard_shortcut: nil,
        usage_example: "help",
        handler: :show_help
      },
      %Command{
        name: "status",
        aliases: ["info", "system"],
        description: "Show system status",
        keyboard_shortcut: nil,
        usage_example: "status",
        handler: :show_status
      },
      %Command{
        name: "cls",
        aliases: ["clear_feed", "clear_screen"],
        description: "Clear the live feed",
        keyboard_shortcut: nil,
        usage_example: "cls",
        handler: :clear_feed
      },
      %Command{
        name: "prune_feed",
        aliases: ["prune", "trim_feed"],
        description: "Prune feed events to the configured limit",
        keyboard_shortcut: nil,
        usage_example: "prune_feed",
        handler: :prune_feed
      }
    ]
  end

  @doc """
  Returns a flat list of all command names and aliases.
  """
  @spec all_command_names() :: [String.t()]
  def all_command_names do
    all_commands()
    |> Enum.flat_map(fn cmd -> [cmd.name | cmd.aliases] end)
    |> Enum.uniq()
  end

  @doc """
  Finds a command by name or alias.
  """
  @spec find_command(String.t()) :: Command.t() | nil
  def find_command(name) when is_binary(name) do
    name_lower = String.downcase(name)

    all_commands()
    |> Enum.find(fn cmd ->
      cmd.name == name_lower or Enum.member?(cmd.aliases, name_lower)
    end)
  end

  @doc """
  Returns commands grouped by category for display.
  """
  @spec commands_by_category() :: [{String.t(), [Command.t()]}]
  def commands_by_category do
    commands = all_commands()

    [
      {"Quick Actions", Enum.slice(commands, 0..3)},
      {"Task/Stream Management", Enum.slice(commands, 4..8)},
      {"Navigation", Enum.slice(commands, 9..11)},
      {"View Control", Enum.slice(commands, 12..15)},
      {"System/Help", Enum.slice(commands, 16..19)}
    ]
  end
end
