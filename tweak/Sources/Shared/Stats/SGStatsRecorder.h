#import <Foundation/Foundation.h>

// The one player-state observer that turns what Spotify plays into rows in the Stats store. Retained
// for the process's life and registered by SGStatsStart.
@interface SGStatsRecorder : NSObject
+ (instancetype)shared;
- (void)start;
@end
