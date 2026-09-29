#import "SGStatsImport.h"
#import "SGStatsStore.h"
#import "SGStatsZip.h"
#import "Core/SGCore.h"

@implementation SGStatsImporter

static NSDate *dateFromExtended(NSString *ts) {
    static NSISO8601DateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [NSISO8601DateFormatter new];
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    });
    return [formatter dateFromString:ts];
}

static NSDate *dateFromLegacy(NSString *endTime) {
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm";
    });
    return [formatter dateFromString:endTime];
}

// -1 when the data is not one of the export's arrays of plays, else the count added.
+ (NSInteger)addPlaysFromData:(NSData *)data {
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![root isKindOfClass:NSArray.class]) return -1;

    NSMutableArray<SGStatsPlay *> *plays = [NSMutableArray array];
    for (id item in (NSArray *)root) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *entry = item;
        NSString *title = entry[@"master_metadata_track_name"];
        NSString *artist = entry[@"master_metadata_album_artist_name"];
        NSString *album = entry[@"master_metadata_album_album_name"];
        NSString *uri = entry[@"spotify_track_uri"];
        NSDate *date = dateFromExtended(entry[@"ts"]);
        NSNumber *ms = entry[@"ms_played"];
        if (!title.length) {
            // The older, shorter export: {endTime, artistName, trackName, msPlayed}.
            title = entry[@"trackName"];
            artist = entry[@"artistName"];
            date = dateFromLegacy(entry[@"endTime"]);
            ms = entry[@"msPlayed"];
            uri = nil;
        }
        if (!title.length || !date || !ms) continue;

        SGStatsPlay *play = [SGStatsPlay new];
        play.ts = (int64_t)date.timeIntervalSince1970;
        play.trackURI = uri;
        play.title = title;
        play.artist = artist;
        play.album = album;
        play.ms = ms.longLongValue;
        play.source = SGStatsSourceImport;
        [plays addObject:play];
    }

    [SGStatsStore.shared addPlays:plays];
    return plays.count;
}

+ (NSInteger)importFileAtURL:(NSURL *)url error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:error];
    if (!data) {
        SGLog(@"[stats] import: could not read %@", url.lastPathComponent);
        return 0;
    }
    SGLog(@"[stats] import: read %@ (%.1f MB)", url.lastPathComponent, data.length / 1048576.0);

    // The export is a ZIP; the picker may also be handed one of its JSON files directly.
    if ([url.pathExtension.lowercaseString isEqualToString:@"zip"]) {
        __block NSInteger added = 0;
        __block NSInteger files = 0;
        [SGStatsZip enumerateJSONEntriesInData:data using:^(NSData *json) {
            NSInteger count = [self addPlaysFromData:json];
            if (count > 0) { added += count; files++; }
        }];
        if (added == 0 && error) *error = [NSError errorWithDomain:@"spotifyglass.stats" code:2 userInfo:@{NSLocalizedDescriptionKey: @"No plays found in that ZIP."}];
        SGLog(@"[stats] import: %ld plays from %ld files", (long)added, (long)files);
        return added;
    }

    NSInteger added = [self addPlaysFromData:data];
    if (added < 0) {
        if (error) *error = [NSError errorWithDomain:@"spotifyglass.stats" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Not a Spotify streaming-history export."}];
        return 0;
    }
    SGLog(@"[stats] import: %ld plays from %@", (long)added, url.lastPathComponent);
    return added;
}

@end
