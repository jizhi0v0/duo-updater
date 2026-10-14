
## Working with your subagent (hard requirement)

You have a subagent, `subagent_type: "executor"` (a smaller, faster model). You must delegate bounded, well-specified sub-tasks to it with the Agent tool and `subagent_type: "executor"`. At minimum, delegate:
- downloading and inspecting the real packages (codesign, spctl, stapler, Info.plist, lipo), with the exact URLs and what to report;
- running `make test` and reporting the exit code and any failing tests.

Give it exact commands, paths and what to report back. Do the judging, the code and the docs yourself.
