import std.stdio;
import paper_plane_bot.grab;
import db;
import tg = telega.botapi;
import vibe.core.log;
import vibe.data.json;

private tg.BotApi telegram;

void main()
{
    import vibe.core.file: readFileUTF8;
    import telega.drivers.requests: RequestsHttpClient;

    //~ setLogLevel(LogLevel.trace);

    const configFile = readFileUTF8("config.json").parseJsonString;
    const tgconf = configFile["telegram"];

    auto httpClient = new RequestsHttpClient();

    if("SOCKS5_proxy" in tgconf)
    {
        const socks5conf = tgconf["SOCKS5_proxy"];

        httpClient.setProxy(socks5conf["server"].get!string, socks5conf["port"].get!ushort);
    }

    telegram = new tg.BotApi(tgconf["secretBotToken"].get!string, tg.BaseApiUrl, httpClient);

    openDb();

    logInfo("Begin download packages list");
    auto pkgs_list = getPackagesSortedByUpdated;
    logInfo("Downloaded %d packages descriptions. Begin comparison for new versions.", pkgs_list.length);
    PackageDescr[] updatedPackages = upsertPackages(pkgs_list);
    logInfo("Number of new or updated descriptions: %d", updatedPackages.length);

    import std.conv: to;

    foreach(pkg; updatedPackages)
        logInfo(pkg.to!string);

    sendNotifies(updatedPackages);
}

void sendNotifies(PackageDescr[] updatedPackages)
{
    import telega.telegram.basic: getUpdates, sendMessage, SendMessageMethod, ParseMode;

    int nextMsgId;

    auto incoming = telegram.getUpdates(nextMsgId, 30);

    foreach(ref inc; incoming)
    {
        string descr = serializeToJsonString(inc.message);

        upsertChatId(inc.message.get.chat.id, descr);
        logTrace("Upsert chat id %d, descr: %s", inc.message.get.chat.id, descr);

        nextMsgId = inc.update_id + 1;
    }

    foreach_reverse(ref pkg; updatedPackages)
    {
        auto chats = getChatIds;

        foreach(chatId; chats)
        {
            import std.format;

            SendMessageMethod msg;
            msg.chat_id = chatId;
            msg.parse_mode = ParseMode.Markdown;
            msg.text = format(
                "A new version of dub package [%s](http://code.dlang.org/%s) *%s* has been released",
                pkg.name,
                pkg.url,
                pkg.ver,
            );

            logTrace("[chatId:%d] %s", chatId, msg.text);

            try
                telegram.sendMessage(msg);
            catch(tg.TelegramBotApiException e)
            {
                if(e.code == 403) // blocked by user
                {
                    delChatId(chatId);
                    logInfo("chat id %d removed due to user block", chatId);
                    continue;
                }
                else
                    logError(`Telegram: `~msg.text);
            }
        }
    }
}
