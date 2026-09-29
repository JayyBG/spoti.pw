#import <UIKit/UIKit.h>
#import "SGStatsModel.h"

// Artwork for a stats row. A track's picture is the album cover, so an album gets the picture of any
// track on it, and an artist gets theirs through a track's embed page, which carries the artist URI
// the import never has; the public oEmbed endpoint answers with the picture for a URI of any kind.
// What is found is remembered, so a row is fetched once.
@interface SGStatsArtwork : NSObject
+ (void)fill:(UIImageView *)view entry:(SGStatsEntry *)entry kind:(SGStatsEntity)kind;
@end
