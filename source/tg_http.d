module tg_http;

import core.time: seconds, Duration;
import requests;
import std.algorithm.comparison: min;
import std.format: format;
import std.string: startsWith;
import tg_http = telega.http;
import vibe.data.json: Json, parseJsonString;

class TgHttpException : Exception
{
    this(string reason, string file = __FILE__, size_t line = __LINE__, Throwable nextInChain = null) @safe
    {
        super("reason: "~reason, file, line, nextInChain);
    }
}

/// Сколько секунд ждать, когда телега не сказала: превышение лимита она
/// описывает сама, но перестраховываться дешевле одного лишнего ожидания.
enum floodWaitFallback = 10;

/// Сколько секунд велела ждать телега: ноль, если это не превышение лимита.
///
/// retry_after лежит в parameters, а telega их не разбирает и в исключение
/// не кладёт, поэтому читаем тело ответа сами, а не выковыриваем число из
/// текста ошибки.
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

// HttpClient для телеги: ходит в api.telegram.org напрямую или через
// HTTP-прокси.
//
// Свой клиент нужен ещё и ради таймаута: у клиента telega без прокси
// timeout равен нулю, то есть ждёт ответ телеги вечно. Висящий сокет
// тогда останавливает весь парсер, а объявления так и не будут
// разосланы. С прокси нужен ещё и разбор ответа: телега даже на ошибку
// отвечает json'ом, а всё остальное - ответ прокси.
class TgHttpClient : tg_http.HttpClient
{
    private immutable string proxyUrl;
    private Request rq;

    private Duration retryAfter;

    this(string proxyUrl = "", Duration timeout = 20.seconds)
    {
        this.proxyUrl = proxyUrl;

        // пустой прокси не задаём: requests сам пойдёт напрямую
        if(proxyUrl.length > 0)
            rq.proxy = proxyUrl;

        rq.timeout = timeout;
    }

    string sendGetRequest(string url)
    {
        return answer(rq.get(url));
    }

    string sendPostRequestJson(string url, string bodyJson)
    {
        return answer(rq.post(url, bodyJson, "application/json"));
    }

    /// Задержка из последнего ответа и сразу забываем: нужна только там, где
    /// мы поймали превышение лимита.
    Duration takeRetryAfter()
    {
        const wait = retryAfter;
        retryAfter = Duration.zero;

        return wait;
    }

    // Телега даже на ошибку отвечает json'ом, всё остальное - ответ прокси
    private string answer(Response rs)
    {
        const body = rs.responseBody.toString;

        if(!body.startsWith("{"))
            throw new TgHttpException(format(
                "прокси %s ответил кодом %d: %s",
                proxyUrl,
                rs.code,
                body[0 .. min(body.length, 200)],
            ));

        retryAfter = floodWait(body);

        return body;
    }
}

unittest
{
    // тело ответа телеги при превышении лимита: номер ошибки в error_code,
    // а секунды ожидания в parameters.retry_after
    const flood = `{"ok":false,"error_code":429,"description":"Too Many Requests: retry after 35",`~
        `"parameters":{"retry_after":35}}`;

    assert(floodWait(flood) == 35.seconds);

    // превышение без parameters и посторонняя ошибка ждать не велят
    assert(floodWait(`{"ok":false,"error_code":429,"description":"Too Many Requests"}`) == Duration.zero);
    assert(floodWait(`{"ok":false,"error_code":400,"description":"Bad Request: chat not found"}`) == Duration.zero);
    assert(floodWait(`прокси ответил кодом 502`) == Duration.zero);
}
