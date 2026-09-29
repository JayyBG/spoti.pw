#import <Foundation/Foundation.h>
#import "SGStatsModel.h"

typedef NS_ENUM(NSInteger, SGStatsSource) { SGStatsSourceLive = 0, SGStatsSourceImport = 1 };

@interface SGStatsPlay : NSObject
@property (nonatomic) int64_t ts;    // unix seconds the play started
@property (nonatomic, copy) NSString *trackURI, *title, *artistURI, *artist, *albumURI, *album, *artwork;
@property (nonatomic, copy) NSString *reasonEnd, *platform, *contextURI;
@property (nonatomic) int64_t ms;
@property (nonatomic) NSInteger source;
@property (nonatomic) BOOL skipped, offline, shuffled;
@end

// One SQLite file of plays in the app's Documents, on a serial queue. Reads are synchronous.
@interface SGStatsStore : NSObject
+ (instancetype)shared;
- (void)addPlay:(SGStatsPlay *)play;
- (void)addPlays:(NSArray<SGStatsPlay *> *)plays;
- (void)eraseAll;
- (BOOL)hasLivePlays;
@property (nonatomic, readonly) NSInteger playCount;
// The SQLite file itself, for a backup, and folding the WAL into it first so the copy is complete.
- (NSString *)filePath;
- (void)checkpoint;
// Reads every play of another store's file (a backup) into this one. Answers how many were added.
+ (NSInteger)restoreFromFileAtPath:(NSString *)path;

// top: an entity's rows in [since, until), grouped the way the page groups them. `until` 0 is now.
- (NSArray<SGStatsEntry *> *)top:(SGStatsEntity)entity order:(SGStatsOrder)order since:(int64_t)since until:(int64_t)until limit:(NSInteger)limit;
- (SGStatsSummary *)summarySince:(int64_t)since;
- (NSArray<SGStatsDay *> *)dailySince:(int64_t)since;
- (NSArray<SGStatsEntry *> *)discover:(SGStatsDiscover)kind entity:(SGStatsEntity)entity since:(int64_t)since until:(int64_t)until limit:(NSInteger)limit;
// Per calendar year, newest first: name is the year, with its plays and milliseconds.
- (NSArray<SGStatsEntry *> *)years;
// The plays split by platform, shuffle or offline, largest first: name is the label.
- (NSArray<SGStatsEntry *> *)breakdown:(SGStatsBreakdown)kind since:(int64_t)since;

// Unix seconds of the earliest and latest play, 0 when there are none.
- (int64_t)earliestTs;
- (int64_t)latestTs;
- (int64_t)earliestTsSince:(int64_t)since;
- (int64_t)latestTsSince:(int64_t)since;
// 168 cells, weekday (0 = Sunday) * 24 + hour, of milliseconds heard.
- (NSArray<NSNumber *> *)clockSince:(int64_t)since;
- (NSArray<SGStatsPlay *> *)recentLimit:(NSInteger)limit;
- (NSArray<SGStatsPlay *> *)allPlays;

// Any track URI of an album or artist, for artwork an imported play has no URI for. The album is
// taken with its artist: without it a common album name matches another artist's album of the same
// name and the wrong cover.
- (NSString *)anyTrackURIForAlbum:(NSString *)album artist:(NSString *)artist;
- (NSString *)anyTrackURIForArtist:(NSString *)artist;
@end
