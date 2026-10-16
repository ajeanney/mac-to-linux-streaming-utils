#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <math.h>

// CoreBrightness is private: fail explicitly if macOS changes this interface.
@interface NSObject (KeyboardBacklight)
- (float)brightnessForKeyboard:(unsigned long long)keyboard;
- (BOOL)setBrightness:(float)level forKeyboard:(unsigned long long)keyboard;
- (BOOL)isAutoBrightnessEnabledForKeyboard:(unsigned long long)keyboard;
- (BOOL)enableAutoBrightness:(BOOL)enabled forKeyboard:(unsigned long long)keyboard;
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY);
        id client = [[NSClassFromString(@"KeyboardBrightnessClient") alloc] init];
        for (NSString *name in @[@"brightnessForKeyboard:", @"setBrightness:forKeyboard:",
                                @"isAutoBrightnessEnabledForKeyboard:", @"enableAutoBrightness:forKeyboard:"]) {
            if (![client respondsToSelector:NSSelectorFromString(name)]) {
                fprintf(stderr, "Keyboard brightness control unavailable\n");
                return 1;
            }
        }
        if (argc == 3) {
            char *end;
            float level = strtof(argv[1], &end);
            if (!*argv[1] || *end || !isfinite(level) || level < 0 || level > 1 ||
                (strcmp(argv[2], "0") && strcmp(argv[2], "1"))) return 2;
            // Disable the ambient light sensor before changing brightness.
            if (![client enableAutoBrightness:NO forKeyboard:1] ||
                ![client setBrightness:level forKeyboard:1]) return 1;
            usleep(500000);
            if (fabsf([client brightnessForKeyboard:1] - level) > 0.02f) return 1;
            if (![client enableAutoBrightness:atoi(argv[2]) forKeyboard:1]) return 1;
        } else if (argc != 1) {
            fprintf(stderr, "usage: mac-keyboard-backlight [LEVEL AUTO_BRIGHTNESS_0_OR_1]\n");
            return 2;
        }
        float level = [client brightnessForKeyboard:1];
        if (!isfinite(level) || level < 0 || level > 1) return 1;
        printf("{\"level\":%.6f,\"auto\":%d}\n", level,
               [client isAutoBrightnessEnabledForKeyboard:1]);
    }
}
