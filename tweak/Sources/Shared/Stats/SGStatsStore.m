#import "SGStatsStore.h"
#import <sqlite3.h>

@implementation SGStatsPlay
@end

@implementation SGStatsStore {
    sqlite3 *_db;
    dispatch_queue_t _queue;
}

+ (instancetype)shared {
    static SGStatsStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ store = [SGStatsStore new]; });
    return store;
}

- (instancetype)init {
    if ((self = [super init])) _queue = dispatch_queue_create("spotifyglass.stats", DISPATCH_QUEUE_SERIAL);
    return self;
}

- (NSString *)path {
    static NSString *path;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *documents = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        path = [documents stringByAppendingPathComponent:@"SGStats.sqlite"];
    });
    return path;
}

static BOOL hasColumn(sqlite3 *db, const char *column) {
    sqlite3_stmt *stmt = NULL;
    BOOL found = NO;
    if (sqlite3_prepare_v2(db, "PRAGMA table_info(plays);", -1, &stmt, NULL) == SQLITE_OK && stmt) {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            const char *name = (const char *)sqlite3_column_text(stmt, 1);
            if (name && strcmp(name, column) == 0) { found = YES; break; }
        }
        sqlite3_finalize(stmt);
    }
    return found;
}

static void ensureColumn(sqlite3 *db, const char *column, const char *definition) {
    if (hasColumn(db, column)) return;
    NSString *sql = [NSString stringWithFormat:@"ALTER TABLE plays ADD COLUMN %s %s;", column, definition];
    sqlite3_exec(db, sql.UTF8String, NULL, NULL, NULL);
}

- (BOOL)open {
    if (_db) return YES;
    if (sqlite3_open_v2(self.path.UTF8String, &_db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, NULL) != SQLITE_OK) {
        _db = NULL;
        return NO;
    }
    sqlite3_exec(_db, "PRAGMA journal_mode=WAL;", NULL, NULL, NULL);
    sqlite3_exec(_db,
        "CREATE TABLE IF NOT EXISTS plays ("
        " id INTEGER PRIMARY KEY AUTOINCREMENT,"
        " ts INTEGER NOT NULL,"
        " track_uri TEXT, title TEXT, artist_uri TEXT, artist TEXT,"
        " album_uri TEXT, album TEXT, artwork TEXT,"
        " ms INTEGER NOT NULL, source INTEGER NOT NULL DEFAULT 0);", NULL, NULL, NULL);
    // Columns added after the first release, so a store written by an older build still opens.
    ensureColumn(_db, "skipped", "INTEGER NOT NULL DEFAULT 0");
    ensureColumn(_db, "reason_end", "TEXT");
    ensureColumn(_db, "platform", "TEXT");
    ensureColumn(_db, "offline", "INTEGER NOT NULL DEFAULT 0");
    ensureColumn(_db, "shuffle", "INTEGER NOT NULL DEFAULT 0");
    ensureColumn(_db, "context_uri", "TEXT");
    sqlite3_exec(_db,
        "CREATE INDEX IF NOT EXISTS plays_ts ON plays(ts);"
        "CREATE INDEX IF NOT EXISTS plays_track ON plays(track_uri);", NULL, NULL, NULL);
    // One row per play: a re-import of the same history must not double it. The expression index
    // needs the rows unique first, so if it will not build, the copies are removed and it is asked
    // again.
    if (sqlite3_exec(_db, "CREATE UNIQUE INDEX IF NOT EXISTS plays_key ON plays(ts, IFNULL(track_uri, title));", NULL, NULL, NULL) != SQLITE_OK) {
        sqlite3_exec(_db, "DELETE FROM plays WHERE id NOT IN (SELECT MIN(id) FROM plays GROUP BY ts, IFNULL(track_uri, title));", NULL, NULL, NULL);
        sqlite3_exec(_db, "CREATE UNIQUE INDEX IF NOT EXISTS plays_key ON plays(ts, IFNULL(track_uri, title));", NULL, NULL, NULL);
    }
    return YES;
}

static void bindText(sqlite3_stmt *stmt, int index, NSString *value) {
    if (value.length) sqlite3_bind_text(stmt, index, value.UTF8String, -1, SQLITE_TRANSIENT);
    else sqlite3_bind_null(stmt, index);
}

- (void)addPlay:(SGStatsPlay *)play {
    [self addPlays:@[play]];
}

