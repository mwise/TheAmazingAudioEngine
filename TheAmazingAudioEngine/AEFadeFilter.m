//
//  AEFadeFilter.m
//  TheAmazingAudioEngine
//
//  Created by Mark Wise on 13/11/2014.
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

#import "AEFadeFilter.h"

#define LAKE_LEFT_CHANNEL (0)
#define LAKE_RIGHT_CHANNEL (1)
#define kFadeIn (0)
#define kFadeOut (1)

@interface AEFadeFilter ()
@property (nonatomic, assign) float scalar;
@property (nonatomic, copy) AEBlockFilterBlock block;
@property (nonatomic, assign) int fadeFlag;              //!< current fade
@end

@implementation AEFadeFilter
@synthesize block = _block;

  - (id)initWithBlock:(AEBlockFilterBlock)block {
      if ( !(self = [super init]) ) self = nil;
      self.block = block;
      return self;
  }

  - (id)initWithFadeOut {
      //if ( !(self = [super init]) ) self = nil;
      self.scalar = 0.56f;
      self.fadeFlag = 2;
      float fadeInDelta = 0.1;
      float fadeOutDelta = 0.05;
      AEFadeFilter * __weak weakSelf = self;

      self = [self initWithBlock:^(AEAudioControllerFilterProducer producer,
                                                  void                     *producerToken,
                                                  const AudioTimeStamp     *time,
                                                  UInt32                    frames,
                                                  AudioBufferList          *audio) {
        // Pull audio
        OSStatus status = producer(producerToken, audio, &frames);
        if ( status != noErr ) return;

        if (weakSelf.fadeFlag == kFadeIn) {
          if (weakSelf.scalar < 1) {
            weakSelf.scalar += fadeInDelta; // experiment with this to adjust the fade time
          } else if (weakSelf.scalar >= 1) {
            weakSelf.scalar = 1;
            weakSelf.fadeFlag = 2;
            if (weakSelf.delegate && [weakSelf.delegate respondsToSelector:@selector(onFadeInComplete)]) {
              [weakSelf.delegate onFadeInComplete];
            }
          }
        } else if (weakSelf.fadeFlag == kFadeOut) {
          if (weakSelf.scalar > 0.0) {
            weakSelf.scalar -= fadeOutDelta;
          } else if (weakSelf.scalar <= 0) {
            weakSelf.scalar = 0;
            weakSelf.fadeFlag = 2;

            if (weakSelf.delegate && [weakSelf.delegate respondsToSelector:@selector(onFadeOutComplete)]) {
              [weakSelf.delegate onFadeOutComplete];
            }
          }
        }

        float myScalar = (float) weakSelf.scalar;

        vDSP_vsmul(audio->mBuffers[LAKE_RIGHT_CHANNEL].mData, 1, &myScalar, audio->mBuffers[LAKE_RIGHT_CHANNEL].mData, 1, frames);
        vDSP_vsmul(audio->mBuffers[LAKE_LEFT_CHANNEL].mData, 1, &myScalar, audio->mBuffers[LAKE_LEFT_CHANNEL].mData, 1, frames);
      }];

      return self;
  }

  - (void) startFadeOut {
    _fadeFlag = kFadeOut;
  }

  - (void) startFadeIn {
    _fadeFlag = kFadeIn;
  }

  + (AEFadeFilter*)initWithFadeOut {
      return [[AEFadeFilter alloc] initWithFadeOut];
  }

  + (AEFadeFilter*)createFadeOut {
      return [[AEFadeFilter alloc] initWithFadeOut];
  }

static OSStatus filterCallback(__unsafe_unretained AEFadeFilter *THIS,
                               __unsafe_unretained AEAudioController *audioController,
                               AEAudioControllerFilterProducer producer,
                               void                     *producerToken,
                               const AudioTimeStamp     *time,
                               UInt32                    frames,
                               AudioBufferList          *audio) {
    THIS->_block(producer, producerToken, time, frames, audio);
    return noErr;
}

-(AEAudioControllerFilterCallback)filterCallback {
    return filterCallback;
}

@end
