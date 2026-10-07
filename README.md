# Dlang Announce Telegram bot

https://t.me/dlang_announces

---
For developers:

After start it reads config file and then checks code.dlang.org for new packages and notifies its subscribers.

config.json:

```Json
{
	"telegram": {
		"secretBotToken": "123:JShghjsdZlI-asdsdjasddasdasdsasds",
		"proxy": "http://user:pass@host:port"
	}
}
```

Must be executed regularly by cron-like tool.

`paper_plane_bot --check_conn` only tests connectivity: it tries to fetch a
package description from code.dlang.org and to call Telegram `getMe`, prints
the result of each attempt and exits with code 1 if something failed.
