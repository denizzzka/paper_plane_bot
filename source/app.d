import std.stdio;
import paper_plane_bot.grab;
import db;

void main()
{
    import std.file;
    import std.datetime;

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
    string[] updatedPackages;

    import std.conv: to;

    foreach(const ref pkg; pkgs_list)
        if(pkg.updated >= lastModified.to!DateTime)
            updatedPackages ~= pkg.name;

    import std.stdio;
    writeln(updatedPackages);
}
