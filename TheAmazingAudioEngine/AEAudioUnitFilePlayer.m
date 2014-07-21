//
//  AEAudioUnitFilePlayer.m
//  TheAmazingAudioEngine
//
//  Created by Michael Tyson on 01/02/2013.
//
//  This software is provided 'as-is', without any express or implied
//  warranty.  In no event will the authors be held liable for any damages
//  arising from the use of this software.
//
//  Permission is granted to anyone to use this software for any purpose,
//  including commercial applications, and to alter it and redistribute it
//  freely, subject to the following restrictions:
//
//  1. The origin of this software must not be misrepresented; you must not
//     claim that you wrote the original software. If you use this software
//     in a product, an acknowledgment in the product documentation would be
//     appreciated but is not required.
//
//  2. Altered source versions must be plainly marked as such, and must not be
//     misrepresented as being the original software.
//
//  3. This notice may not be removed or altered from any source distribution.
//

#import "AEAudioUnitFilePlayer.h"

#define checkResult(result,operation) (_checkResult((result),(operation),strrchr(__FILE__, '/')+1,__LINE__))
static inline BOOL _checkResult(OSStatus result, const char *operation, const char* file, int line) {
    if ( result != noErr ) {
        int fourCC = CFSwapInt32HostToBig(result);
        NSLog(@"%s:%d: %s result %d %08X %4.4s\n", file, line, operation, (int)result, (int)result, (char*)&fourCC);
        return NO;
    }
    return YES;
}

@interface AEAudioUnitFilePlayer () {
    AEAudioController *_audioController;
    AudioComponentDescription _componentDescription;
    AUNode _node;
    AudioUnit _audioUnit;
    AUNode _converterNode;
    AudioUnit _converterUnit;
    AUGraph _audioGraph;
    AudioFileID _audioUnitFile;
    SInt32 _locatehead;
    SInt32 _playhead;
    UInt32 _lengthInFrames;
}
@end

@implementation AEAudioUnitFilePlayer
@synthesize url=_url, fileAudioDescription=_fileAudioDescription;

- (id)initWithAudioController:(AEAudioController*)audioController
                                 error:(NSError**)error {
    AudioComponentDescription audioComponentDescription = AEAudioComponentDescriptionMake(kAudioUnitManufacturer_Apple, kAudioUnitType_Generator, kAudioUnitSubType_AudioFilePlayer);
    return [self initWithComponentDescription:audioComponentDescription audioController:audioController  preInitializeBlock:nil error:error];
}

- (id)initWithComponentDescription:(AudioComponentDescription)audioComponentDescription
                       audioController:(AEAudioController*)audioController
                                 error:(NSError**)error {
    return [self initWithComponentDescription:audioComponentDescription audioController:audioController  preInitializeBlock:nil error:error];
}

- (id)initWithComponentDescription:(AudioComponentDescription)audioComponentDescription
                   audioController:(AEAudioController*)audioController
                preInitializeBlock:(void(^)(AudioUnit audioUnit))block
                             error:(NSError**)error {

    if ( !(self = [super init]) ) return nil;

    // Create the node, and the audio unit
    _audioController = audioController;
    _componentDescription = audioComponentDescription;
    _audioGraph = _audioController.audioGraph;

    if ( ![self setup:block error:error] ) {
        return nil;
    }

    self.volume = 1.0;
    self.pan = 0.0;
    self.channelIsMuted = NO;
    self.channelIsPlaying = YES;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didRecreateGraph:) name:AEAudioControllerDidRecreateGraphNotification object:_audioController];

    return self;
}

