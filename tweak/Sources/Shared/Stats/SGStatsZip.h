#import <Foundation/Foundation.h>

// The .json entries of a ZIP, unpacked in memory: Spotify's data export arrives as a ZIP of JSON
// files and the picker hands the archive itself. Only stored and deflated entries are read, which is
// all the export uses.
@interface SGStatsZip : NSObject
+ (NSDictionary<NSString *, NSData *> *)JSONEntriesInData:(NSData *)data;
@end