- (void)addPlays:(NSArray<SGStatsPlay *> *)plays {
    if (!plays.count) return;
    dispatch_sync(_queue, ^{
        if (!self->_db && ![self open]) return;
        sqlite3_exec(self->_db, "BEGIN;", NULL, NULL, NULL);
        sqlite3_stmt *stmt = NULL;
        sqlite3_prepare_v2(self->_db,
            "INSERT OR IGNORE INTO plays (ts, track_uri, title, artist_uri, artist, album_uri, album, artwork, ms, source,"
            " skipped, reason_end, platform, offline, shuffle, context_uri)"
            " VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);", -1, &stmt, NULL);
        if (stmt) {
            NSInteger batch = 0;
            for (SGStatsPlay *play in plays) {
                sqlite3_bind_int64(stmt, 1, play.ts);
                bindText(stmt, 2, play.trackURI);
                bindText(stmt, 3, play.title);
                bindText(stmt, 4, play.artistURI);
                bindText(stmt, 5, play.artist);
                bindText(stmt, 6, play.albumURI);
                bindText(stmt, 7, play.album);
                bindText(stmt, 8, play.artwork);
                sqlite3_bind_int64(stmt, 9, play.ms);
                sqlite3_bind_int(stmt, 10, (int)play.source);
                sqlite3_bind_int(stmt, 11, play.skipped);
                bindText(stmt, 12, play.reasonEnd);
                bindText(stmt, 13, play.platform);
                sqlite3_bind_int(stmt, 14, play.offline);
                sqlite3_bind_int(stmt, 15, play.shuffled);
                bindText(stmt, 16, play.contextURI);
                sqlite3_step(stmt);
                sqlite3_reset(stmt);
                // Committed as it goes, so a large import the watchdog ends still keeps what it read.
                if (++batch % 2000 == 0) {
                    sqlite3_exec(self->_db, "COMMIT;", NULL, NULL, NULL);
                    sqlite3_exec(self->_db, "BEGIN;", NULL, NULL, NULL);
                }
            }
            sqlite3_finalize(stmt);
        }
        sqlite3_exec(self->_db, "COMMIT;", NULL, NULL, NULL);
    });
}

- (NSString *)filePath {
    return [self path];
}

- (void)checkpoint {
    dispatch_sync(_queue, ^{
        if (!self->_db && ![self open]) return;
        sqlite3_exec(self->_db, "PRAGMA wal_checkpoint(TRUNCATE);", NULL, NULL, NULL);
    });
}

- (void)eraseAll {
    dispatch_sync(_queue, ^{
        if (!self->_db && ![self open]) return;
        sqlite3_exec(self->_db, "DELETE FROM plays;", NULL, NULL, NULL);
    });
}

- (BOOL)hasLivePlays {
    __block BOOL found = NO;
    dispatch_sync(_queue, ^{
        if (!self->_db && ![self open]) return;
        sqlite3_stmt *stmt = NULL;
        sqlite3_prepare_v2(self->_db, "SELECT 1 FROM plays WHERE source = 0 LIMIT 1;", -1, &stmt, NULL);
        if (stmt) { found = sqlite3_step(stmt) == SQLITE_ROW; sqlite3_finalize(stmt); }
    });
    return found;
}

- (NSInteger)playCount {
    __block NSInteger count = 0;
    dispatch_sync(_queue, ^{
        if (!self->_db && ![self open]) return;
        sqlite3_stmt *stmt = NULL;
        sqlite3_prepare_v2(self->_db, "SELECT COUNT(*) FROM plays;", -1, &stmt, NULL);
        if (stmt) { if (sqlite3_step(stmt) == SQLITE_ROW) count = (NSInteger)sqlite3_column_int64(stmt, 0); sqlite3_finalize(stmt); }
    });
    return count;
}

// Albums and artists group by name, not URI: an imported play carries no URIs and a live one does,
// so a URI key would split the same artist or album in two. Tracks keep their URI, which both
// sources have.
static NSString *entityKey(SGStatsEntity entity) {
    switch (entity) {
        case SGStatsEntityTrack: return @"COALESCE(track_uri, 'n:' || IFNULL(title,'') || '|' || IFNULL(artist,''))";
        case SGStatsEntityAlbum: return @"'a:' || LOWER(IFNULL(album,'')) || '|' || LOWER(IFNULL(artist,''))";
        case SGStatsEntityArtist: return @"'r:' || LOWER(IFNULL(artist,''))";
    }
    return nil;
}

