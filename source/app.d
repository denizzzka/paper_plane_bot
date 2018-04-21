import std.stdio;
import paper_plane_bot.grab;
import db;
import telega = telega.botapi;
import vibe.core.log;

private telega.BotApi telegram;

void main()
{
    import std.file;
    import std.datetime;
    import vibe.core.file: readFileUTF8;
    import vibe.data.json;

    //~ setLogLevel(LogLevel.trace);

    const config = readFileUTF8("config.json").parseJsonString;
    telegram = new telega.BotApi(config["telegram"]["secretBotToken"].get!string);

    const string filename = "last_updated_mtime.txt";

    openDb();

    SysTime lastModified = Clock.currTime;

    {
        try
            lastModified = filename.timeLastModified;
        catch(FileException)
            return; // file not found, will be created new one
        finally
            filename.write([]); // create or update timestamp file
    }

    auto pkgs_list = getPackagesSortedByUpdated;
    PackageDescr[] updatedPackages;

    import std.conv: to;

    foreach(const ref pkg; pkgs_list)
        if(pkg.updated >= lastModified.to!DateTime)
            updatedPackages ~= pkg;

    sendNotifies(updatedPackages);
}

void sendNotifies(PackageDescr[] updatedPackages)
{
    auto incoming = telegram.getUpdates;

    foreach(ref inc; incoming)
    {
        upsertChatId(inc.message.chat.id);
    }

    foreach_reverse(ref pkg; updatedPackages)
    {
        auto chats = getChatIds;

        foreach(chatId; chats)
        {
            import std.format;

            string msg = format(
                "A new dub package *%s %s* has been released: http://code.dlang.org/%s",
                pkg.name,
                pkg.ver,
                pkg.url
            );

            logTrace("[chatId:%d] %s", chatId, msg);

            try
                telegram.sendMessage(chatId, msg);
            catch(telega.TelegramBotApiException e)
            {
                if(e.code == 403) // blocked by user
                {
                    delChatId(chatId);
                    logInfo("chatId %d removed due to user block", chatId);
                    continue;
                }
                else
                    logError(e.msg);
            }
        }
    }
}
