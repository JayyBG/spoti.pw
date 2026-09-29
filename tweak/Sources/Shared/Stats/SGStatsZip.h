#import <Foundation/Foundation.h>

// Walks the .json entries of a ZIP, one at a time: Spotify's data export arrives as a ZIP of JSON
// files and the picker hands the archive itself. Only stored and deflated entries are read, which is
// all the export uses. `block` is called with each entry's data and the entry is released after, so a
// multi-file export never sits in memory whole.
@interface SGStatsZip : NSObject
+ (void)enumerateJSONEntriesInData:(NSData *)data using:(void (^)(NSData *json))block;
@end
