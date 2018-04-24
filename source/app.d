import std.stdio;
import paper_plane_bot.grab;
import db;
import telega = telega.botapi;
import vibe.core.log;

private telega.BotApi telegram;

void main()
{
    import vibe.core.file: readFileUTF8;
    import vibe.data.json;

    //~ setLogLevel(LogLevel.trace);

    const config = readFileUTF8("config.json").parseJsonString;
    telegram = new telega.BotApi(config["telegram"]["secretBotToken"].get!string);

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
    auto incoming = telegram.getUpdates(100, 1);

    foreach(ref inc; incoming)
    {
        import vibe.data.json;

        string descr = serializeToJsonString(inc.message);

        upsertChatId(inc.message.chat.id, descr);
        logInfo("Upsert chat id %d, descr: %s", inc.message.chat.id, descr);

        telegram.updateProcessed(inc);
    }

    foreach_reverse(ref pkg; updatedPackages)
    {
        auto chats = getChatIds;

        foreach(chatId; chats)
        {
            import std.format;

            string msg = format(
                "A new version of dub package [%s](http://code.dlang.org/%s) *%s* has been released",
                pkg.name,
                pkg.url,
                pkg.ver,
            );

            logTrace("[chatId:%d] %s", chatId, msg);

            try
                telegram.sendMessage(chatId, msg);
            catch(telega.TelegramBotApiException e)
            {
                if(e.code == 403) // blocked by user
                {
                    delChatId(chatId);
                    logInfo("chat id %d removed due to user block", chatId);
                    continue;
                }
                else
                    logError(`Telegram: `~e.msg);
            }
        }
    }
}
