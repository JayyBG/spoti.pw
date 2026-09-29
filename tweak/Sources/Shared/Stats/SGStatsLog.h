#import <Foundation/Foundation.h>

// The Stats import's own log, appended to a file in the app's Documents. The unified log is gone
// with the process when an import is killed, so this one survives and the Import log row reads it.
void SGStatsLogLine(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
NSString *SGStatsLogTail(NSUInteger maxLines);
void SGStatsLogClear(void);