- (BOOL)setup:(void(^)(AudioUnit audioUnit))block error:(NSError**)error {
	OSStatus result;
    if ( !checkResult(result=AUGraphAddNode(_audioGraph, &_componentDescription, &_node), "AUGraphAddNode") ||
         !checkResult(result=AUGraphNodeInfo(_audioGraph, _node, NULL, &_audioUnit), "AUGraphNodeInfo") ) {
        if ( error ) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:result userInfo:@{NSLocalizedDescriptionKey: @"Couldn't initialise audio unit"}];
        return NO;
    }

    UInt32 maxFPS = 4096;
    checkResult(result=AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFPS, sizeof(maxFPS)), "kAudioUnitProperty_MaximumFramesPerSlice");

    // Try to set the output audio description
    AudioStreamBasicDescription audioDescription = _audioController.audioDescription;
    result = AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &audioDescription, sizeof(AudioStreamBasicDescription));
    if ( result == kAudioUnitErr_FormatNotSupported ) {
        // The audio description isn't supported. Assign modified default audio description, and create an audio converter.
        AudioStreamBasicDescription defaultAudioDescription;
        UInt32 size = sizeof(defaultAudioDescription);
        AudioUnitGetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &defaultAudioDescription, &size);
        defaultAudioDescription.mSampleRate = audioDescription.mSampleRate;
        AEAudioStreamBasicDescriptionSetChannelsPerFrame(&defaultAudioDescription, audioDescription.mChannelsPerFrame);
        if ( !checkResult(result=AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &defaultAudioDescription, size), "AudioUnitSetProperty") ) {
            if ( error ) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:result userInfo:@{NSLocalizedDescriptionKey: @"Incompatible audio format"}];
            return NO;
        }

        AudioComponentDescription audioConverterDescription = AEAudioComponentDescriptionMake(kAudioUnitManufacturer_Apple, kAudioUnitType_FormatConverter, kAudioUnitSubType_AUConverter);
        if ( !checkResult(result=AUGraphAddNode(_audioGraph, &audioConverterDescription, &_converterNode), "AUGraphAddNode") ||
             !checkResult(result=AUGraphNodeInfo(_audioGraph, _converterNode, NULL, &_converterUnit), "AUGraphNodeInfo") ||
             !checkResult(result=AudioUnitSetProperty(_converterUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &defaultAudioDescription, sizeof(AudioStreamBasicDescription)), "AudioUnitSetProperty(kAudioUnitProperty_StreamFormat)") ||
             !checkResult(result=AudioUnitSetProperty(_converterUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &audioDescription, sizeof(AudioStreamBasicDescription)), "AudioUnitSetProperty(kAudioUnitProperty_StreamFormat)") ||
             !checkResult(result=AudioUnitSetProperty(_converterUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFPS, sizeof(maxFPS)), "kAudioUnitProperty_MaximumFramesPerSlice") ||
             !checkResult(result=AUGraphConnectNodeInput(_audioGraph, _node, 0, _converterNode, 0), "AUGraphConnectNodeInput") ) {

            if ( error ) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:result userInfo:@{NSLocalizedDescriptionKey: @"Couldn't setup converter audio unit"}];
            return NO;
        }

        // Set the audio unit to handle up to 4096 frames per slice to keep rendering during screen lock
        UInt32 maxFPS = 4096;
        checkResult(AudioUnitSetProperty(_converterUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFPS, sizeof(maxFPS)),
                    "AudioUnitSetProperty(kAudioUnitProperty_MaximumFramesPerSlice)");
    }

    checkResult(AUGraphUpdate(_audioGraph, NULL), "AUGraphUpdate");

    if(block) block(_audioUnit);

    checkResult(AudioUnitInitialize(_audioUnit), "AudioUnitInitialize");

    if ( _converterUnit ) {
        checkResult(AudioUnitInitialize(_converterUnit), "AudioUnitInitialize");
    }

    [self setupAudioFilePlayer];

    return YES;
}

-(void)setupAudioFilePlayer {
    _audioUnitFile = nil;
    _url = nil;
    _playhead = 0;
    _locatehead = 0;
    _lengthInFrames = 0;
    checkResult(AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Global, 0, &_componentDescription, sizeof(&_componentDescription)),
        "AudioUnitSetProperty(kAudioUnitProperty_StreamFormat)");
}

