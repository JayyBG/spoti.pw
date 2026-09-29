#import <Foundation/Foundation.h>
#import "SGStatsModel.h"

typedef NS_ENUM(NSInteger, SGStatsSource) { SGStatsSourceLive = 0, SGStatsSourceImport = 1 };

@interface SGStatsPlay : NSObject
@property (nonatomic) int64_t ts;    // unix seconds the play started
@property (nonatomic, copy) NSString *trackURI, *title, *artistURI, *artist, *albumURI, *album, *artwork;
@property (nonatomic) int64_t ms;
@property (nonatomic) NSInteger source;
@end

// One SQLite file of plays in the app's Documents, on a serial queue. Reads are synchronous.
@interface SGStatsStore : NSObject
+ (instancetype)shared;
- (void)addPlay:(SGStatsPlay *)play;
- (void)addPlays:(NSArray<SGStatsPlay *> *)plays;
- (void)eraseAll;
- (BOOL)hasLivePlays;
@property (nonatomic, readonly) NSInteger playCount;
- (NSArray<SGStatsEntry *> *)top:(SGStatsEntity)entity order:(SGStatsOrder)order since:(int64_t)since limit:(NSInteger)limit;
- (SGStatsSummary *)summarySince:(int64_t)since;
- (NSArray<SGStatsDay *> *)dailySince:(int64_t)since;
@end
