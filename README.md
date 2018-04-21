# Dlang Announce Bot

To subscribe find Telegram contact @dlang_announce_bot and write something to it.

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