static NSString *entityName(SGStatsEntity entity) {
    switch (entity) {
        case SGStatsEntityAlbum: return @"MAX(album)";
        case SGStatsEntityArtist: return @"MAX(artist)";
        default: return @"MAX(title)";
    }
}

static NSString *entitySubtitle(SGStatsEntity entity) {
    return entity == SGStatsEntityArtist ? @"NULL" : @"MAX(artist)";
}

static NSString *entityURI(SGStatsEntity entity) {
    switch (entity) {
        case SGStatsEntityAlbum: return @"MAX(album_uri)";
        case SGStatsEntityArtist: return @"MAX(artist_uri)";
        default: return @"MAX(track_uri)";
    }
}

static NSString *entityArtwork(SGStatsEntity entity) {
    return entity == SGStatsEntityArtist ? @"NULL" : @"MAX(artwork)";
}

static NSString *orderClause(SGStatsOrder order) {
    switch (order) {
        case SGStatsOrderMinutes: return @"total DESC";
        case SGStatsOrderDays: return @"days DESC";
        default: return @"plays DESC";
    }
}

// name, subtitle, uri, artwork, plays, skips, total, days, first, last
- (NSArray<SGStatsEntry *> *)readEntries:(sqlite3_stmt *)stmt {
    NSMutableArray<SGStatsEntry *> *entries = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        SGStatsEntry *entry = [SGStatsEntry new];
        const char *text = (const char *)sqlite3_column_text(stmt, 0);
        entry.name = text ? @(text) : nil;
        text = (const char *)sqlite3_column_text(stmt, 1);
        entry.subtitle = text ? @(text) : nil;
        text = (const char *)sqlite3_column_text(stmt, 2);
        entry.uri = text ? @(text) : nil;
        text = (const char *)sqlite3_column_text(stmt, 3);
        entry.artwork = text ? @(text) : nil;
        entry.plays = (NSInteger)sqlite3_column_int64(stmt, 4);
        entry.skips = (NSInteger)sqlite3_column_int64(stmt, 5);
        entry.ms = sqlite3_column_int64(stmt, 6);
        entry.first = sqlite3_column_int64(stmt, 8);
        entry.last = sqlite3_column_int64(stmt, 9);
        [entries addObject:entry];
    }
    return entries;
}

- (NSArray<SGStatsEntry *> *)top:(SGStatsEntity)entity order:(SGStatsOrder)order since:(int64_t)since until:(int64_t)until limit:(NSInteger)limit {
    NSMutableArray<SGStatsEntry *> *entries = [NSMutableArray array];
    NSString *sql = [NSString stringWithFormat:
        @"SELECT %@ AS name, %@ AS subtitle, %@ AS uri, %@ AS artwork,"
         " COUNT(*) AS plays, IFNULL(SUM(skipped),0) AS skips, SUM(ms) AS total,"
         " COUNT(DISTINCT date(ts,'unixepoch','localtime')) AS days, MIN(ts) AS first, MAX(ts) AS last"
         " FROM plays WHERE ts >= ? AND (? = 0 OR ts < ?) GROUP BY %@ HAVING name IS NOT NULL AND name <> ''"
         " ORDER BY %@, name LIMIT ?;",
        entityName(entity), entitySubtitle(entity), entityURI(entity), entityArtwork(entity), entityKey(entity), orderClause(order)];
    dispatch_sync(_queue, ^{
        if (!self->_db && ![self open]) return;
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql.UTF8String, -1, &stmt, NULL) != SQLITE_OK) return;
        sqlite3_bind_int64(stmt, 1, since);
        sqlite3_bind_int64(stmt, 2, until);
        sqlite3_bind_int64(stmt, 3, until);
        sqlite3_bind_int(stmt, 4, (int)limit);
        [entries addObjectsFromArray:[self readEntries:stmt]];
        sqlite3_finalize(stmt);
    });
    return entries;
}

