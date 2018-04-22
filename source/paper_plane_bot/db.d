module db;

import d2sqlite3;
import std.exception: enforce;

private Database db;
private Statement stmnt_addChatId;
private Statement stmnt_checkChatId;
private Statement stmnt_getChatIds;
private Statement stmnt_delChatId;
private Statement stmnt_upsertPackage;
private Statement stmnt_getPackageVersion;

void openDb(string filename = "paper_plane_db.sqlite3")
{
    db = Database(filename);

    db.run(`CREATE TABLE IF NOT EXISTS chats (
                chat_id INTEGER PRIMARY KEY NOT NULL,
                descr TEXT
            )`);

    db.run(`CREATE TABLE IF NOT EXISTS packages (
                name TEXT PRIMARY KEY NOT NULL,
                version TEXT NOT NULL
            )`);

    stmnt_addChatId = db.prepare(
        "INSERT INTO chats (chat_id, descr)
         VALUES (:chat_id, :descr)"
    );

    stmnt_checkChatId = db.prepare(
        "SELECT count(*) FROM chats WHERE chat_id = :chat_id"
    );

    stmnt_getChatIds = db.prepare(
        "SELECT chat_id FROM chats"
    );

    stmnt_delChatId = db.prepare(
        "DELETE FROM chats WHERE chat_id = :chat_id"
    );

    stmnt_upsertPackage = db.prepare(
        "INSERT OR REPLACE INTO packages (name, version)
         VALUES (:name, :version)"
    );

    stmnt_getPackageVersion = db.prepare(
        "SELECT version FROM packages WHERE name = :name"
    );
}

// FIXME: here is need transaction
void upsertChatId(long chatId, string descr)
{
    stmnt_checkChatId.bind(1, chatId);
    auto count = stmnt_checkChatId.execute().oneValue!long;
    stmnt_checkChatId.reset;

    enforce(count <= 1);

    if(count == 0)
    {
        stmnt_addChatId.inject(chatId, descr);

        enforce(db.changes == 1);
    }
}

long[] getChatIds()
{
    auto res = stmnt_getChatIds.execute();

    long[] ret;

    foreach(row; res)
        ret ~= row.peek!long(0);

    stmnt_getChatIds.reset();

    return ret;
}

void delChatId(long chatId)
{
    import std.conv: to;

    stmnt_delChatId.inject(chatId);
    enforce(db.changes == 1, db.changes.to!string);
}

unittest
{
    openDb(":memory:");
    upsertChatId(123, "some description");
    upsertChatId(456, "sdf sdf");

    long[] ids = getChatIds();
    assert(ids[0] == 123 || ids[0] == 456);
    assert(ids.length == 2);

    delChatId(123);
    assert(getChatIds.length == 1);
}

import paper_plane_bot.grab: PackageDescr;

/// Returns: packages with changed version since last check
PackageDescr[] upsertPackages(PackageDescr[] pkgs)
{
    PackageDescr[] changed;

    foreach(ref pkg; pkgs)
    {
        stmnt_getPackageVersion.bind(1, pkg.name);
        auto res = stmnt_getPackageVersion.execute;

        if(
            res.empty || // new package
            pkg.ver != res.front.peek!string(0) // version changed
        )
        {
            stmnt_upsertPackage.inject(pkg.name, pkg.ver);
            changed ~= pkg;
        }

        stmnt_getPackageVersion.reset;
    }

    return changed;
}

unittest
{
    openDb(":memory:");

    PackageDescr pkg1 = {name: "test1", ver: "123"};
    PackageDescr pkg2 = {name: "test2", ver: "456"};

    auto r1 = upsertPackages([pkg1, pkg2]);
    assert(r1.length == 2);

    pkg2.ver = "888";

    auto upsert1 = upsertPackages([pkg1, pkg2]);
    assert(upsert1.length == 1);
    assert(upsert1[0].ver == "888");
}
