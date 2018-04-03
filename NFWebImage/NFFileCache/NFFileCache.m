//
//  NFFileCache.m
//  NFMemoryCache
//
//  Created by fulang on 2018/3/8.
//  Copyright © 2018年 fulang. All rights reserved.
//

#import "NFFileCache.h"
#import <CommonCrypto/CommonCrypto.h>

#define DefaultDirectoryName    @"NFFileCache"
#define CatalogFileName         @"CachesCatalog"

#define AddSkipBackupAttributeToItemAtPath(filePathString) \
{ \
    NSURL* URL= [NSURL fileURLWithPath: filePathString]; \
    if([self->_fileManager fileExistsAtPath: [URL path]]){ \
        [URL setResourceValue: [NSNumber numberWithBool: YES] forKey: NSURLIsExcludedFromBackupKey error: nil]; \
    } \
}

static NSString *_NFNSStringMD5(NSString *string) {
    if (!string) return nil;
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(data.bytes, (CC_LONG)data.length, result);
    return [NSString stringWithFormat:
            @"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
            result[0],  result[1],  result[2],  result[3],
            result[4],  result[5],  result[6],  result[7],
            result[8],  result[9],  result[10], result[11],
            result[12], result[13], result[14], result[15]
            ];
}

@interface _NFFileCacheCataLog : NSObject <NSCoding>

@property (nonatomic,assign) NSInteger count;
@property (nonatomic,assign) int64_t totalSize;
@property (nonatomic,strong) NSMutableSet *keys;

@end

@implementation _NFFileCacheCataLog

- (instancetype)init {
    self = [super init];
    _count      = 0;
    _totalSize  = 0;
    _keys  = [NSMutableSet set];
    return self;
}

- (void)encodeWithCoder:(nonnull NSCoder *)aCoder {
    [aCoder encodeInteger:_count forKey:@"count"];
    [aCoder encodeInt64:_totalSize forKey:@"totalSize"];
    [aCoder encodeObject:_keys forKey:@"keys"];
}

- (nullable instancetype)initWithCoder:(nonnull NSCoder *)aDecoder {
    self = [self init];
    _count      = [aDecoder decodeIntegerForKey:@"count"];
    _totalSize  = [aDecoder decodeInt64ForKey:@"totalSize"];
    _keys  = [aDecoder decodeObjectForKey:@"keys"];
    return self;
}

@end

@implementation NFFileCache {
    NSFileManager *_fileManager;
    dispatch_queue_t _queue;
    NSString *_catalogPath;
    _NFFileCacheCataLog *_catalog;
}

- (instancetype)initWithDirectoryPath:(NSString *)path {
    return [self initWithDirectoryPath:path name:nil];
}
- (instancetype)initWithDirectoryPath:(NSString *)path name:(NSString *)name {
    self = [super init];
    if (path.length == 0) {
        NSString *documentDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        _directoryPath = [documentDirectory stringByAppendingPathComponent:DefaultDirectoryName];
    }else {
        _directoryPath = path;
    }
    
    _fileManager = [NSFileManager defaultManager];
    if (![self _createDirectoryAtPathIfNeed:_directoryPath]) {
        return nil;
    }
    
    _name = name;
    _queue = dispatch_queue_create("com.nf.cache.file", DISPATCH_QUEUE_CONCURRENT);
    _catalogPath = [_directoryPath stringByAppendingPathComponent:CatalogFileName];
    
    if ([_fileManager fileExistsAtPath:_catalogPath]) {
        _catalog = [NSKeyedUnarchiver unarchiveObjectWithFile:_catalogPath];
    }else {
        _catalog = [_NFFileCacheCataLog new];
    }
    return self;
}

- (instancetype)init {
    return [self initWithDirectoryPath:nil];
}

#pragma mark - Public
- (int64_t)totalSize {
    return _catalog.totalSize;
}

- (BOOL)containsObjectForKey:(NSString *)key {
    if (key.length == 0) {
        return NO;
    }
    return [_catalog.keys containsObject:key];
}

- (id)objectForKey:(NSString *)key {
    if (![self containsObjectForKey:key]) {
        return nil;
    }
    NSData *data = [self _dataForKey:key];
    if (data == nil) {
        return nil;
    }
    id object = nil;
    if (self.customUnArchiveBlock) {
        object = self.customUnArchiveBlock(data);
    }else {
        @try {
            object = [NSKeyedUnarchiver unarchiveObjectWithData:data];
        } @catch (NSException *e) {
            NSLog(@"unarchive data failed for key: %@", key);
        }
    }
    return object;
}

- (void)objectForKey:(NSString *)key withBlock:(void (^)(NSString *, id))block {
    if (!block) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) self = weakSelf;
        id object = [self objectForKey:key];
        dispatch_async(dispatch_get_main_queue(), ^{
            block(key, object);
        });
    });
}

- (void)setObject:(id)object forKey:(NSString *)key {
    if (key.length == 0) { return; }
    if (object == nil) {
        [self removeObjectForKey:key];
        return;
    }
    NSData *data = nil;
    if (self.customArchiveBlock) {
        data = self.customArchiveBlock(object);
    }else {
        @try {
            data = [NSKeyedArchiver archivedDataWithRootObject:object];
        } @catch (NSException *e) {
            NSLog(@"archive object failed for key: %@", key);
        }
    }
    if (data) {
        NSString *filePath = [self _filePathForKey:key];
        [data writeToFile:filePath atomically:YES];
        [_catalog.keys addObject:key];
    }
}

- (void)setObject:(id)object forKey:(NSString *)key withBlock:(void (^)(void))block {
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) self = weakSelf;
        [self setObject:object forKey:key];
        dispatch_async(dispatch_get_main_queue(), ^{
            !block?:block();
        });
    });
}

- (void)removeObjectForKey:(NSString *)key {
    
}

- (void)removeAllObject {
    
}

#pragma mark - Private
- (NSData *)_dataForKey:(NSString *)key {
    NSString *filePath = [self _filePathForKey:key];
    return [NSData dataWithContentsOfFile:filePath];
}

- (NSString *)_fileNameForKey:(NSString *)key {
    NSString *fileName = nil;
    if (self.customFileNameBlock) {
        fileName = self.customFileNameBlock(key);
    }else {
        fileName = _NFNSStringMD5(key);
    }
    return fileName;
}

- (NSString *)_filePathForKey:(NSString *)key {
    NSString *filename = [self _fileNameForKey:key];
    return [_directoryPath stringByAppendingPathComponent:filename];
}

- (BOOL)_createDirectoryAtPathIfNeed:(NSString *)path {
    BOOL isDirectory = NO;
    BOOL needCreate = NO;
    NSError *error = nil;
    [_fileManager fileExistsAtPath:path];
    if (![_fileManager fileExistsAtPath:path isDirectory:&isDirectory]) {
        needCreate = YES;
    }else if (!isDirectory){
        [_fileManager removeItemAtPath:path error:nil];
        needCreate = YES;
    }
    if (!needCreate) {
        return YES;
    }
    if ([_fileManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error]) {
        AddSkipBackupAttributeToItemAtPath(path)
        return YES;
    }else {
        NSLog(@"create directory error: %@", error);
        return NO;
    }
}

@end
