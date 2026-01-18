module paper_plane_bot.grab;

import vibe.data.json;
import std.datetime;
import std.conv: to;

auto getContentObj(string url)
{
    import vibe.http.client;

    return requestHTTP(
        url,
        (req){
            req.headers["User-Agent"] = "DlangAnnounceBot (+https://github.com/denizzzka/paper_plane_bot)";
        }
    );
}

Json getContentJson(string url)
{
    return url.getContentObj.readJson;
}

string getContentUTF8String(string url)
{
    import vibe.core.stream: pipe;
    import vibe.stream.memory: createMemoryOutputStream;
    import std.utf: toUTF8;

    auto res = getContentObj(url);
    auto istr = res.bodyReader;
    auto inMem = createMemoryOutputStream;

    pipe(istr, inMem, ulong.max);

    return (cast(char[]) inMem.data).toUTF8;
}

string[] getPackagesList()
{
    Json content = getContentJson(`https://code.dlang.org/packages/index.json`);

    string[] ret;

    foreach(ref j; content.byValue)
        ret ~= j.get!string;

    return ret;
}

Json getPackageDescription(string pkgName)
{
    return getContentJson(`https://code.dlang.org/packages/`~pkgName~`.json`);
}

SysTime getUpdatedTime(Json packageDescription)
{
    auto arr = packageDescription["versions"];

    SysTime k = SysTime.min;

    foreach(ref e; arr.byValue)
    {
        SysTime curr = SysTime.fromISOExtString(e["date"].get!string);

        if(curr > k)
            k = curr;
    }

    return k;
}

unittest
{
    import std.algorithm.searching;

    //~ auto pkgs = getPackagesList; // this function isn't used

    //~ assert(pkgs.length > 0);
    //~ assert(pkgs[0].length > 0);
    //~ assert(canFind(pkgs, "dub"));

    auto pkg = getPackageDescription("dub");
    assert(pkg["name"].get!string == "dub");

    auto updated = pkg.getUpdatedTime;
    assert(updated > SysTime.min);
    assert(updated < SysTime.max);
}

struct PackageDescr
{
    string name;
    DateTime updated;
    string ver;
    string url;
}

PackageDescr[] getPackagesSortedByUpdated()
{
    import html;

    const string url = `https://code.dlang.org/?sort=updated&category=&skip=0&limit=10000000`;
    auto htmldoc = url.getContentUTF8String.createDocument;

    auto tbl = htmldoc.querySelector("html body div#content table");
    auto rows = tbl.find("tr");

    PackageDescr[] ret;

    foreach(r; rows)
    {
        PackageDescr d;

        d.name = r.find("a").front.text.to!string;
        d.url = r.find("a").front.attr("href").to!string;
        auto ts = r.find(`span.dull`).front.to!string.idup.fetchTimeFromHtml;

        if(ts.length > 0)
        {
            d.updated = DateTime.fromSimpleString(ts);
            d.ver = r.find(`.nobreak`).front.text.to!string.fetchVerFromHtml;

            ret ~= d;
        }
    }

    return ret;
}

unittest
{
    auto pkgs = getPackagesSortedByUpdated;

    assert(pkgs[0].updated > DateTime.min);
    assert(pkgs[0].updated < DateTime.max);
    assert(pkgs[0].ver.length > 3);
    assert(pkgs[0].url[0 .. 8] == "packages");
}

// Due to attr(name) fails
private string fetchTimeFromHtml(string html)
{
    import std.regex;

    auto r = regex(`title="([0-9][0-9][0-9][0-9]-.+?)Z"`);

    return matchFirst(html, r)[1];
}

unittest
{
    string s = `<span title="2018-Apr-20 20:50:05Z" class="dull nobreak"/>`;

    assert(s.fetchTimeFromHtml == "2018-Apr-20 20:50:05");
}

// Due to broken page formatting
private string fetchVerFromHtml(string html)
{
    import std.regex;
    import std.string: strip;

    auto r = regex(`(.+?),`);

    return matchFirst(html.strip, r)[1];
}

unittest
{
    string s = `					0.15.16, an hour ago`;

    assert(s.fetchVerFromHtml == "0.15.16");
}
