#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SGStatsEntity) { SGStatsEntityTrack, SGStatsEntityAlbum, SGStatsEntityArtist };
typedef NS_ENUM(NSInteger, SGStatsOrder) { SGStatsOrderPlays, SGStatsOrderMinutes, SGStatsOrderDays };
typedef NS_ENUM(NSInteger, SGStatsRange) {
    SGStatsRangeDay, SGStatsRangeWeek, SGStatsRange4Weeks, SGStatsRange6Months, SGStatsRangeYear, SGStatsRangeLifetime
};
// On repeat: most played in the range. New: first heard in the range. Forgotten: played a lot before
// the range and not since.
typedef NS_ENUM(NSInteger, SGStatsDiscover) { SGStatsDiscoverOnRepeat, SGStatsDiscoverNew, SGStatsDiscoverForgotten };
// The stored attribute a breakdown page splits the plays by.
typedef NS_ENUM(NSInteger, SGStatsBreakdown) { SGStatsBreakdownPlatform, SGStatsBreakdownShuffle, SGStatsBreakdownOffline };

NSString *SGStatsRangeName(SGStatsRange range);
NSString *SGStatsEntityName(SGStatsEntity entity);
NSString *SGStatsOrderName(SGStatsOrder order);
// Unix seconds the range starts at, 0 for lifetime. The end of the range is now.
int64_t SGStatsRangeSince(SGStatsRange range);

@interface SGStatsEntry : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *uri;
@property (nonatomic, copy) NSString *artwork;
@property (nonatomic) NSInteger plays;
@property (nonatomic) NSInteger skips;
@property (nonatomic) int64_t ms;
@property (nonatomic) int64_t first, last;   // unix seconds, for the detail page
@end

@interface SGStatsSummary : NSObject
@property (nonatomic) int64_t ms;
@property (nonatomic) NSInteger plays, tracks, albums, artists;
@end

@interface SGStatsDay : NSObject
@property (nonatomic) int64_t day;   // unix seconds at local midnight
@property (nonatomic) int64_t ms;
@end
