#import "SGStatsImport.h"
#import "SGStatsStore.h"
#import "SGStatsZip.h"
#import "SGStatsLog.h"

@implementation SGStatsImporter

static NSDate *dateFromExtended(NSString *ts) {
    static NSISO8601DateFormatter *plain, *fractional;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        plain = [NSISO8601DateFormatter new];
        plain.formatOptions = NSISO8601DateFormatWithInternetDateTime;
        fractional = [NSISO8601DateFormatter new];
        fractional.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    });
    return [plain dateFromString:ts] ?: [fractional dateFromString:ts];
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

// Every field of Spotify's entries may be null, which arrives as NSNull and answers nothing, so each
// is asked what it is before it is asked anything about itself.
static SGStatsPlay *playFromEntry(NSDictionary *entry) {
    BOOL extended = [entry[@"master_metadata_track_name"] isKindOfClass:NSString.class];
    NSString *title, *artist = nil, *album = nil, *uri = nil;
    NSDate *date;
    NSNumber *ms;
    if (extended) {
        title = entry[@"master_metadata_track_name"];
        artist = [entry[@"master_metadata_album_artist_name"] isKindOfClass:NSString.class] ? entry[@"master_metadata_album_artist_name"] : nil;
        album = [entry[@"master_metadata_album_album_name"] isKindOfClass:NSString.class] ? entry[@"master_metadata_album_album_name"] : nil;
        uri = [entry[@"spotify_track_uri"] isKindOfClass:NSString.class] ? entry[@"spotify_track_uri"] : nil;
        date = dateFromExtended(entry[@"ts"]);
        ms = [entry[@"ms_played"] isKindOfClass:NSNumber.class] ? entry[@"ms_played"] : nil;
    } else {
        // The older, shorter export: {endTime, artistName, trackName, msPlayed}.
        title = [entry[@"trackName"] isKindOfClass:NSString.class] ? entry[@"trackName"] : nil;
        artist = [entry[@"artistName"] isKindOfClass:NSString.class] ? entry[@"artistName"] : nil;
        date = dateFromLegacy(entry[@"endTime"]);
        ms = [entry[@"msPlayed"] isKindOfClass:NSNumber.class] ? entry[@"msPlayed"] : nil;
    }
    if (!title.length || !date || !ms) return nil;

    SGStatsPlay *play = [SGStatsPlay new];
    play.ts = (int64_t)date.timeIntervalSince1970;
    play.trackURI = uri;
    play.title = title;
    play.artist = artist;
    play.album = album;
    play.ms = ms.longLongValue;
    play.source = SGStatsSourceImport;
    if (extended) {
        play.skipped = [entry[@"skipped"] isKindOfClass:NSNumber.class] && [entry[@"skipped"] boolValue];
        play.offline = [entry[@"offline"] isKindOfClass:NSNumber.class] && [entry[@"offline"] boolValue];
        play.shuffled = [entry[@"shuffle"] isKindOfClass:NSNumber.class] && [entry[@"shuffle"] boolValue];
        play.reasonEnd = [entry[@"reason_end"] isKindOfClass:NSString.class] ? entry[@"reason_end"] : nil;
        play.platform = [entry[@"platform"] isKindOfClass:NSString.class] ? entry[@"platform"] : nil;
    }
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
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
    if (!data) {
        SGStatsLogLine(@"read failed: %@ (%@)", url.lastPathComponent, error ? *error : nil);
        return 0;
    }
    SGStatsLogLine(@"read %@ (%.1f MB)", url.lastPathComponent, data.length / 1048576.0);

    if ([url.pathExtension.lowercaseString isEqualToString:@"zip"]) {
        __block NSInteger added = 0, files = 0;
        [SGStatsZip enumerateJSONEntriesInData:data using:^(NSString *name, NSData *json) {
            // Only the streaming-history files carry plays; the export is full of other JSON.
            if (![name.lowercaseString containsString:@"streaming"]) return;
            @try {
                NSInteger count = [self addPlaysFromData:json];
                SGStatsLogLine(@"%@: %ld plays", name.lastPathComponent, (long)count);
                if (count > 0) { added += count; files++; }
            } @catch (NSException *exception) {
                SGStatsLogLine(@"EXCEPTION on %@: %@", name.lastPathComponent, exception.reason);
            }
        }];
        SGStatsStore *store = SGStatsStore.shared;
        SGStatsLogLine(@"import done: %ld plays from %ld files; now %ld plays, %lld..%lld",
                       (long)added, (long)files, (long)store.playCount, store.earliestTs, store.latestTs);
        if (added == 0) {
            if (error) *error = [NSError errorWithDomain:@"spotifyglass.stats" code:2 userInfo:@{NSLocalizedDescriptionKey: @"No plays found in that ZIP."}];
        }
        return added;
    }

    NSInteger added = 0;
    @try {
        added = [self addPlaysFromData:data];
    } @catch (NSException *exception) {
        SGStatsLogLine(@"EXCEPTION on %@: %@", url.lastPathComponent, exception.reason);
    }
    if (added < 0) {
        SGStatsLogLine(@"not an array: %@", url.lastPathComponent);
        if (error) *error = [NSError errorWithDomain:@"spotifyglass.stats" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Not a Spotify streaming-history export."}];
        return 0;
    }
    SGStatsLogLine(@"import done: %ld plays from %@", (long)added, url.lastPathComponent);
    return added;
}

@end
