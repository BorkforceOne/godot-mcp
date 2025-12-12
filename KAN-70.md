# KAN-70: Implement get_runtime_errors tool for runtime error capture

**Status:** In Progress  
**Priority:** High  
**Epic:** KAN-68 - Godot MCP Enhanced Debugging & Validation Tools  
**Repository:** https://github.com/Coding-Solo/godot-mcp

---

## Summary

Implement MCP tool `get_runtime_errors` that captures runtime errors, warnings, and `push_error()`/`push_warning()` calls from the running game.

## Why This Matters

Runtime errors occur but Claude has no visibility. User must manually relay console output. This closes the feedback loop.

---

## Inputs

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `since_timestamp` | float | optional | Only errors after this Unix timestamp |
| `severity` | string | optional | Filter by `"all"` / `"error"` / `"warning"` |
| `clear_after_read` | bool | optional | Clear buffer after reading |

## Output

```json
{
  "errors": [
    {
      "timestamp": float,
      "type": string,
      "message": string,
      "script": string,
      "line": int
    }
  ],
  "error_count": int,
  "warning_count": int
}
```

---

## Technical Notes

- Need error buffer system (FIFO, max ~100 entries)
- Options: custom logger autoload, log file monitoring, or override push_error
- Must handle both editor and game runtime contexts

---

## Files to Touch (Coding-Solo/godot-mcp)

| Action | File | Notes |
|--------|------|-------|
| MODIFY | `scripts/godot_operations.gd` | Add error capture operation |
| CREATE | `src/tools/runtime-errors.ts` | Or add to existing tool file |
| MODIFY | `src/index.ts` | Register new tool |

> **Note:** The new MCP server uses a bundled GDScript approach where all operations go through a single `godot_operations.gd` file rather than separate addon files.

---

## Acceptance Criteria

- [ ] Captures `push_error()` with script/line info
- [ ] Captures `push_warning()`
- [ ] Captures null reference errors
- [ ] Timestamp filtering works
- [ ] Buffer doesn't grow unbounded

---

## Links

- **Jira Ticket:** https://tidalstudios.atlassian.net/browse/KAN-70
- **MCP Server Repo:** https://github.com/Coding-Solo/godot-mcp
