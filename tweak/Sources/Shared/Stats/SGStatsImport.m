#import "SGStatsImport.h"
#import "SGStatsStore.h"
#import "SGStatsZip.h"
#import "SGStatsLog.h"

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

static SGStatsPlay *playFromEntry(NSDictionary *entry) {
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
    if (![title isKindOfClass:NSString.class] || !title.length || !date || ![ms isKindOfClass:NSNumber.class]) return nil;

    SGStatsPlay *play = [SGStatsPlay new];
    play.ts = (int64_t)date.timeIntervalSince1970;
    play.trackURI = [uri isKindOfClass:NSString.class] ? uri : nil;
    play.title = title;
    play.artist = [artist isKindOfClass:NSString.class] ? artist : nil;
    play.album = [album isKindOfClass:NSString.class] ? album : nil;
    play.ms = ms.longLongValue;
    play.source = SGStatsSourceImport;
    return play;
}

// Spotify's files are one big JSON array and NSJSONSerialization would turn a 30 MB file into
// hundreds of MB of objects at once. The array's own top-level objects are cut out and parsed one by
// one instead, so only a single play is ever in memory. Answers NO when the data is not an array.
static BOOL enumerateArrayEntries(NSData *data, void (^block)(NSDictionary *entry)) {
    if (data.length < 2) return NO;
    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;
    NSUInteger i = 0;
    while (i < length && bytes[i] != '[') i++;
    if (i >= length) return NO;
    i++;

    while (i < length) {
        while (i < length && (bytes[i] == ' ' || bytes[i] == '\t' || bytes[i] == '\n' || bytes[i] == '\r' || bytes[i] == ',')) i++;
        if (i >= length || bytes[i] == ']') break;
        if (bytes[i] != '{') { i++; continue; }

        NSUInteger start = i;
        NSInteger depth = 0;
        BOOL inString = NO, escaped = NO;
        for (; i < length; i++) {
            uint8_t c = bytes[i];
            if (inString) {
                if (escaped) escaped = NO;
                else if (c == '\\') escaped = YES;
                else if (c == '"') inString = NO;
                continue;
            }
            if (c == '"') inString = YES;
            else if (c == '{') depth++;
            else if (c == '}') { if (--depth == 0) { i++; break; } }
        }
        @autoreleasepool {
            NSData *object = [data subdataWithRange:NSMakeRange(start, i - start)];
            NSDictionary *entry = [NSJSONSerialization JSONObjectWithData:object options:0 error:NULL];
            if ([entry isKindOfClass:NSDictionary.class]) block(entry);
        }
    }
    return YES;
}

// -1 when the data is not one of the export's arrays of plays, else the count added.
+ (NSInteger)addPlaysFromData:(NSData *)data {
    NSMutableArray<SGStatsPlay *> *buffer = [NSMutableArray array];
    __block NSInteger added = 0;
    BOOL isArray = enumerateArrayEntries(data, ^(NSDictionary *entry) {
        SGStatsPlay *play = playFromEntry(entry);
        if (!play) return;
        [buffer addObject:play];
        if (buffer.count >= 1000) {
            [SGStatsStore.shared addPlays:buffer];
            added += buffer.count;
            [buffer removeAllObjects];
        }
    });
    if (!isArray) return -1;
    if (buffer.count) { [SGStatsStore.shared addPlays:buffer]; added += buffer.count; }
    return added;
}

+ (NSInteger)importFileAtURL:(NSURL *)url error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:error];
    if (!data) {
        SGStatsLogLine(@"read failed: %@ (%@)", url.lastPathComponent, error ? *error : nil);
        return 0;
    }
    SGStatsLogLine(@"read %@ (%.1f MB)", url.lastPathComponent, data.length / 1048576.0);

    if ([url.pathExtension.lowercaseString isEqualToString:@"zip"]) {
        __block NSInteger added = 0, files = 0;
        [SGStatsZip enumerateJSONEntriesInData:data using:^(NSData *json) {
            NSInteger count = [self addPlaysFromData:json];
            if (count > 0) { added += count; files++; SGStatsLogLine(@"+%ld plays (%ld files so far)", (long)count, (long)files); }
        }];
        SGStatsLogLine(@"import done: %ld plays from %ld files", (long)added, (long)files);
        if (added == 0) {
            if (error) *error = [NSError errorWithDomain:@"spotifyglass.stats" code:2 userInfo:@{NSLocalizedDescriptionKey: @"No plays found in that ZIP."}];
        }
        return added;
    }

    NSInteger added = [self addPlaysFromData:data];
    if (added < 0) {
        SGStatsLogLine(@"not an array: %@", url.lastPathComponent);
        if (error) *error = [NSError errorWithDomain:@"spotifyglass.stats" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Not a Spotify streaming-history export."}];
        return 0;
    }
    SGStatsLogLine(@"import done: %ld plays from %@", (long)added, url.lastPathComponent);
    return added;
}

@end
