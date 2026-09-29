#import "SGStatsRecorder.h"
#import "Stats.h"
#import "SGStatsStore.h"
#import "Core/SGCore.h"
#import "Shared/Player/PlayerState.h"
#import "Headers/SPTPlayer.h"

// A play is kept at Spotify's own bar for one: 30 seconds of a track count.
static const int64_t kMinMs = 30000;

@interface SGStatsRecorder () <SGPlayerStateObserver>
@end

void SGStatsStart(void) {
    if (!SGFlag(SGKeyStats, NO)) return;
    [SGStatsRecorder.shared start];
}

@implementation SGStatsRecorder {
    NSString *_key, *_title, *_artist, *_artistURI, *_album, *_albumURI, *_artwork;
    int64_t _startedAt, _accumulatedMs, _durationMs;
    NSTimeInterval _lastTick;
    BOOL _playing;
}

+ (instancetype)shared {
    static SGStatsRecorder *recorder;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ recorder = [SGStatsRecorder new]; });
    return recorder;
}

- (void)start {
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(terminate) name:UIApplicationWillTerminateNotification object:nil];
    SGAddPlayerStateObserver(self);
    _lastTick = NSDate.date.timeIntervalSince1970;
    SPTPlayerState *state = SGPlayerState();
    if (state) [self apply:state];
}

- (void)terminate {
    [self tick];
    [self flush];
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    [self apply:state];
}

// Add the wall-clock time since the last event while the player was running.
- (void)tick {
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (_playing && _key) _accumulatedMs += (int64_t)((now - _lastTick) * 1000.0);
    _lastTick = now;
}

- (void)apply:(SPTPlayerState *)state {
    NSString *uri = SGURIString(state.track.URI);
    [self tick];
    if (!uri.length) {
        [self flush];
        return;
    }
    if (![uri isEqualToString:_key]) {
        [self flush];
        _key = uri;
        _startedAt = (int64_t)NSDate.date.timeIntervalSince1970;
        _accumulatedMs = 0;
        _durationMs = state.duration > 0 ? (int64_t)(state.duration * 1000.0) : 0;
        SPTPlayerTrack *track = state.track;
        NSDictionary *metadata = track.metadata;
        _title = track.trackTitle;
        _artist = track.artistName;
        _artistURI = SGURIString(track.artistURI);
        _album = metadata[@"album_name"] ?: metadata[@"album_title"];
        _albumURI = metadata[@"album_uri"];
        _artwork = metadata[@"image_xlarge_url"] ?: metadata[@"image_large_url"] ?: metadata[@"image_url"] ?: metadata[@"image_small_url"];
    }
    _playing = state.isPlaying && !state.isPaused;
}

// Store what was heard of the track that just ended, if it was heard enough of.
- (void)flush {
    if (!_key) return;
    int64_t ms = _accumulatedMs;
    if (_durationMs > 0 && ms > _durationMs) ms = _durationMs;
    if (ms >= kMinMs) {
        SGStatsPlay *play = [SGStatsPlay new];
        play.ts = _startedAt;
        play.trackURI = _key;
        play.title = _title;
        play.artist = _artist;
        play.artistURI = _artistURI;
        play.album = _album;
        play.albumURI = _albumURI;
        play.artwork = _artwork;
        play.ms = ms;
        play.source = SGStatsSourceLive;
        [SGStatsStore.shared addPlay:play];
    }
    _key = nil;
    _accumulatedMs = 0;
    _durationMs = 0;
    _playing = NO;
}

@end
