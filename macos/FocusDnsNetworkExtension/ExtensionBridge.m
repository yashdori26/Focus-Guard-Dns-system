//
//  ExtensionBridge.m
//  FocusDnsNetworkExtension
//
//  Low-level POSIX and Darwin C integration for FocusDNS macOS Network Extension.
//

#import "ExtensionBridge.h"
#import <Security/Security.h>
#import <notify.h>

@implementation FocusExtensionBridge

+ (BOOL)hasSystemExtensionEntitlement {
    // Audit current process entitlements
    SecTaskRef task = SecTaskCreateFromSelf(NULL);
    if (!task) return NO;

    CFTypeRef entitlement = SecTaskCopyValueForEntitlement(task, CFSTR("com.apple.developer.networking.networkextension"), NULL);
    BOOL hasEntitlement = (entitlement != NULL);
    if (entitlement) CFRelease(entitlement);
    CFRelease(task);

    return hasEntitlement;
}

+ (BOOL)parseIpv4String:(NSString *)ipAddress outSockAddr:(struct sockaddr_in *)outAddr {
    if (!ipAddress || !outAddr) return NO;
    memset(outAddr, 0, sizeof(struct sockaddr_in));
    outAddr->sin_family = AF_INET;
    outAddr->sin_len = sizeof(struct sockaddr_in);

    int result = inet_pton(AF_INET, [ipAddress UTF8String], &(outAddr->sin_addr));
    return (result == 1);
}

+ (void)postDarwinNotification:(NSString *)notificationName {
    if (!notificationName) return;
    notify_post([notificationName UTF8String]);
}

+ (nullable NSData *)querySecureEnclaveTokenWithKey:(NSString *)tag {
    if (!tag) return nil;

    NSData *tagData = [tag dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassKey,
        (__bridge id)kSecAttrApplicationTag: tagData,
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecReturnData: @YES
    };

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status == errSecSuccess && result) {
        return (__bridge_transfer NSData *)result;
    }
    return nil;
}

@end
