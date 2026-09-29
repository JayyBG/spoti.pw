#import <Foundation/Foundation.h>

// Reads a Spotify "Extended streaming history" .json (the account data export) into the store, in the
// same shape a live play is. Returns how many plays were added; an NSError explains a file that could
// not be read or was not that export.
@interface SGStatsImporter : NSObject
+ (NSInteger)importFileAtURL:(NSURL *)url error:(NSError **)error;
@end
