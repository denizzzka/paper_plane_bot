import std.stdio;
import d2sqlite3;
import paper_plane_bot.grab;

void main()
{
    import std.file: exists;

    const string filename = "packages.sqlite3";
    const bool isNeedNewDB = !filename.exists;

    auto db = Database(filename);

    if(isNeedNewDB)
    {
        writeln(`DB file `~filename~`is not found, creating new one`);

        db.run(`CREATE TABLE packages (
                  name  TEXT PRIMARY KEY NOT NULL,
                  updated TEXT NOT NULL
                )`);

        writeln(`Downloading packages list and filling out DB`);

        auto packages = getPackagesList;
    }
}
