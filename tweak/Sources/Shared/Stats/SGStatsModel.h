#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SGStatsEntity) { SGStatsEntityTrack, SGStatsEntityAlbum, SGStatsEntityArtist };
typedef NS_ENUM(NSInteger, SGStatsOrder) { SGStatsOrderPlays, SGStatsOrderMinutes };
typedef NS_ENUM(NSInteger, SGStatsRange) {
    SGStatsRangeDay, SGStatsRangeWeek, SGStatsRange4Weeks, SGStatsRange6Months, SGStatsRangeYear, SGStatsRangeLifetime
};

NSString *SGStatsRangeName(SGStatsRange range);
NSString *SGStatsEntityName(SGStatsEntity entity);
// Unix seconds the range starts at, 0 for lifetime.
int64_t SGStatsRangeSince(SGStatsRange range);

@interface SGStatsEntry : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *uri;
@property (nonatomic, copy) NSString *artwork;
@property (nonatomic) NSInteger plays;
@property (nonatomic) int64_t ms;
@end

@interface SGStatsSummary : NSObject
@property (nonatomic) int64_t ms;
@property (nonatomic) NSInteger plays, tracks, albums, artists;
@end

@interface SGStatsDay : NSObject
@property (nonatomic) int64_t day;   // unix seconds at local midnight
@property (nonatomic) int64_t ms;
@end
