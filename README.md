# Dlang Announce Telegram bot

https://t.me/dlang_announces

---
For developers:

After start it reads config file and then checks code.dlang.org for new packages and notifies its subscribers.

config.json:

```Json
{
	"telegram": {
		"secretBotToken": "123:JShghjsdZlI-asdsdjasddasdasdsasds"
	}
}
```

Must be executed regularly by cron-like tool.
