module db;

import d2sqlite3;
import std.exception: enforce;

private Database db;
private Statement stmnt_addChatId;
private Statement stmnt_checkChatId;
private Statement stmnt_getChatIds;
private Statement stmnt_delChatId;

void openDb(string filename = "paper_plane_db.sqlite3")
{
    db = Database(filename);

    db.run(`CREATE TABLE IF NOT EXISTS chats (
                chat_id INTEGER PRIMARY KEY NOT NULL
            )`);

    stmnt_addChatId = db.prepare(
        "INSERT INTO chats (chat_id)
         VALUES (:chat_id)"
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
}

// FIXME: here is need transaction
void upsertChatId(long chatId)
{
    stmnt_checkChatId.bind(1, chatId);
    auto count = stmnt_checkChatId.execute().oneValue!long;
    stmnt_checkChatId.reset;

    enforce(count <= 1);

    if(count == 0)
    {
        stmnt_addChatId.inject(chatId);

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
    addChatId(123);
    addChatId(456);

    long[] ids = getChatIds();
    assert(ids[0] == 123 || ids[0] == 456);
    assert(ids.length == 2);

    delChatId(123);
    assert(getChatIds.length == 1);
}
