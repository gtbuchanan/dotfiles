@echo off
rem Windows half of the postinstall named by the hass-cli pin in mise's
rem home-assistant.toml fragment. That fragment is plain TOML and ships to every
rem personal host, so the command it names has to resolve everywhere -- which is
rem the only reason this file exists.
rem
rem There is nothing to do here yet. Its POSIX counterpart works around
rem hass-cli 1.0.0 calling asyncio.get_event_loop() on a Python 3.14
rem interpreter, which Termux is pinned to and Windows is not: uv picks the
rem interpreter here, and it has not landed on one that removes the implicit
rem event loop.
rem
rem So this exits clean rather than being absent -- a missing command would fail
rem `mise install` on Windows for a bug Windows does not have. If uv does move
rem to 3.14+ here, the same subcommands will start failing and the fix belongs
rem in this file. See hass-cli-postinstall and docs/home-assistant.md.
exit /b 0
