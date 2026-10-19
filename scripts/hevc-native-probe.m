// Offline fixtures only; personal excerpts require explicit authorization.
// No application, queue, preferences, or user caches.
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <MP42Foundation/MP42Foundation.h>

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 3) { NSLog(@"usage: probe inspect input | mux input output true|false"); return 2; }
        NSURL *source = [NSURL fileURLWithPath:@(argv[2])];
        NSError *error = nil;
        if (strcmp(argv[1], "mux") == 0) {
            if (argc != 5) return 2;
            NSURL *output = [NSURL fileURLWithPath:@(argv[3])];
            if ([source isEqual:output] || [[NSFileManager defaultManager] fileExistsAtPath:output.path]) return 2;
            MP42FileImporter *importer = [[MP42FileImporter alloc] initWithURL:source error:&error];
            if (!importer) { NSLog(@"%@", error); return 1; }
            MP42File *file = [[MP42File alloc] init];
            for (MP42Track *track in importer.tracks) [file addTrack:track];
            NSDictionary *options = strcmp(argv[4], "true") == 0 ? @{MP42ForceHvc1: @YES} : @{};
            if (![file writeToUrl:output options:options error:&error]) { NSLog(@"%@", error); return 1; }
            NSLog(@"MUX complete");
            return 0;
        }
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:source options:nil];
        NSArray<AVAssetTrack *> *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
        NSLog(@"videoTracks=%lu playable=%d", (unsigned long)tracks.count, asset.playable);
        for (AVAssetTrack *track in tracks) {
            NSLog(@"enabled=%d formats=%@", track.enabled, track.formatDescriptions);
            AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:asset error:&error];
            BOOL all = argc == 4 && strcmp(argv[3], "all") == 0;
            BOOL seek = argc == 4 && strcmp(argv[3], "seek") == 0;
            if (seek) reader.timeRange = CMTimeRangeMake(CMTimeMake(1, 1), CMTimeMake(1, 1));
            BOOL compressed = argc == 4 && strcmp(argv[3], "compressed") == 0;
            AVAssetReaderTrackOutput *output = [[AVAssetReaderTrackOutput alloc] initWithTrack:track outputSettings:compressed ? nil : @{(NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange)}];
            [reader addOutput:output];
            if (![reader startReading]) { NSLog(@"start error=%@", reader.error); continue; }
            int count = 0;
            CMSampleBufferRef sample;
            while ((sample = [output copyNextSampleBuffer])) {
                if (compressed) NSLog(@"samples=%ld data=%p length=%zu", CMSampleBufferGetNumSamples(sample), CMSampleBufferGetDataBuffer(sample), CMSampleBufferGetDataBuffer(sample) ? CMBlockBufferGetDataLength(CMSampleBufferGetDataBuffer(sample)) : 0);
                if (CMSampleBufferGetImageBuffer(sample)) ++count;
                CFRelease(sample);
                if (!all && count >= 3) break;
            }
            NSLog(@"decodedImages=%d status=%ld error=%@", count, (long)reader.status, reader.error);
            [reader cancelReading];
        }
    }
    return 0;
}
