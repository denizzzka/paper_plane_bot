module tg_http;

import core.time: seconds, Duration;
import std.algorithm.comparison: min;
import std.format: format;
import std.string: startsWith;
import tg_http = telega.http;
import vibe.data.json: Json, parseJsonString;
import vibe.http.client;
import vibe.stream.operations: readAllUTF8;

class TgHttpException : Exception
{
    this(string reason, string file = __FILE__, size_t line = __LINE__, Throwable nextInChain = null) @safe
    {
        super("reason: "~reason, file, line, nextInChain);
    }
}

/// How many seconds to wait when Telegram did not say: it describes rate
/// limit excesses itself, but over-insuring is cheaper than one extra wait.
enum floodWaitFallback = 10;

/// How many seconds Telegram told us to wait: zero if this is not a rate
/// limit excess.
///
/// retry_after lives in parameters, and telega neither parses them nor puts
/// them into the exception, so we read the response body ourselves instead
/// of digging the number out of the error text.
private Duration floodWait(string body)
{
    Json json;

    try
        json = parseJsonString(body);
    catch (Exception)
        return Duration.zero;

    if(json.type != Json.Type.object)
        return Duration.zero;

    auto code = json["error_code"];

    if(code.type != Json.Type.int_ || code.get!long != 429)
        return Duration.zero;

    auto parameters = json["parameters"];

    if(parameters.type != Json.Type.object)
        return Duration.zero;

    auto wait = parameters["retry_after"];

    if(wait.type != Json.Type.int_ || wait.get!long <= 0)
        return Duration.zero;

    return wait.get!long.seconds;
}

// HTTP client for Telegram: talks to api.telegram.org through the same
// settings as the feed download, that is through the shared proxy from
// config.json if one is set (http, https or socks5).
//
// We need our own client also for the sake of a timeout: telega's own
// client without a proxy has timeout equal to zero, that is it waits for
// Telegram's answer forever. A hanging socket would then stop the whole
// run and the notifications would never be sent. With a proxy we also
// need to parse the answer: Telegram replies with json even on errors,
// anything else is an answer of the proxy.
class TgHttpClient : tg_http.HttpClient
{
    private const HTTPClientSettings settings;
    private string proxyDesc;

    private Duration retryAfter;

    this(const HTTPClientSettings settings)
    {
        this.settings = settings;
        this.proxyDesc = settings.proxyURL.schema is null
            ? "server" : "proxy " ~ settings.proxyURL.toString;
    }

    string sendGetRequest(string url)
    {
        auto res = requestHTTP(url, null, settings);
        const code = res.statusCode;

        return answer(res.bodyReader.readAllUTF8(true), code);
    }

    string sendPostRequestJson(string url, string bodyJson)
    {
        auto res = requestHTTP(url, (scope req){
            req.method = HTTPMethod.POST;
            req.headers["Content-Type"] = "application/json";
            req.writeBody(cast(const(ubyte)[]) bodyJson);
        }, settings);
        const code = res.statusCode;

        return answer(res.bodyReader.readAllUTF8(true), code);
    }

    /// Delay from the last answer, taken and forgotten at once: it is only
    /// needed where we caught a rate limit excess.
    Duration takeRetryAfter()
    {
        const wait = retryAfter;
        retryAfter = Duration.zero;

        return wait;
    }

    // Telegram replies with json even on errors, anything else is the
    // answer of the proxy
    private string answer(string body, const int code)
    {
        if(!body.startsWith("{"))
            throw new TgHttpException(format(
                "%s replied with code %d: %s",
                proxyDesc,
                code,
                body[0 .. min(body.length, 200)],
            ));

        retryAfter = floodWait(body);

        return body;
    }
}

unittest
{
    // Telegram's answer body on a rate limit excess: error code in
    // error_code and the seconds to wait in parameters.retry_after
    const flood = `{"ok":false,"error_code":429,"description":"Too Many Requests: retry after 35",`~
        `"parameters":{"retry_after":35}}`;

    assert(floodWait(flood) == 35.seconds);

    // an excess without parameters and an unrelated error do not ask to wait
    assert(floodWait(`{"ok":false,"error_code":429,"description":"Too Many Requests"}`) == Duration.zero);
    assert(floodWait(`{"ok":false,"error_code":400,"description":"Bad Request: chat not found"}`) == Duration.zero);
    assert(floodWait(`proxy replied with code 502`) == Duration.zero);
}