-(void)setUrl:(NSURL *)url {
    [self loadUrl:url error:nil];
}
//
//-----------------------------------------------------------------------------
- (void)loadUrl:(NSURL*)url error:(NSError**)error {
    OSStatus result;

    if ( _audioUnitFile ) {
        AudioFileClose(_audioUnitFile);
        _audioUnitFile = nil;
    }
    if (url) {
        checkResult(result=AudioFileOpenURL((__bridge CFURLRef) url, kAudioFileReadPermission, 0, &_audioUnitFile), "AudioFileOpenURL");
        if (noErr == result) {
            // Set the file to play
            checkResult(AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_ScheduledFileIDs, kAudioUnitScope_Global, 0, &_audioUnitFile, sizeof(_audioUnitFile)),
                "AudioUnitSetProperty(kAudioUnitProperty_ScheduledFileIDs)");

            // Determine file properties
            UInt64 packetCount;
            UInt32 size = sizeof(packetCount);
            checkResult(AudioFileGetProperty(_audioUnitFile, kAudioFilePropertyAudioDataPacketCount, &size, &packetCount),
                "AudioFileGetProperty(kAudioFilePropertyAudioDataPacketCount)");

            size = sizeof(_fileAudioDescription);
            checkResult(AudioFileGetProperty(_audioUnitFile, kAudioFilePropertyDataFormat, &size, &_fileAudioDescription),
                "AudioFileGetProperty(kAudioFilePropertyDataFormat)");

            _lengthInFrames = packetCount * _fileAudioDescription.mFramesPerPacket;
            _url = url;

            [self setupPlayRegion];
        }
    }

}

- (OSStatus)setupPlayRegion {
    OSStatus result = -1;

    if (_audioUnitFile) {
        if (_locatehead >= _lengthInFrames) {
            _locatehead = 0;
        }

        ScheduledAudioFileRegion region;
        memset (&region.mTimeStamp, 0, sizeof(region.mTimeStamp));
        region.mTimeStamp.mFlags = kAudioTimeStampSampleTimeValid;
        region.mTimeStamp.mSampleTime = 0;
        //region.mCompletionProc = audioRegionCompletion;
        //region.mCompletionProcUserData = (__bridge void *)(self);
        region.mCompletionProc = nil;
        region.mCompletionProcUserData = nil;
        region.mAudioFile = _audioUnitFile;
        region.mLoopCount = 0;
        region.mStartFrame = _locatehead;
        region.mFramesToPlay = _lengthInFrames - _locatehead;

        checkResult(result = AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_ScheduledFileRegion, kAudioUnitScope_Global, 0, &region, sizeof(region)),
                         "AudioUnitSetProperty(kAudioUnitProperty_ScheduledFileRegion)");

        // Prime the player by reading some frames from disk
        UInt32 defaultNumberOfFrames = 0;
        checkResult(result = AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_ScheduledFilePrime, kAudioUnitScope_Global, 0, &defaultNumberOfFrames, sizeof(defaultNumberOfFrames)),
                         "AudioUnitSetProperty(kAudioUnitProperty_ScheduledFilePrime)");

         // Set the start time (now = -1)
         AudioTimeStamp startTime;
        memset (&startTime, 0, sizeof(startTime));
        startTime.mFlags = kAudioTimeStampSampleTimeValid;
        startTime.mSampleTime = -1;
        checkResult(AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_ScheduleStartTimeStamp, kAudioUnitScope_Global, 0, &startTime, sizeof(startTime)),
                    "AudioUnitSetProperty(kAudioUnitProperty_ScheduleStartTimeStamp)");
    }

    return result;
}

//-----------------------------------------------------------------------------
-(NSTimeInterval) duration {
    if (_fileAudioDescription.mSampleRate > 1.0f) {
        return (double)_lengthInFrames / (double)_fileAudioDescription.mSampleRate;
    }
    return 0.0f;
}

