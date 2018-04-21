import std.stdio;
import paper_plane_bot.grab;
import db;
import telega = telega.botapi;

private telega.BotApi telegram;

void main()
{
    import std.file;
    import std.datetime;
    import vibe.core.file: readFileUTF8;
    import vibe.data.json;
    import vibe.core.log;

    setLogLevel(LogLevel.trace);

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

    auto chats = getChatIds;

    foreach(ref pkg; updatedPackages)
    {
        foreach(chatId; chats)
        {
            import std.stdio;
            writefln("Send msg about package %s to chatId %d", pkg.name, chatId);

            telegram.sendMessage(chatId, pkg.name~" was updated");
        }
    }
}
