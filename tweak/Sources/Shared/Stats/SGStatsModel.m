#import "SGStatsModel.h"

NSString *SGStatsRangeName(SGStatsRange range) {
    switch (range) {
        case SGStatsRangeDay: return @"24 hours";
        case SGStatsRangeWeek: return @"This week";
        case SGStatsRange4Weeks: return @"4 weeks";
        case SGStatsRange6Months: return @"6 months";
        case SGStatsRangeYear: return @"This year";
        case SGStatsRangeLifetime: return @"Lifetime";
    }
    return @"";
}

NSString *SGStatsEntityName(SGStatsEntity entity) {
    switch (entity) {
        case SGStatsEntityTrack: return @"Tracks";
        case SGStatsEntityAlbum: return @"Albums";
        case SGStatsEntityArtist: return @"Artists";
    }
    return @"";
}

NSString *SGStatsOrderName(SGStatsOrder order) {
    switch (order) {
        case SGStatsOrderPlays: return @"Plays";
        case SGStatsOrderMinutes: return @"Minutes";
        case SGStatsOrderDays: return @"Days";
    }
    return @"";
}

static int64_t unixOf(NSDate *date) {
    return (int64_t)date.timeIntervalSince1970;
}

int64_t SGStatsRangeSince(SGStatsRange range) {
    NSInteger days = 0;
    switch (range) {
        case SGStatsRangeDay: days = 1; break;
        case SGStatsRange4Weeks: days = 28; break;
        case SGStatsRange6Months: days = 182; break;
        case SGStatsRangeWeek:
        case SGStatsRangeYear: {
            NSCalendar *calendar = NSCalendar.currentCalendar;
            NSCalendarUnit unit = range == SGStatsRangeWeek ? NSCalendarUnitWeekOfYear : NSCalendarUnitYear;
            NSDate *start = nil;
            if ([calendar rangeOfUnit:unit startDate:&start interval:NULL forDate:NSDate.date] && start) return unixOf(start);
            days = range == SGStatsRangeWeek ? 7 : 365;
            break;
        }
        case SGStatsRangeLifetime: return 0;
    }
    return unixOf([NSDate.date dateByAddingTimeInterval:-days * 86400.0]);
}

@implementation SGStatsEntry
@end

@implementation SGStatsSummary
@end

@implementation SGStatsDay
@end