-(NSTimeInterval) currentTime {
    if (self.channelIsPlaying) {
        OSStatus result;
        AudioTimeStamp curTime;
        memset (&curTime, 0, sizeof(curTime));
        UInt32 size = sizeof(curTime);

        checkResult(result=AudioUnitGetProperty(_audioUnit, kAudioUnitProperty_CurrentPlayTime,
                                                             kAudioUnitScope_Global, 0, &curTime, &size),
                                                             "AudioUnitGetProperty - kAudioUnitProperty_CurrentPlayTime");

        if (_fileAudioDescription.mSampleRate > 1.0f && _audioController.audioDescription.mSampleRate > 1.0f) {
            // correct for the difference between the input and playback rate
            double sampleRateRatio = (double)_fileAudioDescription.mSampleRate / (double)_audioController.audioDescription.mSampleRate;
            if (curTime.mSampleTime < 0.0f) // http://lists.apple.com/archives/coreaudio-api/2008/May/msg00143.html
                _playhead = 0;
            else
                _playhead = (unsigned long)curTime.mSampleTime * sampleRateRatio;
            _playhead += _locatehead;
        }
    }

    if (_fileAudioDescription.mSampleRate > 1.0f) {
        return (double)_playhead / (double)_fileAudioDescription.mSampleRate;
    }

    return 0.0f;
}

-(void) setPlaying:(BOOL)isPlaying {
    if (isPlaying) {
        if (!self.channelIsPlaying) {
            // cancel any previous detection of playback finish we may have had going on
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(completionCallSetup) object:nil];

            // need to reset before creating the new start region
            AudioUnitReset(_audioUnit, kAudioUnitScope_Global, 0);
            [self setupPlayRegion];

            self.channelIsPlaying = YES;

            // if we located close to the end, we need to fire up our end detection manually,
            // as audioRegionCompletion proc may not get called if we push out the buffer initially
            // a few seconds before the end seems to be a safe, but not overly agressive value
            NSTimeInterval ct = [self currentTime];
            NSTimeInterval dt = [self duration];
            if ((dt-ct) < 3.0f) {
                //[self completionCallSetup];
            }
        }
    } else if (self.channelIsPlaying) {
        // cancel any previous detection of playback finish we may have had going on
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(completionCallSetup) object:nil];

        // call currentTime to update _playhead
        [self currentTime];
        _locatehead = _playhead;
        self.channelIsPlaying = NO;
    }
}

-(void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AEAudioControllerDidRecreateGraphNotification object:_audioController];

    if ( _node ) {
        checkResult(AUGraphRemoveNode(_audioGraph, _node), "AUGraphRemoveNode");
    }
    if ( _converterNode ) {
        checkResult(AUGraphRemoveNode(_audioGraph, _converterNode), "AUGraphRemoveNode");
    }

    checkResult(AUGraphUpdate(_audioGraph, NULL), "AUGraphUpdate");

}

-(AudioUnit)audioUnit {
    return _audioUnit;
}

-(AUNode)audioGraphNode {
    return _node;
}

static OSStatus renderCallback(__unsafe_unretained AEAudioUnitFilePlayer *THIS,
                               __unsafe_unretained AEAudioController *audioController,
                               const AudioTimeStamp     *time,
                               UInt32                    frames,
                               AudioBufferList          *audio) {
    AudioUnitRenderActionFlags flags = 0;
    checkResult(AudioUnitRender(THIS->_converterUnit ? THIS->_converterUnit : THIS->_audioUnit, &flags, time, 0, frames, audio), "AudioUnitRender");
    return noErr;
}

-(AEAudioControllerRenderCallback)renderCallback {
    return renderCallback;
}

- (void)didRecreateGraph:(NSNotification*)notification {
    _node = 0;
    _audioUnit = NULL;
    _converterNode = 0;
    _converterUnit = NULL;
    _audioGraph = _audioController.audioGraph;
    [self setup:nil error:NULL];
}

@end
