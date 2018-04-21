import std.stdio;
import paper_plane_bot.grab;

void main()
{
    import std.file;
    import std.datetime;

    const string filename = "last_updated_mtime.txt";

    SysTime lastModified = Clock.currTime;

    {
        try
            lastModified = filename.timeLastModified;
        catch(FileException){} // file not found, will be created new one

        filename.write([]);
    }
}
