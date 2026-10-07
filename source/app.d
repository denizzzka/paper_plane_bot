import std.getopt;
import std.stdio;
import core.thread: Thread;
import core.time: Duration, MonoTime, msecs, seconds;
import paper_plane_bot.grab;
import db;
import tg = telega.botapi;
import tg_http;
import vibe.core.log;
import vibe.data.json;

private tg.BotApi telegram;
private TgHttpClient tgHttp;

// How we send on timeouts and rate limit excesses: the defaults, if the
// config has no such keys
private int sendRetries;
private Duration retryPause;
private Duration sendInterval;
private int floodWaits;

private bool paced;
private MonoTime nextSend;

void main(string[] args)
{
    import vibe.core.file: readFileUTF8;
    import vibe.http.client;

    bool fastForward;
    bool checkConn;

    auto helpInformation = getopt(
            args,
            "ff", `Only update DB but do not send anything to Telegram ("fast forward")`, &fastForward,
            "check_conn", `Only check that the feed and Telegram are reachable (through the proxy), then exit`, &checkConn,
        );

    if(helpInformation.helpWanted)
    {
        defaultGetoptPrinter("Some information about the program.", helpInformation.options);

        return;
    }

    setLogLevel(LogLevel.diagnostic);

    const configFile = readFileUTF8("config.json").parseJsonString;
    const tgconf = configFile["telegram"];

    httpSettings = new HTTPClientSettings;

    // readTimeout instead of infinite waiting: Telegram's long-poll keeps
    // the connection for up to 30 seconds, the rest must answer faster
    httpSettings.readTimeout = 60.seconds;

    // One proxy for everything: both sending to Telegram and downloading
    // the feed. If the key is absent - we go directly.
    {
        import vibe.inet.url;

        const proxy_url = "proxy" in configFile;
        if(proxy_url)
            httpSettings.proxyURL = URL(proxy_url.get!string);
    }

    if(httpSettings.proxyURL.schema !is null)
        logInfo("Proxy: %s", httpSettings.proxyURL);

    sendRetries = tgconf.confInt("sendRetries", 3);
    retryPause = tgconf.confInt("retryPauseMs", 2000).msecs;
    sendInterval = tgconf.confInt("sendIntervalMs", 50).msecs;
    floodWaits = tgconf.confInt("floodWaits", 3);

    // The client is also needed to parse Telegram's rate limit answer:
    // telega does not put retry_after into the exception
    tgHttp = new TgHttpClient(httpSettings);
    telegram = new tg.BotApi(tgconf["secretBotToken"].get!string, tg.BaseApiUrl, tgHttp);

    if(checkConn)
    {
        checkConnections();
        return;
    }

    const chatId = tgconf["chatId"].get!long;

    logInfo("Check Telegram for incoming private messages");
    processIncomingMessages();

    openDb();

    logInfo("Begin download packages list");
    auto pkgs_list = getPackagesSortedByUpdated;
    logInfo("Downloaded %d packages descriptions. Begin comparison for new versions.", pkgs_list.length);
    PackageDescr[] updatedPackages = getChangedPackages(pkgs_list);
    logInfo("Number of new or updated descriptions: %d", updatedPackages.length);

    import std.conv: to;

    foreach(pkg; updatedPackages)
        logInfo(pkg.to!string);

    if(fastForward)
    {
        logDiagnostic(`"Fast forward" enabled: Do not send updates to TG`);

        foreach(ref pkg; updatedPackages)
            markPackage(pkg);
    }
    else
    {
        logInfo("Send updates into chat");

        // The version is remembered only after Telegram accepted the
        // message: a package that was not sent stays changed and goes out
        // on the next run, while an accepted one is never repeated
        foreach_reverse(ref pkg; updatedPackages)
            if(sendPackageUpdatedNotify(chatId, pkg))
                markPackage(pkg);
    }
}

