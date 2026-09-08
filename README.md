# claude-code-setup

My [Claude Code](https://code.claude.com) setup. Starts with the statusline; skills and `CLAUDE.md` will follow.

## Statusline

![statusline](statusline/screenshot.png)

Two lines, always visible under the prompt:

```
ctx [██░░░░] 37% | Fable 5.1 | claudesidian (main)
usg [████░░] 62% (1h30m) | 223.0k tokens ~$1.23
```

- **ctx**: how full the context window is. Watch this instead of running `/context`.
- **model**: the current model. On Fable it gets a pink plate so I can't miss that I'm on the most expensive one.
- **folder (branch)**: where this session is working. Useful with several sessions and worktrees open.
- **usg**: 5-hour usage limit, colored green to red, with time until it resets.
- **tokens ~cost**: total tokens this session and the estimated cost.

### Install

1. Copy [`statusline/statusline.sh`](statusline/statusline.sh) to `~/.claude/statusline.sh` and make it executable:

   ```bash
   curl -o ~/.claude/statusline.sh https://raw.githubusercontent.com/seandkim/claude-code-setup/main/statusline/statusline.sh
   chmod +x ~/.claude/statusline.sh
   ```

2. Point Claude Code at it in `~/.claude/settings.json`:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "~/.claude/statusline.sh"
     }
   }
   ```

3. Restart Claude Code. Or run `/statusline` and tell it to use the script.

Requires `jq` and `bc` (`brew install jq` on macOS; `bc` ships with it). The Fable highlight needs a terminal with truecolor support (Ghostty, cmux, iTerm2, Kitty, WezTerm all qualify).

### Tweak

Everything is plain bash. The parts you'll most likely change:

- `bar_length` in `make_bar` for wider or narrower bars
- `BG_MODEL` / `FG_MODEL` for the highlighted model's colors, and the `[Ff]able` match for which model gets it
- the `parts` array at the bottom for what goes on line 1 and in what order

The JSON Claude Code pipes to the script is documented in the [statusline docs](https://code.claude.com/docs/en/statusline).

## License

MIT
