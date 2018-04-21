module paper_plane_bot.grab;

import requests;
import vibe.data.json;

string[] getPackagesList()
{
    Json content = getContent(`https://code.dlang.org/packages/index.json`).toString.parseJsonString;

    string[] ret;

    foreach(ref j; content.byValue)
        ret ~= j.get!string;

    return ret;
}

Json getPackageDescription(string pkgName)
{
    return getContent(`https://code.dlang.org/packages/`~pkgName~`.json`).toString.parseJsonString;
}

import std.datetime.systime: SysTime;

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

    auto pkgs = getPackagesList;

    assert(pkgs.length > 0);
    assert(pkgs[0].length > 0);
    assert(canFind(pkgs, "dub"));

    auto pkg = getPackageDescription("dub");
    assert(pkg["name"].get!string == "dub");

    auto updated = pkg.getUpdatedTime;
    import std.stdio; writeln(updated);
    assert(updated > SysTime.min);
    assert(updated < SysTime.max);
}