- (NSArray<SGStatsEntry *> *)discover:(SGStatsDiscover)kind entity:(SGStatsEntity)entity since:(int64_t)since until:(int64_t)until limit:(NSInteger)limit {
    NSString *having = kind == SGStatsDiscoverNew ? @"HAVING MIN(ts) >= ?"
                     : (kind == SGStatsDiscoverForgotten ? @"HAVING MAX(ts) < ? AND SUM(ms) > 0"
                     : @"HAVING name IS NOT NULL AND name <> ''");
    NSString *where = kind == SGStatsDiscoverOnRepeat ? @"ts >= ? AND (? = 0 OR ts < ?)" : @"(? = 0 OR ts < ?)";
    NSString *sql = [NSString stringWithFormat:
        @"SELECT %@ AS name, %@ AS subtitle, %@ AS uri, %@ AS artwork,"
         " COUNT(*) AS plays, IFNULL(SUM(skipped),0) AS skips, SUM(ms) AS total,"
         " COUNT(DISTINCT date(ts,'unixepoch','localtime')) AS days, MIN(ts) AS first, MAX(ts) AS last"
         " FROM plays WHERE %@ GROUP BY %@ %@ ORDER BY total DESC, name LIMIT ?;",
        entityName(entity), entitySubtitle(entity), entityURI(entity), entityArtwork(entity), where, entityKey(entity), having];
    NSMutableArray<SGStatsEntry *> *entries = [NSMutableArray array];
    dispatch_sync(_queue, ^{
        if (!self->_db && ![self open]) return;
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql.UTF8String, -1, &stmt, NULL) != SQLITE_OK) return;
        int index = 1;
        if (kind == SGStatsDiscoverOnRepeat) {
            sqlite3_bind_int64(stmt, index++, since);
            sqlite3_bind_int64(stmt, index++, until);
            sqlite3_bind_int64(stmt, index++, until);
        } else {
            sqlite3_bind_int64(stmt, index++, until);
        }
        if (kind != SGStatsDiscoverOnRepeat) sqlite3_bind_int64(stmt, index++, since);
        sqlite3_bind_int(stmt, index, (int)limit);
        [entries addObjectsFromArray:[self readEntries:stmt]];
        sqlite3_finalize(stmt);
    });
    return entries;
}

- (SGStatsSummary *)summarySince:(int64_t)since {
    SGStatsSummary *summary = [SGStatsSummary new];
    dispatch_sync(_queue, ^{
        if (!self->_db && ![self open]) return;
        const char *sql =
            "SELECT IFNULL(SUM(ms),0), COUNT(*),"
            " COUNT(DISTINCT COALESCE(track_uri,title)),"
            " COUNT(DISTINCT COALESCE(album_uri,album)),"
            " COUNT(DISTINCT COALESCE(artist_uri,artist))"
            " FROM plays WHERE ts >= ?;";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) != SQLITE_OK) return;
        sqlite3_bind_int64(stmt, 1, since);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            summary.ms = sqlite3_column_int64(stmt, 0);
            summary.plays = (NSInteger)sqlite3_column_int64(stmt, 1);
            summary.tracks = (NSInteger)sqlite3_column_int64(stmt, 2);
            summary.albums = (NSInteger)sqlite3_column_int64(stmt, 3);
            summary.artists = (NSInteger)sqlite3_column_int64(stmt, 4);
        }
        sqlite3_finalize(stmt);
    });
    return summary;
}

- (NSArray<SGStatsDay *> *)dailySince:(int64_t)since {
    NSMutableArray<SGStatsDay *> *days = [NSMutableArray array];
    dispatch_sync(_queue, ^{
        if (!self->_db && ![self open]) return;
        const char *sql =
            "SELECT CAST(strftime('%s', date(ts,'unixepoch','localtime')) AS INTEGER) AS day, SUM(ms)"
            " FROM plays WHERE ts >= ? GROUP BY day ORDER BY day;";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) != SQLITE_OK) return;
        sqlite3_bind_int64(stmt, 1, since);
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            SGStatsDay *day = [SGStatsDay new];
            day.day = sqlite3_column_int64(stmt, 0);
            day.ms = sqlite3_column_int64(stmt, 1);
            [days addObject:day];
        }
        sqlite3_finalize(stmt);
    });
    return days;
}

