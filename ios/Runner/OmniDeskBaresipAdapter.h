#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^OmniDeskBaresipEventHandler)(NSString *type, NSString * _Nullable reason);

/// Small Objective-C facade around the pinned Baresip static library.  The
/// facade deliberately exposes only lifecycle/control operations to Swift;
/// SIP credentials never leave this object and are not persisted or logged.
@interface OmniDeskBaresipAdapter : NSObject

@property(nonatomic, readonly, nullable) NSString *mediaSessionId;
@property(nonatomic, readonly, nullable) NSString *callId;
@property(nonatomic, readonly, nullable) NSString *callSid;

- (instancetype)initWithEventHandler:(OmniDeskBaresipEventHandler)handler;
- (NSString *)ensureRegisteredWithUri:(NSString *)uri
                             username:(NSString *)username
                         authUsername:(NSString *)authUsername
                             password:(NSString *)password
                            registrar:(NSString *)registrar
                               domain:(NSString *)domain
                                proxy:(NSString *)proxy
                            transport:(NSString *)transport
                                 port:(NSInteger)port
                         incomingCallId:(NSString * _Nullable)incomingCallId
                                  error:(NSError * _Nullable * _Nullable)error;
- (NSString *)startOutgoingWithCallSid:(NSString *)callSid
                           targetSipUri:(NSString *)targetSipUri
                                  error:(NSError * _Nullable * _Nullable)error;
- (BOOL)endMedia:(NSString *)mediaSessionId error:(NSError * _Nullable * _Nullable)error;
- (BOOL)setMuted:(BOOL)enabled error:(NSError * _Nullable * _Nullable)error;
- (BOOL)setHeld:(BOOL)enabled error:(NSError * _Nullable * _Nullable)error;
- (BOOL)sendDtmf:(NSString *)digit error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
