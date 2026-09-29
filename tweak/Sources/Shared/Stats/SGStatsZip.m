#import "SGStatsZip.h"
#import "Core/SGCore.h"
#import <zlib.h>

static uint16_t read16(const uint8_t *bytes, NSUInteger length, NSUInteger offset) {
    if (offset + 2 > length) return 0;
    return (uint16_t)(bytes[offset] | (bytes[offset + 1] << 8));
}

static uint32_t read32(const uint8_t *bytes, NSUInteger length, NSUInteger offset) {
    if (offset + 4 > length) return 0;
    return (uint32_t)(bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | ((uint32_t)bytes[offset + 3] << 24));
}

@implementation SGStatsZip

static NSData *inflateEntry(const uint8_t *bytes, NSUInteger length, NSUInteger offset, NSUInteger compressed, NSUInteger uncompressed, int method) {
    if (offset + compressed > length) return nil;
    if (method == 0) return [NSData dataWithBytes:bytes + offset length:compressed];
    if (method != 8 || uncompressed == 0) return nil;

    NSMutableData *output = [NSMutableData dataWithLength:uncompressed];
    z_stream stream = {0};
    if (inflateInit2(&stream, -15) != Z_OK) return nil;
    stream.next_in = (Bytef *)(bytes + offset);
    stream.avail_in = (uInt)compressed;
    stream.next_out = output.mutableBytes;
    stream.avail_out = (uInt)uncompressed;
    int result = inflate(&stream, Z_FINISH);
    inflateEnd(&stream);
    if (result != Z_STREAM_END || stream.total_out != uncompressed) return nil;
    return output;
}

+ (NSDictionary<NSString *, NSData *> *)JSONEntriesInData:(NSData *)data {
    if (data.length < 22) return @{};
    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;

    // End of central directory, scanning back over a possible comment.
    NSUInteger eocd = NSNotFound;
    NSUInteger lowest = length > 22 + 65535 ? length - 22 - 65535 : 0;
    for (NSUInteger i = length - 22; i + 1 > lowest; i--) {
        if (read32(bytes, length, i) == 0x06054b50) { eocd = i; break; }
        if (i == 0) break;
    }
    if (eocd == NSNotFound) return @{};

    NSUInteger count = read16(bytes, length, eocd + 10);
    NSUInteger offset = read32(bytes, length, eocd + 16);

    NSMutableDictionary<NSString *, NSData *> *entries = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < count; i++) {
        if (read32(bytes, length, offset) != 0x02014b50) break;
        int method = read16(bytes, length, offset + 10);
        NSUInteger compressed = read32(bytes, length, offset + 20);
        NSUInteger uncompressed = read32(bytes, length, offset + 24);
        NSUInteger nameLength = read16(bytes, length, offset + 28);
        NSUInteger extraLength = read16(bytes, length, offset + 30);
        NSUInteger commentLength = read16(bytes, length, offset + 32);
        NSUInteger localOffset = read32(bytes, length, offset + 42);
        if (offset + 46 + nameLength > length) break;
        NSString *name = [[NSString alloc] initWithBytes:bytes + offset + 46 length:nameLength encoding:NSUTF8StringEncoding];

        NSUInteger next = offset + 46 + nameLength + extraLength + commentLength;
        offset = next;

        if (![name.pathExtension.lowercaseString isEqualToString:@"json"]) continue;
        if (compressed == 0xffffffffu || uncompressed == 0xffffffffu) continue;
        if (read32(bytes, length, localOffset) != 0x04034b50) continue;
        NSUInteger localName = read16(bytes, length, localOffset + 26);
        NSUInteger localExtra = read16(bytes, length, localOffset + 28);
        NSUInteger start = localOffset + 30 + localName + localExtra;
        NSData *entry = inflateEntry(bytes, length, start, compressed, uncompressed, method);
        if (entry) entries[name] = entry;
    }
    return entries;
}

@end