- (NSArray<NSNumber *> *)clockSince:(int64_t)since {
    NSMutableArray<NSNumber *> *cells = [NSMutableArray array];
    for (NSInteger i = 0; i < 168; i++) [cells addObject:@0];
    dispatch_sync(_queue, ^{
        if (!self->_db && ![self open]) return;
        const char *sql =
            "SELECT CAST(strftime('%w', ts,'unixepoch','localtime') AS INTEGER) AS wd,"
            " CAST(strftime('%H', ts,'unixepoch','localtime') AS INTEGER) AS hr, SUM(ms)"
            " FROM plays WHERE ts >= ? GROUP BY wd, hr;";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) != SQLITE_OK) return;
        sqlite3_bind_int64(stmt, 1, since);
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            NSInteger index = (NSInteger)sqlite3_column_int64(stmt, 0) * 24 + (NSInteger)sqlite3_column_int64(stmt, 1);
            if (index >= 0 && index < 168) cells[index] = @(sqlite3_column_int64(stmt, 2));
        }
        sqlite3_finalize(stmt);
    });
    return cells;
}

static SGStatsPlay *playFromRow(sqlite3_stmt *stmt) {
    SGStatsPlay *play = [SGStatsPlay new];
    play.ts = sqlite3_column_int64(stmt, 0);
    const char *text = (const char *)sqlite3_column_text(stmt, 1); play.trackURI = text ? @(text) : nil;
    text = (const char *)sqlite3_column_text(stmt, 2); play.title = text ? @(text) : nil;
    text = (const char *)sqlite3_column_text(stmt, 3); play.artistURI = text ? @(text) : nil;
    text = (const char *)sqlite3_column_text(stmt, 4); play.artist = text ? @(text) : nil;
    text = (const char *)sqlite3_column_text(stmt, 5); play.albumURI = text ? @(text) : nil;
    text = (const char *)sqlite3_column_text(stmt, 6); play.album = text ? @(text) : nil;
    text = (const char *)sqlite3_column_text(stmt, 7); play.artwork = text ? @(text) : nil;
    play.ms = sqlite3_column_int64(stmt, 8);
    play.source = (NSInteger)sqlite3_column_int64(stmt, 9);
    play.skipped = sqlite3_column_int64(stmt, 10) != 0;
    text = (const char *)sqlite3_column_text(stmt, 11); play.reasonEnd = text ? @(text) : nil;
    text = (const char *)sqlite3_column_text(stmt, 12); play.platform = text ? @(text) : nil;
    play.offline = sqlite3_column_int64(stmt, 13) != 0;
    play.shuffled = sqlite3_column_int64(stmt, 14) != 0;
    text = (const char *)sqlite3_column_text(stmt, 15); play.contextURI = text ? @(text) : nil;
    return play;
}

static const char *kPlayColumns =
    "ts, track_uri, title, artist_uri, artist, album_uri, album, artwork, ms, source,"
    " skipped, reason_end, platform, offline, shuffle, context_uri";

- (NSArray<SGStatsPlay *> *)recentLimit:(NSInteger)limit {
    NSMutableArray<SGStatsPlay *> *plays = [NSMutableArray array];
    dispatch_sync(_queue, ^{
        if (!self->_db && ![self open]) return;
        NSString *sql = [NSString stringWithFormat:@"SELECT %s FROM plays ORDER BY ts DESC LIMIT ?;", kPlayColumns];
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql.UTF8String, -1, &stmt, NULL) != SQLITE_OK) return;
        sqlite3_bind_int(stmt, 1, (int)limit);
        while (sqlite3_step(stmt) == SQLITE_ROW) [plays addObject:playFromRow(stmt)];
        sqlite3_finalize(stmt);
    });
    return plays;
}

- (NSArray<SGStatsPlay *> *)allPlays {
    NSMutableArray<SGStatsPlay *> *plays = [NSMutableArray array];
    dispatch_sync(_queue, ^{
        if (!self->_db && ![self open]) return;
        NSString *sql = [NSString stringWithFormat:@"SELECT %s FROM plays ORDER BY ts;", kPlayColumns];
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql.UTF8String, -1, &stmt, NULL) != SQLITE_OK) return;
        while (sqlite3_step(stmt) == SQLITE_ROW) [plays addObject:playFromRow(stmt)];
        sqlite3_finalize(stmt);
    });
    return plays;
}

static NSString *firstText(sqlite3 *db, const char *sql, NSString *value) {
    if (!value.length) return nil;
    __block NSString *result = nil;
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) == SQLITE_OK && stmt) {
        sqlite3_bind_text(stmt, 1, value.UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            const char *text = (const char *)sqlite3_column_text(stmt, 0);
            if (text) result = @(text);
        }
        sqlite3_finalize(stmt);
    }
    return result;
}

