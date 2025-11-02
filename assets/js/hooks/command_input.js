/**
 * CommandInput Hook
 *
 * Handles keyboard interactions for the command input field:
 * - Tab: Cycle through autocomplete suggestions
 * - Up/Down: Navigate command history
 * - Escape: Clear input
 * - Enter: Execute command
 */
export default {
  mounted() {
    this.handleEvent("update_input_value", ({ value }) => {
      this.el.value = value;
    });

    this.handleEvent("focus_input", () => {
      this.el.focus();
    });

    this.el.addEventListener("keydown", (e) => {
      // Tab key - cycle through suggestions
      if (e.key === "Tab") {
        e.preventDefault();
        this.pushEvent("command_tab", {});
        return;
      }

      // Up arrow - previous command in history
      if (e.key === "ArrowUp") {
        e.preventDefault();
        this.pushEvent("command_arrow_up", {});
        return;
      }

      // Down arrow - next command in history
      if (e.key === "ArrowDown") {
        e.preventDefault();
        this.pushEvent("command_arrow_down", {});
        return;
      }

      // Escape - clear input
      if (e.key === "Escape") {
        e.preventDefault();
        this.el.value = "";
        this.pushEvent("command_input_change", { value: "" });
        return;
      }

      // Enter - execute command (already handled by phx-keydown in template)
      // F1-F4 keys - quick actions (let them bubble up for now)
    });
  }
};
