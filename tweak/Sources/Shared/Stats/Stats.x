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
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        SGStatsWriteWidgetSummary();
    }];
    // Late enough that the app and the notification centre are up.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SGStatsScheduleRecap();
        SGStatsWriteWidgetSummary();
    });
}
