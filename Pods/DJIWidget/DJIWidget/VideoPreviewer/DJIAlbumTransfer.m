//
//  DJIAlbumTransfer.h
//
//  Copyright (c) 2015 DJI. All rights reserved.
//


#import <DJIWidgetMacros.h>
#import "DJIAlbumTransfer.h"
#import <Photos/Photos.h>

#ifndef SAFE_BLOCK
#define SAFE_BLOCK(block, ...) if(block){block(__VA_ARGS__);};
#endif

@implementation DJIAlbumTransfer
+(void) writeVideo:(NSString*)file toAlbum:(NSString*)album completionBlock:(void(^)(NSURL *assetURL, NSError *error))block{
    NSFileManager* fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:file]) {
        NSError *customError = [[NSError alloc] initWithDomain:@"drone.dji.com" code:DJIAlbumTransferErrorCode_FileNotFound userInfo:nil];
        SAFE_BLOCK(block, nil, customError);
        return;
    }
    
    if(!UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(file)){
        NSError *customError = [[NSError alloc] initWithDomain:@"drone.dji.com" code:DJIAlbumTransferErrorCode_FileCannotPlay userInfo:nil];
        SAFE_BLOCK(block, nil, customError);
        return;
    }
    
    NSURL* fileURL = [NSURL fileURLWithPath:file];
    [self saveVideoToAssetLibrary:fileURL albumName:album completionBlock:^(NSURL *assetURL, NSError *error) {
        SAFE_BLOCK(block, assetURL, error);
    }];
}

+(void) writeVidoToAssetLibrary:(NSString*)file completionBlock:(void(^)(NSURL *assetURL, NSError *error))block{
    
    NSFileManager* fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:file]) {
        NSError *customError = [[NSError alloc] initWithDomain:@"drone.dji.com" code:DJIAlbumTransferErrorCode_FileNotFound userInfo:nil];
        SAFE_BLOCK(block, nil, customError);
        return;
    }
    
    if(!UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(file)){
        NSError *customError = [[NSError alloc] initWithDomain:@"drone.dji.com" code:DJIAlbumTransferErrorCode_FileCannotPlay userInfo:nil];
        SAFE_BLOCK(block, nil, customError);
        return;
    }
    
    NSURL* fileURL = [NSURL fileURLWithPath:file];
    [DJIAlbumTransfer saveVideoToAssetLibrary:fileURL albumName:nil completionBlock:block];
}


+ (void)saveVideoToAssetLibrary:(NSURL *)url albumName:(NSString * _Nullable)albumName completionBlock:(void(^)(NSURL *assetURL, NSError *error))block
{
    __block NSString *assetIdentifier = nil;
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        PHAssetChangeRequest *request = [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:url];
        assetIdentifier = request.placeholderForCreatedAsset.localIdentifier;
    } completionHandler:^(BOOL success, NSError * _Nullable error) {
        if (error || !success || assetIdentifier.length == 0) {
            NSError *finalError = error;
            if (!finalError) {
                finalError = [[NSError alloc] initWithDomain:@"drone.dji.com" code:DJIAlbumTransferErrorCode_NoDiskSpace userInfo:nil];
            }
            SAFE_BLOCK(block, nil, finalError);
            return;
        }

        NSURL *assetURL = [NSURL URLWithString:[NSString stringWithFormat:@"ph://%@", assetIdentifier]];
        if (albumName.length == 0) {
            SAFE_BLOCK(block, assetURL, nil);
            return;
        }

        [self addAssetWithIdentifier:assetIdentifier toAlbum:albumName completionBlock:^(NSError *albumError) {
            if (block) {
                block(albumError ? nil : assetURL, albumError);
            }
        }];
    }];
}

+ (void)addAssetWithIdentifier:(NSString *)assetIdentifier toAlbum:(NSString *)album completionBlock:(void(^)(NSError *error))block
{
    PHAssetCollection *collection = [self findOrCreateAssetsCollectionWithGroupName:album];
    if (!collection) {
        NSError *error = [NSError errorWithDomain:@"com.dji.drone" code:DJIAlbumTransferErrorCode_AlbumCanNotCreate userInfo:nil];
        SAFE_BLOCK(block, error);
        return;
    }

    PHFetchResult<PHAsset *> *assets = [PHAsset fetchAssetsWithLocalIdentifiers:@[assetIdentifier] options:nil];
    PHAsset *asset = assets.firstObject;
    if (!asset) {
        NSError *error = [NSError errorWithDomain:@"com.dji.drone" code:DJIAlbumTransferErrorCode_Unknown userInfo:nil];
        SAFE_BLOCK(block, error);
        return;
    }

    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        PHAssetCollectionChangeRequest *collectionChangeRequest = [PHAssetCollectionChangeRequest changeRequestForAssetCollection:collection];
        [collectionChangeRequest addAssets:@[asset]];
    } completionHandler:^(BOOL success, NSError * _Nullable error) {
        if (error || !success) {
            SAFE_BLOCK(block, error ?: [NSError errorWithDomain:@"com.dji.drone" code:DJIAlbumTransferErrorCode_Unknown userInfo:nil]);
            return;
        }

        SAFE_BLOCK(block, nil);
    }];
}

+ (PHAssetCollection *)findOrCreateAssetsCollectionWithGroupName:(NSString *)groupName
{
    PHFetchResult<PHAssetCollection *> *collections = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAlbumRegular options:nil];
    for (PHAssetCollection *collection in collections) {
        if ([collection.localizedTitle isEqualToString:groupName]) {
            return collection;
        }
    }

    NSError *error = nil;
    __block NSString *collectionIdentifier = nil;
    [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        PHAssetCollectionChangeRequest *request = [PHAssetCollectionChangeRequest creationRequestForAssetCollectionWithTitle:groupName];
        collectionIdentifier = request.placeholderForCreatedAssetCollection.localIdentifier;
    } error:&error];

    if (error || collectionIdentifier.length == 0) {
        return nil;
    }

    return [PHAssetCollection fetchAssetCollectionsWithLocalIdentifiers:@[collectionIdentifier] options:nil].firstObject;
}

+(void) createAlbumIfNotExist:(NSString *)album{
    [self findOrCreateAssetsCollectionWithGroupName:album];
}

@end
