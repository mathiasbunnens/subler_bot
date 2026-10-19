// Generated fixture builder only. GPL-2.0-or-later (links MP42Foundation).
#import <Foundation/Foundation.h>
#import <MP42Foundation/MP42Foundation.h>
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 4) return 2;
        NSURL *source = [NSURL fileURLWithPath:@(argv[1])];
        NSURL *dest = [NSURL fileURLWithPath:@(argv[2])];
        if ([[NSFileManager defaultManager] fileExistsAtPath:dest.path] || [source isEqual:dest]) return 2;
        NSError *error = nil;
        MP42FileImporter *importer = [[MP42FileImporter alloc] initWithURL:source error:&error];
        if (!importer) return 1;
        MP42File *file = [MP42File new];
        NSMutableArray<MP42AudioTrack *> *audio = [NSMutableArray array];
        for (MP42Track *track in importer.tracks) {
            [file addTrack:track];
            if ([track isKindOfClass:MP42AudioTrack.class]) {
                track.language = @"fr"; track.alternateGroup = 1;
                [audio addObject:(MP42AudioTrack *)track];
            }
        }
        if (audio.count != 6) return 3;
        for (unsigned i = 0; i < 3; i++) {
            audio[i+3].fallbackTrack = audio[i];
            audio[i+3].enabled = NO;
        }
        MP42ChapterTrack *chapters = [MP42ChapterTrack new];
        [chapters addChapter:@"Generated first" timestamp:0];
        [chapters addChapter:@"Generated second" timestamp:1000];
        [file addTrack:chapters];
        [file.metadata addMetadataItem:[MP42MetadataItem metadataItemWithIdentifier:MP42MetadataKeyName value:@"Generated preservation fixture" dataType:MP42MetadataItemDataTypeString extendedLanguageTag:nil]];
        [file.metadata addMetadataItem:[MP42MetadataItem metadataItemWithIdentifier:MP42MetadataKeyReleaseDate value:@"2026-01-01T00:00:00Z" dataType:MP42MetadataItemDataTypeString extendedLanguageTag:nil]];
        MP42Image *cover = [[MP42Image alloc] initWithURL:[NSURL fileURLWithPath:@(argv[3])] type:MP42_ART_PNG];
        [file.metadata addMetadataItem:[MP42MetadataItem metadataItemWithIdentifier:MP42MetadataKeyCoverArt value:cover dataType:MP42MetadataItemDataTypeImage extendedLanguageTag:nil]];
        if (![file writeToUrl:dest options:@{} error:&error]) return 1;
        return 0;
    }
}
