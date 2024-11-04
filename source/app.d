import std.getopt;
import std.stdio;
import paper_plane_bot.grab;
import db;
import tg = telega.botapi;
import vibe.core.log;
import vibe.data.json;

private tg.BotApi telegram;

void main(string[] args)
{
    import vibe.core.file: readFileUTF8;
    import telega.drivers.requests: RequestsHttpClient;

    bool fastForward;

    auto helpInformation = getopt(
            args,
            "ff", `Only update DB but do not send anything to Telegram ("fast forward")`, &fastForward,
        );

    if(helpInformation.helpWanted)
    {
        defaultGetoptPrinter("Some information about the program.", helpInformation.options);

        return;
    }

    setLogLevel(LogLevel.diagnostic);

    const configFile = readFileUTF8("config.json").parseJsonString;
    const tgconf = configFile["telegram"];

    auto httpClient = new RequestsHttpClient();

    if("SOCKS5_proxy" in tgconf)
    {
        const socks5conf = tgconf["SOCKS5_proxy"];

        httpClient.setProxy(socks5conf["server"].get!string, socks5conf["port"].get!ushort);
    }

    telegram = new tg.BotApi(tgconf["secretBotToken"].get!string, tg.BaseApiUrl, httpClient);
    const chatId = tgconf["chatId"].get!long;

    logInfo("Check Telegram for incoming private messages");
    processIncomingMessages();

    openDb();

    logInfo("Begin download packages list");
    auto pkgs_list = getPackagesSortedByUpdated;
    logInfo("Downloaded %d packages descriptions. Begin comparison for new versions.", pkgs_list.length);
    PackageDescr[] updatedPackages = upsertPackages(pkgs_list);
    logInfo("Number of new or updated descriptions: %d", updatedPackages.length);

    import std.conv: to;

    foreach(pkg; updatedPackages)
        logInfo(pkg.to!string);

    if(fastForward)
        logDiagnostic(`"Fast forward" enabled: Do not send updates to TG`);
    else
    {
        logInfo("Send updates into chat");
        foreach_reverse(ref pkg; updatedPackages)
            sendPackageUpdatedNotify(chatId, pkg);
    }
}

void processIncomingMessages()
{
    import telega.telegram.basic: getUpdates;

    int nextMsgId;

    foreach(att; 0..3)
    {
        auto incoming = telegram.getUpdates(nextMsgId, 30, 0);

        if(att > 0 && incoming.length == 0)
            break;

        foreach(ref inc; incoming)
        {
            string descr = serializeToJsonString(inc.message);

            logTrace("Incoming message: %s", descr);

            if(!inc.message.isNull)
                sendNotify(inc.message.get.chat.id, `Sorry, this bot isn't longer functional. Please go to [new channel](https://t.me/dlang_announces)`);

            nextMsgId = inc.update_id + 1;
        }
    }
}

void sendPackageUpdatedNotify(in long chatId, in PackageDescr pkg)
{
    import std.format;

    const text = format(
        "A new version of dub package [%s](https://code.dlang.org/%s) *%s* has been released",
        pkg.name,
        pkg.url,
        pkg.ver,
    );

    sendNotify(chatId, text);
}

void sendNotify(in long chatId, in string markDownText)
{
    import telega.telegram.basic: sendMessage, SendMessageMethod, ParseMode;

    SendMessageMethod msg;
    msg.chat_id = chatId;
    msg.parse_mode = ParseMode.Markdown;
    msg.text = markDownText;

    logTrace("[chatId:%d] %s", chatId, msg.text);

    try
        telegram.sendMessage(msg);
    catch(tg.TelegramBotApiException e)
    {
        if(e.code == 403) // blocked by user
        {
            delChatId(chatId);
            logError("chat id %d blocks posting for this bot", chatId);
        }
        else
            logError(`Telegram: `~msg.text);
    }
}