static NSString *firstTextArtist(sqlite3 *db, const char *sql, NSString *first, NSString *second) {
    if (!first.length) return nil;
    __block NSString *result = nil;
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) == SQLITE_OK && stmt) {
        sqlite3_bind_text(stmt, 1, first.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, (second ?: @"").UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            const char *text = (const char *)sqlite3_column_text(stmt, 0);
            if (text) result = @(text);
        }
        sqlite3_finalize(stmt);
    }
    return result;
}

- (NSString *)anyTrackURIForAlbum:(NSString *)album artist:(NSString *)artist {
    __block NSString *result = nil;
    dispatch_sync(_queue, ^{
        if (!self->_db && ![self open]) return;
        result = firstTextArtist(self->_db, "SELECT track_uri FROM plays WHERE LOWER(album) = LOWER(?) AND LOWER(artist) = LOWER(?) AND track_uri IS NOT NULL AND track_uri <> '' LIMIT 1;", album, artist);
    });
    return result;
}

- (NSString *)anyTrackURIForArtist:(NSString *)artist {
    __block NSString *result = nil;
    dispatch_sync(_queue, ^{
        if (!self->_db && ![self open]) return;
        result = firstText(self->_db, "SELECT track_uri FROM plays WHERE LOWER(artist) = LOWER(?) AND track_uri IS NOT NULL AND track_uri <> '' LIMIT 1;", artist);
    });
    return result;
}

static int64_t scalar(sqlite3 *db, const char *sql) {
    int64_t value = 0;
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) == SQLITE_OK && stmt) {
        if (sqlite3_step(stmt) == SQLITE_ROW) value = sqlite3_column_int64(stmt, 0);
        sqlite3_finalize(stmt);
    }
    return value;
}

+ (NSInteger)restoreFromFileAtPath:(NSString *)path {
    sqlite3 *db = NULL;
    if (sqlite3_open_v2(path.UTF8String, &db, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK || !db) {
        if (db) sqlite3_close(db);
        return 0;
    }
    NSInteger added = 0;
    NSString *sql = [NSString stringWithFormat:@"SELECT %s FROM plays;", kPlayColumns];
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, sql.UTF8String, -1, &stmt, NULL) == SQLITE_OK && stmt) {
        NSMutableArray<SGStatsPlay *> *buffer = [NSMutableArray array];
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            [buffer addObject:playFromRow(stmt)];
            if (buffer.count >= 1000) {
                [SGStatsStore.shared addPlays:buffer];
                added += buffer.count;
                [buffer removeAllObjects];
            }
        }
        if (buffer.count) { [SGStatsStore.shared addPlays:buffer]; added += buffer.count; }
        sqlite3_finalize(stmt);
    }
    sqlite3_close(db);
    return added;
}

- (int64_t)earliestTs { __block int64_t v = 0; dispatch_sync(_queue, ^{ if (!self->_db && ![self open]) return; v = scalar(self->_db, "SELECT IFNULL(MIN(ts),0) FROM plays;"); }); return v; }
- (int64_t)latestTs { __block int64_t v = 0; dispatch_sync(_queue, ^{ if (!self->_db && ![self open]) return; v = scalar(self->_db, "SELECT IFNULL(MAX(ts),0) FROM plays;"); }); return v; }
- (int64_t)earliestTsSince:(int64_t)since {
    __block int64_t v = 0;
    dispatch_sync(_queue, ^{
        if (!self->_db && ![self open]) return;
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, "SELECT IFNULL(MIN(ts),0) FROM plays WHERE ts >= ?;", -1, &stmt, NULL) == SQLITE_OK && stmt) {
            sqlite3_bind_int64(stmt, 1, since);
            if (sqlite3_step(stmt) == SQLITE_ROW) v = sqlite3_column_int64(stmt, 0);
            sqlite3_finalize(stmt);
        }
    });
    return v;
}
- (int64_t)latestTsSince:(int64_t)since {
    __block int64_t v = 0;
    dispatch_sync(_queue, ^{
        if (!self->_db && ![self open]) return;
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, "SELECT IFNULL(MAX(ts),0) FROM plays WHERE ts >= ?;", -1, &stmt, NULL) == SQLITE_OK && stmt) {
            sqlite3_bind_int64(stmt, 1, since);
            if (sqlite3_step(stmt) == SQLITE_ROW) v = sqlite3_column_int64(stmt, 0);
            sqlite3_finalize(stmt);
        }
    });
    return v;
}

@end