// --check_conn: try to reach the feed and Telegram by the same routes as a
// regular run (that is through the proxy from the config) and report. We
// write nothing to the DB and nothing to Telegram.
void checkConnections()
{
    import core.stdc.stdlib: exit;
    import telega.telegram.basic: getMe;

    writefln("proxy: %s", httpSettings.proxyURL.schema is null
        ? "none" : httpSettings.proxyURL.toString);

    bool ok = checkOne("feed (code.dlang.org)", { getPackageDescription("dub"); });
    ok &= checkOne("telegram (api.telegram.org)", { telegram.getMe(); });

    if(!ok)
        exit(1);
}

/// Performs the check and prints its result: returns whether it succeeded
private bool checkOne(string what, void delegate() action)
{
    import std.datetime.stopwatch: AutoStart, StopWatch;

    auto timer = StopWatch(AutoStart.yes);
    string err;

    try
        action();
    catch(Exception e)
        err = e.msg;

    timer.stop();

    if(err is null)
        writefln("%s: OK, %d ms", what, timer.peek.total!"msecs");
    else
        writefln("%s: FAILED, %d ms: %s", what, timer.peek.total!"msecs", err);

    return err is null;
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

/// Sends the package news and reports whether Telegram accepted it: the
/// caller remembers the version only on true.
bool sendPackageUpdatedNotify(in long chatId, in PackageDescr pkg)
{
    import std.format;

    const text = format(
        "A new version of dub package [%s](https://code.dlang.org/%s) *%s* has been released",
        pkg.name,
        pkg.url,
        pkg.ver,
    );

    return sendNotify(chatId, text);
}

/// Sends the message and reports whether Telegram accepted it.
///
/// false means Telegram refused the message itself (a wrong chat, a blocked
/// bot and so on): retrying the same run is pointless, so the caller leaves
/// the package unchanged and it is attempted again on the next run.
/// Transport failures and rate limit excesses that survive their own
/// retries throw and stop the whole run, everything already sent stays
/// remembered.
bool sendNotify(in long chatId, in string markDownText)
{
    import telega.telegram.basic: sendMessage, SendMessageMethod, ParseMode;

    SendMessageMethod msg;
    msg.chat_id = chatId;
    msg.parse_mode = ParseMode.Markdown;
    msg.text = markDownText;

    logTrace("[chatId:%d] %s", chatId, msg.text);

    int attempt;
    int waited;

    // network failures we retry, Telegram's own answers - not: retrying
    // them is pointless
    while(attempt < sendRetries)
    {
        pace();

        try
        {
            telegram.sendMessage(msg);

            return true;
        }
        catch(tg.TelegramBotApiException e)
        {
            // a rate limit excess does not count as a failed attempt: Telegram
            // itself tells us to wait, and this is not a sending failure
            if(e.code == 429)
            {
                if(++waited > floodWaits)
                    throw e;

                const wait = tgHttp.takeRetryAfter();
                const pause = wait > Duration.zero ? wait : floodWaitFallback.seconds;

                logWarn("Telegram asks to wait %d s", cast(long) pause.total!"seconds");

                Thread.sleep(pause);

                continue;
            }

            // Telegram's own answer, retrying is pointless
            if(e.code == 403) // blocked by user
            {
                delChatId(chatId);
                logError("chat id %d blocks posting for this bot", chatId);
            }
            else
                logError(`Telegram: `~msg.text);

            return false;
        }
        catch(Exception e)
        {
            if(++attempt == sendRetries)
                throw e;

            logError("Telegram send failed, attempt %d of %d: %s", attempt, sendRetries, e.msg);

            Thread.sleep(retryPause * attempt);
        }
    }

    return false;
}

/// We keep a pause between messages: Telegram's limit counts per token as a
/// whole, and the send queue is long and goes in a row.
private void pace()
{
    if(paced)
    {
        const wait = nextSend - MonoTime.currTime;

        if(wait.total!"nsecs" > 0)
            Thread.sleep(wait);
    }

    paced = true;
    nextSend = MonoTime.currTime + sendInterval;
}

// A number from config.json or the default, if there is no such key
private int confInt(in Json conf, string name, int defaultValue)
{
    if(conf[name].type == Json.Type.undefined)
        return defaultValue;

    return conf[name].get!int;
}
