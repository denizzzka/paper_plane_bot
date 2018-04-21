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

Json getPackageContent(string pkgName)
{
    return getContent(`https://code.dlang.org/packages/`~pkgName~`.json`).toString.parseJsonString;
}

unittest
{
    import std.algorithm.searching;

    auto pkgs = getPackagesList;

    assert(pkgs.length > 0);
    assert(pkgs[0].length > 0);
    assert(canFind(pkgs, "dub"));

    auto pkg = getPackageContent("dub");
    assert(pkg["name"].get!string == "dub");
}
