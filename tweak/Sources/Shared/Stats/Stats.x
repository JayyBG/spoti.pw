#import "Core/SGCore.h"
#import "Stats.h"
#import "SGStatsLog.h"

// An exception anywhere in the process is written to the Stats log before the process dies, so a
// crash in an import leaves a reason behind.
static void SGStatsException(NSException *exception) {
    SGStatsLogLine(@"UNCAUGHT %@: %@\n%@", exception.name, exception.reason, [exception.callStackSymbols componentsJoinedByString:@"\n"]);
}

%ctor {
    %init;
    NSSetUncaughtExceptionHandler(&SGStatsException);
    SGStatsStart();
}
