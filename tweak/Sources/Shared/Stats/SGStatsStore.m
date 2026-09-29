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
        " ms INTEGER NOT NULL, source INTEGER NOT NULL DEFAULT 0);"
        "CREATE INDEX IF NOT EXISTS plays_ts ON plays(ts);"
        "CREATE INDEX IF NOT EXISTS plays_track ON plays(track_uri);", NULL, NULL, NULL);
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
            "INSERT INTO plays (ts, track_uri, title, artist_uri, artist, album_uri, album, artwork, ms, source)"
            " VALUES (?,?,?,?,?,?,?,?,?,?);", -1, &stmt, NULL);
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

static NSString *entityKey(SGStatsEntity entity) {
    switch (entity) {
        case SGStatsEntityTrack: return @"COALESCE(track_uri, 'n:' || IFNULL(title,'') || '|' || IFNULL(artist,''))";
        case SGStatsEntityAlbum: return @"COALESCE(album_uri, 'a:' || IFNULL(album,'') || '|' || IFNULL(artist,''))";
        case SGStatsEntityArtist: return @"COALESCE(artist_uri, 'r:' || IFNULL(artist,''))";
    }
    return nil;
}

- (NSArray<SGStatsEntry *> *)top:(SGStatsEntity)entity order:(SGStatsOrder)order since:(int64_t)since limit:(NSInteger)limit {
    NSMutableArray<SGStatsEntry *> *entries = [NSMutableArray array];
    NSString *name = entity == SGStatsEntityAlbum ? @"MAX(album)" : (entity == SGStatsEntityArtist ? @"MAX(artist)" : @"MAX(title)");
    NSString *subtitle = entity == SGStatsEntityArtist ? @"NULL" : @"MAX(artist)";
    NSString *uri = entity == SGStatsEntityAlbum ? @"MAX(album_uri)" : (entity == SGStatsEntityArtist ? @"MAX(artist_uri)" : @"MAX(track_uri)");
    NSString *artwork = entity == SGStatsEntityArtist ? @"NULL" : @"MAX(artwork)";
    NSString *orderBy = order == SGStatsOrderMinutes ? @"total DESC" : @"plays DESC";
    NSString *sql = [NSString stringWithFormat:
        @"SELECT %@ AS name, %@ AS subtitle, %@ AS uri, %@ AS artwork, COUNT(*) AS plays, SUM(ms) AS total"
         " FROM plays WHERE ts >= ? GROUP BY %@ HAVING name IS NOT NULL AND name <> '' ORDER BY %@, name LIMIT ?;",
        name, subtitle, uri, artwork, entityKey(entity), orderBy];
    dispatch_sync(_queue, ^{
        if (!self->_db && ![self open]) return;
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql.UTF8String, -1, &stmt, NULL) != SQLITE_OK) return;
        sqlite3_bind_int64(stmt, 1, since);
        sqlite3_bind_int(stmt, 2, (int)limit);
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
            entry.ms = sqlite3_column_int64(stmt, 5);
            [entries addObject:entry];
        }
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

@end
