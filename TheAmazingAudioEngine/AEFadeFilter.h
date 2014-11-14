
//
//  AEBlockFilter.h
//  TheAmazingAudioEngine
//
//  Created by Michael Tyson on 20/12/2012.
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

#ifdef __cplusplus
extern "C" {
#endif

#import <Foundation/Foundation.h>
#import <Accelerate/Accelerate.h>
#import "TheAmazingAudioEngine.h"
#import "AEBlockFilter.h"

@protocol MyProtocolName;

@interface AEFadeFilter : AEBlockFilter <AEAudioFilter>

/*!
 * Create a new filter with a given block
 *
 * @param block Block to use for audio generation
 */
+ (AEFadeFilter*)initWithFadeOut;
+ (AEBlockFilter*)createFadeOut;
- (void)startFadeOut;

@property (nonatomic, assign) int fadeInMs;              //!< Fade in time ms
@property (nonatomic, assign) int fadeOutMs;              //!< Fade out time ms
@property (nonatomic, strong) void (^completionBlock)(void);
@property (nonatomic, weak) id<MyProtocolName> delegate;

@end

@protocol MyProtocolName <NSObject>

@optional
-(void)onFadeInComplete;
-(void)onFadeOutComplete;

@end // end of delegate protocol


#ifdef __cplusplus
}
#endif
