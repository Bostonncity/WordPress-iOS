#import "BlogServiceRemoteXMLRPC.h"
#import <WordPressApi/WordPressApi.h>
#import "WordPress-Swift.h"

@implementation BlogServiceRemoteXMLRPC

- (void)checkMultiAuthorForBlogID:(NSNumber *)blogID
                          success:(void(^)(BOOL isMultiAuthor))success
                          failure:(void (^)(NSError *error))failure
{
    NSParameterAssert(blogID != nil);
    NSDictionary *filter = @{@"who":@"authors"};
    NSArray *parameters = [self getXMLRPCArgsForBlogWithID:blogID extra:filter];
    [self.api callMethod:@"wp.getUsers"
              parameters:parameters
                 success:^(AFHTTPRequestOperation *operation, id responseObject) {
                     if (success) {
                         NSArray *response = (NSArray *)responseObject;
                         BOOL isMultiAuthor = [response count] > 1;
                         success(isMultiAuthor);
                     }
                 } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                     if (failure) {
                         failure(error);
                     }
                 }];
}

- (void)syncOptionsForBlogID:(NSNumber *)blogID success:(OptionsHandler)success failure:(void (^)(NSError *))failure
{
    WPXMLRPCRequestOperation *operation = [self operationForOptionsWithBlogID:blogID success:success failure:failure];
    [self.api enqueueXMLRPCRequestOperation:operation];
}

- (void)syncPostFormatsForBlogID:(NSNumber *)blogID success:(PostFormatsHandler)success failure:(void (^)(NSError *))failure
{
    WPXMLRPCRequestOperation *operation = [self operationForPostFormatsWithBlogID:blogID success:success failure:failure];
    [self.api enqueueXMLRPCRequestOperation:operation];
}

- (void)syncSettingsForBlogID:(NSNumber *)blogID
                    success:(SettingsHandler)success
                    failure:(void (^)(NSError *error))failure
{
    NSArray *parameters = [self getXMLRPCArgsForBlogWithID:blogID extra:nil];
    [self.api callMethod:@"wp.getOptions" parameters:parameters success:^(AFHTTPRequestOperation *operation, id responseObject) {
        if (![responseObject isKindOfClass:[NSDictionary class]]) {
            if (failure) {
                failure(nil);
            }
            return;
        }
        NSDictionary *XMLRPCDictionary = (NSDictionary *)responseObject;
        RemoteBlogSettings *remoteSettings = [self remoteBlogSettingFromXMLRPCDictionary:XMLRPCDictionary];
        if (success) {
            success(remoteSettings);
        }
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        DDLogError(@"Error syncing settings: %@", error);
        if (failure) {
            failure(error);
        }
    }];
}

- (void)updateBlogSettings:(RemoteBlogSettings *)remoteBlogSettings
                 forBlogID:(NSNumber *)blogID
                   success:(SuccessHandler)success
                   failure:(void (^)(NSError *error))failure
{
    NSDictionary *rawParameters = @{
        @"blog_title"   : remoteBlogSettings.name,
        @"blog_tagline" : remoteBlogSettings.tagline
    };
    
    NSArray *parameters = [self getXMLRPCArgsForBlogWithID:blogID extra:rawParameters];
    
    [self.api callMethod:@"wp.setOptions" parameters:parameters success:^(AFHTTPRequestOperation *operation, id responseObject) {
        if (![responseObject isKindOfClass:[NSDictionary class]]) {
            if (failure) {
                failure(nil);
            }
            return;
        }
        NSDictionary *XMLRPCDictionary = (NSDictionary *)responseObject;
        RemoteBlogSettings *remoteSettings = [self remoteBlogSettingFromXMLRPCDictionary:XMLRPCDictionary];
        if (success) {
            success(remoteSettings);
        }
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        DDLogError(@"Error syncing settings: %@", error);
        if (failure) {
            failure(error);
        }
    }];
}



- (WPXMLRPCRequestOperation *)operationForOptionsWithBlogID:(NSNumber *)blogID
                                                    success:(OptionsHandler)success
                                                    failure:(void (^)(NSError *error))failure
{
    NSArray *parameters = [self getXMLRPCArgsForBlogWithID:blogID extra:nil];
    WPXMLRPCRequest *request = [self.api XMLRPCRequestWithMethod:@"wp.getOptions" parameters:parameters];
    WPXMLRPCRequestOperation *operation = [self.api XMLRPCRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSAssert([responseObject isKindOfClass:[NSDictionary class]], @"Response should be a dictionary.");

        if (success) {
            success(responseObject);
        }
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        DDLogError(@"Error syncing options: %@", error);

        if (failure) {
            failure(error);
        }
    }];

    return operation;
}

- (WPXMLRPCRequestOperation *)operationForPostFormatsWithBlogID:(NSNumber *)blogID
                                                        success:(PostFormatsHandler)success
                                                        failure:(void (^)(NSError *error))failure
{
    NSDictionary *dict = @{@"show-supported": @"1"};
    NSArray *parameters = [self getXMLRPCArgsForBlogWithID:blogID extra:dict];

    WPXMLRPCRequest *request = [self.api XMLRPCRequestWithMethod:@"wp.getPostFormats" parameters:parameters];
    WPXMLRPCRequestOperation *operation = [self.api XMLRPCRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSAssert([responseObject isKindOfClass:[NSDictionary class]], @"Response should be a dictionary.");

        NSDictionary *postFormats = responseObject;
        NSDictionary *respDict = responseObject;
        if ([postFormats objectForKey:@"supported"]) {
            NSMutableArray *supportedKeys;
            if ([[postFormats objectForKey:@"supported"] isKindOfClass:[NSArray class]]) {
                supportedKeys = [NSMutableArray arrayWithArray:[postFormats objectForKey:@"supported"]];
            } else if ([[postFormats objectForKey:@"supported"] isKindOfClass:[NSDictionary class]]) {
                supportedKeys = [NSMutableArray arrayWithArray:[[postFormats objectForKey:@"supported"] allValues]];
            }
            
            // Standard isn't included in the list of supported formats? Maybe it will be one day?
            if (![supportedKeys containsObject:@"standard"]) {
                [supportedKeys addObject:@"standard"];
            }

            NSDictionary *allFormats = [postFormats objectForKey:@"all"];
            NSMutableArray *supportedValues = [NSMutableArray array];
            for (NSString *key in supportedKeys) {
                [supportedValues addObject:[allFormats objectForKey:key]];
            }
            respDict = [NSDictionary dictionaryWithObjects:supportedValues forKeys:supportedKeys];
        }

        if (success) {
            success(respDict);
        }
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        DDLogError(@"Error syncing post formats (%@): %@", operation.request.URL, error);

        if (failure) {
            failure(error);
        }
    }];

    return operation;
}

- (RemoteBlogSettings *)remoteBlogSettingFromXMLRPCDictionary:(NSDictionary *)json
{
    RemoteBlogSettings *remoteSettings = [RemoteBlogSettings new];
    
    remoteSettings.name = [json stringForKeyPath:@"blog_title.value"];
    remoteSettings.tagline = [json stringForKeyPath:@"blog_tagline.value"];
    if (json[@"blog_public"]) {
        remoteSettings.privacy = [json numberForKeyPath:@"blog_public.value"];
    }
    return remoteSettings;
}

@end
