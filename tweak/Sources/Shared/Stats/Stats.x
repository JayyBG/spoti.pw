#import "Core/SGCore.h"
#import "Stats.h"

%ctor {
    %init;
    SGStatsStart();
}
