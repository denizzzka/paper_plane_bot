# Dlang Announce Telegram bot

https://t.me/dlang_announces

---
For developers:

After start it reads config file and then checks code.dlang.org for new packages and notifies its subscribers.

config.json:

```Json
{
	"proxy": "http://user:pass@host:port",
	"telegram": {
		"secretBotToken": "123:JShghjsdZlI-asdsdjasddasdasdsasds"
	}
}
```

`proxy` is optional. It is used both for Telegram messages and for fetching
the code.dlang.org feed. Supported URL schemes: `http`, `https`, `socks5`.

Sending to Telegram is done with a bounded timeout and retries: network
failures are retried with a growing pause, and Telegram rate limit answers
(429) are handled by waiting the requested `retry_after`. The `telegram`
section may carry optional tuning keys, all of them with defaults:
`sendRetries` (3), `retryPauseMs` (2000), `sendIntervalMs` (50) - pause
between messages, `floodWaits` (3).

A package version is written to the DB only after Telegram accepted its
notification: a package whose send failed stays unchanged and is retried
on the next run, an accepted one is never repeated. With `--ff` the
versions are written without sending, as the option promises.

Must be executed regularly by cron-like tool.

`paper_plane_bot --check_conn` only tests connectivity: it tries to fetch a
package description from code.dlang.org and to call Telegram `getMe`, prints
the result of each attempt and exits with code 1 if something failed.

Building:

Forks with proxy support are taken from the directories next to this one:
`../vibe-core`, `../vibe-http`, `../telega`. Also `dub.selections.json` pins
`vibe-d` 0.10.3, which formally contradicts the telega recipe - do not run
`dub upgrade` without fixing the telega dependency bound first.
