//
//  ExtensionBridge.h
//  FocusDnsNetworkExtension
//
//  Objective-C / C Bridging header for low-level POSIX socket control,
//  Mach port messaging, and Darwin notifications.
//

#ifndef ExtensionBridge_h
#define ExtensionBridge_h

#import <Foundation/Foundation.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>

NS_ASSUME_NONNULL_BEGIN

/// FocusDNS Native System Extension C Helper utilities.
@interface FocusExtensionBridge : NSObject

/// Verifies whether the process has root or network extension entitlements.
+ (BOOL)hasSystemExtensionEntitlement;

/// Resolves raw IP address string into binary sockaddr_in structure.
+ (BOOL)parseIpv4String:(NSString *)ipAddress outSockAddr:(struct sockaddr_in *)outAddr;

/// Post a Darwin notification to the macOS desktop shell.
+ (void)postDarwinNotification:(NSString *)notificationName;

/// Queries the macOS Security framework for the presence of the hardware-backed Focus token.
+ (nullable NSData *)querySecureEnclaveTokenWithKey:(NSString *)tag;

@end

NS_ASSUME_NONNULL_END

#endif /* ExtensionBridge_h */
