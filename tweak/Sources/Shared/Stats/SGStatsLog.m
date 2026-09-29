#import "SGStatsLog.h"

static NSString *logPath(void) {
    NSString *documents = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    return [documents stringByAppendingPathComponent:@"SGStats.log"];
}

void SGStatsLogLine(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"HH:mm:ss";
    NSString *line = [NSString stringWithFormat:@"%@  %@\n", [formatter stringFromDate:NSDate.date], message];

    // Appending to the end of a file that the picker's queue keeps open; a lock keeps two import
    // threads from interleaving the writes.
    static NSLock *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSLock new]; });
    [lock lock];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:logPath()];
    if (handle) {
        [handle seekToEndOfFile];
        [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    } else {
        [line writeToFile:logPath() atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }
    [lock unlock];
}

NSString *SGStatsLogTail(NSUInteger maxLines) {
    NSString *text = [NSString stringWithContentsOfFile:logPath() encoding:NSUTF8StringEncoding error:NULL];
    if (!text.length) return @"Nothing logged yet.";
    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    if (lines.count > maxLines) lines = [lines subarrayWithRange:NSMakeRange(lines.count - maxLines, maxLines)];
    return [lines componentsJoinedByString:@"\n"];
}

void SGStatsLogClear(void) {
    [NSFileManager.defaultManager removeItemAtPath:logPath() error:NULL];
}
