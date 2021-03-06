#import <Mapbox/Mapbox.h>

#import "NSBundle+MGLAdditions.h"

#import <mbgl/util/default_styles.hpp>

#import <XCTest/XCTest.h>
#if TARGET_OS_IPHONE
    #import <UIKit/UIKit.h>
#else
    #import <Cocoa/Cocoa.h>
#endif
#import <objc/runtime.h>

@interface MGLStyleTests : XCTestCase <MGLMapViewDelegate>

@property (nonatomic) MGLMapView *mapView;
@property (nonatomic) MGLStyle *style;

@end

@implementation MGLStyleTests {
    XCTestExpectation *_styleLoadingExpectation;
}

- (void)setUp {
    [super setUp];

    [MGLAccountManager setAccessToken:@"pk.feedcafedeadbeefbadebede"];
    NSURL *styleURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"one-liner" withExtension:@"json"];
    self.mapView = [[MGLMapView alloc] initWithFrame:CGRectMake(0, 0, 100, 100) styleURL:styleURL];
    self.mapView.delegate = self;
    if (!self.mapView.style) {
        _styleLoadingExpectation = [self expectationWithDescription:@"Map view should finish loading style."];
        [self waitForExpectationsWithTimeout:1 handler:nil];
    }
}

- (void)mapView:(MGLMapView *)mapView didFinishLoadingStyle:(MGLStyle *)style {
    XCTAssertNotNil(mapView.style);
    XCTAssertEqual(mapView.style, style);

    [_styleLoadingExpectation fulfill];
}

- (void)tearDown {
    _styleLoadingExpectation = nil;
    self.mapView = nil;

    [super tearDown];
}

- (MGLStyle *)style {
    return self.mapView.style;
}

- (void)testUnversionedStyleURLs {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    XCTAssertEqualObjects([MGLStyle streetsStyleURL].absoluteString, @"mapbox://styles/mapbox/streets-v8");
    XCTAssertEqualObjects([MGLStyle emeraldStyleURL].absoluteString, @"mapbox://styles/mapbox/emerald-v8");
    XCTAssertEqualObjects([MGLStyle lightStyleURL].absoluteString, @"mapbox://styles/mapbox/light-v8");
    XCTAssertEqualObjects([MGLStyle darkStyleURL].absoluteString, @"mapbox://styles/mapbox/dark-v8");
    XCTAssertEqualObjects([MGLStyle satelliteStyleURL].absoluteString, @"mapbox://styles/mapbox/satellite-v8");
    XCTAssertEqualObjects([MGLStyle hybridStyleURL].absoluteString, @"mapbox://styles/mapbox/satellite-hybrid-v8");
#pragma clang diagnostic pop
}

- (void)testVersionedStyleURLs {
    // Test that all the default styles have publicly-declared MGLStyle class
    // methods and that the URLs all have the right values.
    XCTAssertEqualObjects([MGLStyle streetsStyleURLWithVersion:MGLStyleDefaultVersion].absoluteString, @(mbgl::util::default_styles::streets.url));
    XCTAssertEqualObjects([MGLStyle streetsStyleURLWithVersion:99].absoluteString, @"mapbox://styles/mapbox/streets-v99");
    XCTAssertEqualObjects([MGLStyle outdoorsStyleURLWithVersion:MGLStyleDefaultVersion].absoluteString, @(mbgl::util::default_styles::outdoors.url));
    XCTAssertEqualObjects([MGLStyle outdoorsStyleURLWithVersion:99].absoluteString, @"mapbox://styles/mapbox/outdoors-v99");
    XCTAssertEqualObjects([MGLStyle lightStyleURLWithVersion:MGLStyleDefaultVersion].absoluteString, @(mbgl::util::default_styles::light.url));
    XCTAssertEqualObjects([MGLStyle lightStyleURLWithVersion:99].absoluteString, @"mapbox://styles/mapbox/light-v99");
    XCTAssertEqualObjects([MGLStyle darkStyleURLWithVersion:MGLStyleDefaultVersion].absoluteString, @(mbgl::util::default_styles::dark.url));
    XCTAssertEqualObjects([MGLStyle darkStyleURLWithVersion:99].absoluteString, @"mapbox://styles/mapbox/dark-v99");
    XCTAssertEqualObjects([MGLStyle satelliteStyleURLWithVersion:MGLStyleDefaultVersion].absoluteString, @(mbgl::util::default_styles::satellite.url));
    XCTAssertEqualObjects([MGLStyle satelliteStyleURLWithVersion:99].absoluteString, @"mapbox://styles/mapbox/satellite-v99");
    XCTAssertEqualObjects([MGLStyle satelliteStreetsStyleURLWithVersion:MGLStyleDefaultVersion].absoluteString, @(mbgl::util::default_styles::satelliteStreets.url));
    XCTAssertEqualObjects([MGLStyle satelliteStreetsStyleURLWithVersion:99].absoluteString, @"mapbox://styles/mapbox/satellite-streets-v99");

    static_assert(6 == mbgl::util::default_styles::numOrderedStyles,
                  "MGLStyleTests isn’t testing all the styles in mbgl::util::default_styles.");
}

- (void)testStyleURLDeclarations {
    // Make sure this test is comprehensive.
    const unsigned numImplicitArgs = 2 /* _cmd, self */;
    unsigned numMethods = 0;
    Method *methods = class_copyMethodList(object_getClass([MGLStyle class]), &numMethods);
    unsigned numVersionedMethods = 0;
    for (NSUInteger i = 0; i < numMethods; i++) {
        Method method = methods[i];
        SEL selector = method_getName(method);
        NSString *name = @(sel_getName(selector));
        unsigned numArgs = method_getNumberOfArguments(method);
        if ([name hasSuffix:@"StyleURL"]) {
            XCTAssertEqual(numArgs, numImplicitArgs, @"Unversioned style URL method should have no parameters, but it has %u.", numArgs - numImplicitArgs);
        } else if ([name hasSuffix:@"StyleURLWithVersion:"]) {
            XCTAssertEqual(numArgs, numImplicitArgs + 1, @"Versioned style URL method should have one parameter, but it has %u.", numArgs - numImplicitArgs);
            numVersionedMethods++;
        } else {
            XCTAssertEqual([name rangeOfString:@"URL"].location, NSNotFound, @"MGLStyle style URL method %@ is malformed.", name);
        }
    }
    XCTAssertEqual(mbgl::util::default_styles::numOrderedStyles, numVersionedMethods,
                   @"There are %lu default styles but MGLStyleTests only provides versioned style URL methods for %u of them.",
                   mbgl::util::default_styles::numOrderedStyles, numVersionedMethods);

    // Test that all the versioned style methods are in the public header.
    NSString *styleHeader = self.stringWithContentsOfStyleHeader;

    NSError *versionedMethodError;
    NSString *versionedMethodExpressionString = @(R"RE(^\+\s*\(NSURL\s*\*\s*\)\s*\w+StyleURLWithVersion\s*:\s*\(\s*NSInteger\s*\)\s*version\s*;)RE");
    NSRegularExpression *versionedMethodExpression = [NSRegularExpression regularExpressionWithPattern:versionedMethodExpressionString options:NSRegularExpressionAnchorsMatchLines error:&versionedMethodError];
    XCTAssertNil(versionedMethodError, @"Error compiling regular expression to search for versioned methods.");
    NSUInteger numVersionedMethodDeclarations = [versionedMethodExpression numberOfMatchesInString:styleHeader options:0 range:NSMakeRange(0, styleHeader.length)];
    XCTAssertEqual(numVersionedMethodDeclarations, numVersionedMethods);

    // Test that “current version is” statements are present and current for all versioned style methods.
    NSError *versionError;
    NSString *versionExpressionString = @(R"RE(current version is `(\d+)`)RE");
    NSRegularExpression *versionExpression = [NSRegularExpression regularExpressionWithPattern:versionExpressionString options:0 error:&versionError];
    XCTAssertNil(versionError, @"Error compiling regular expression to search for current version statements.");
    NSUInteger numVersionDeclarations = [versionExpression numberOfMatchesInString:styleHeader options:0 range:NSMakeRange(0, styleHeader.length)];
    XCTAssertEqual(numVersionDeclarations, numVersionedMethods);
    [versionExpression enumerateMatchesInString:styleHeader options:0 range:NSMakeRange(0, styleHeader.length) usingBlock:^(NSTextCheckingResult * _Nullable result, NSMatchingFlags flags, BOOL * _Nonnull stop) {
        XCTAssertEqual(result.numberOfRanges, 2, @"Regular expression should have one capture group.");
        NSString *version = [styleHeader substringWithRange:[result rangeAtIndex:1]];
        XCTAssertEqual([version integerValue], MGLStyleDefaultVersion, @"Versioned style URL method should document current version as %ld, not %ld.", MGLStyleDefaultVersion, version.integerValue);
    }];
}

- (void)testName {
    XCTAssertNil(self.style.name);
}

- (void)testSources {
    NSSet<MGLSource *> *initialSources = self.style.sources;
    if ([initialSources.anyObject.identifier isEqualToString:@"com.mapbox.annotations"]) {
        XCTAssertEqual(self.style.sources.count, 1);
    } else {
        XCTAssertEqual(self.style.sources.count, 0);
    }
    MGLShapeSource *shapeSource = [[MGLShapeSource alloc] initWithIdentifier:@"shapeSource" shape:nil options:nil];
    [self.style addSource:shapeSource];
    XCTAssertEqual(self.style.sources.count, initialSources.count + 1);
    [self.style removeSource:shapeSource];
    XCTAssertEqual(self.style.sources.count, initialSources.count);
}

- (void)testAddingSourcesTwice {
    MGLShapeSource *shapeSource = [[MGLShapeSource alloc] initWithIdentifier:@"shapeSource" shape:nil options:nil];
    [self.style addSource:shapeSource];
    XCTAssertThrowsSpecificNamed([self.style addSource:shapeSource], NSException, @"MGLRedundantSourceException");

    MGLRasterSource *rasterSource = [[MGLRasterSource alloc] initWithIdentifier:@"rasterSource" configurationURL:[NSURL URLWithString:@".json"] tileSize:42];
    [self.style addSource:rasterSource];
    XCTAssertThrowsSpecificNamed([self.style addSource:rasterSource], NSException, @"MGLRedundantSourceException");

    MGLVectorSource *vectorSource = [[MGLVectorSource alloc] initWithIdentifier:@"vectorSource" configurationURL:[NSURL URLWithString:@".json"]];
    [self.style addSource:vectorSource];
    XCTAssertThrowsSpecificNamed([self.style addSource:vectorSource], NSException, @"MGLRedundantSourceException");
}

- (void)testAddingSourcesWithDuplicateIdentifiers {
    MGLVectorSource *source1 = [[MGLVectorSource alloc] initWithIdentifier:@"my-source" configurationURL:[NSURL URLWithString:@"mapbox://mapbox.mapbox-terrain-v2"]];
    MGLVectorSource *source2 = [[MGLVectorSource alloc] initWithIdentifier:@"my-source" configurationURL:[NSURL URLWithString:@"mapbox://mapbox.mapbox-terrain-v2"]];

    [self.style addSource: source1];
    XCTAssertThrowsSpecificNamed([self.style addSource: source2], NSException, @"MGLRedundantSourceIdentifierException");
}

- (void)testRemovingSourcesBeforeAddingThem {
    MGLRasterSource *rasterSource = [[MGLRasterSource alloc] initWithIdentifier:@"raster-source" tileURLTemplates:@[] options:nil];
    [self.style removeSource:rasterSource];
    [self.style addSource:rasterSource];
    XCTAssertNotNil([self.style sourceWithIdentifier:rasterSource.identifier]);

    MGLShapeSource *shapeSource = [[MGLShapeSource alloc] initWithIdentifier:@"shape-source" shape:nil options:nil];
    [self.style removeSource:shapeSource];
    [self.style addSource:shapeSource];
    XCTAssertNotNil([self.style sourceWithIdentifier:shapeSource.identifier]);

    MGLVectorSource *vectorSource = [[MGLVectorSource alloc] initWithIdentifier:@"vector-source" tileURLTemplates:@[] options:nil];
    [self.style removeSource:vectorSource];
    [self.style addSource:vectorSource];
    XCTAssertNotNil([self.style sourceWithIdentifier:vectorSource.identifier]);
}

- (void)testAddingSourceOfTypeABeforeSourceOfTypeBWithSameIdentifier {
    // Add a raster source
    MGLRasterSource *rasterSource = [[MGLRasterSource alloc] initWithIdentifier:@"some-identifier" tileURLTemplates:@[] options:nil];
    [self.style addSource:rasterSource];

    // Attempt to remove a shape source with the same identifier as the raster source
    MGLShapeSource *shapeSource = [[MGLShapeSource alloc] initWithIdentifier:@"some-identifier" shape:nil options:nil];
    [self.style removeSource:shapeSource];
    // The raster source should still be added
    XCTAssertTrue([[self.style sourceWithIdentifier:rasterSource.identifier] isMemberOfClass:[MGLRasterSource class]]);

    // Remove the raster source
    [self.style removeSource:rasterSource];

    // Add the shape source
    [self.style addSource:shapeSource];

    // Attempt to remove a vector source with the same identifer as the shape source
    MGLVectorSource *vectorSource = [[MGLVectorSource alloc] initWithIdentifier:@"some-identifier" tileURLTemplates:@[] options:nil];
    [self.style removeSource:vectorSource];
    // The shape source should still be added
    XCTAssertTrue([[self.style sourceWithIdentifier:shapeSource.identifier] isMemberOfClass:[MGLShapeSource class]]);

    // Remove the shape source
    [self.style removeSource:shapeSource];

    // Add the vector source
    [self.style addSource:vectorSource];

    // Attempt to remove the previously created raster source that has the same identifer as the shape source
    [self.style removeSource:rasterSource];
    // The vector source should still be added
    XCTAssertTrue([[self.style sourceWithIdentifier:shapeSource.identifier] isMemberOfClass:[MGLVectorSource class]]);
}

- (void)testLayers {
    NSArray<MGLStyleLayer *> *initialLayers = self.style.layers;
    if ([initialLayers.firstObject.identifier isEqualToString:@"com.mapbox.annotations.points"]) {
        XCTAssertEqual(self.style.layers.count, 1);
    } else {
        XCTAssertEqual(self.style.layers.count, 0);
    }
    MGLShapeSource *shapeSource = [[MGLShapeSource alloc] initWithIdentifier:@"shapeSource" shape:nil options:nil];
    [self.style addSource:shapeSource];
    MGLFillStyleLayer *fillLayer = [[MGLFillStyleLayer alloc] initWithIdentifier:@"fillLayer" source:shapeSource];
    [self.style addLayer:fillLayer];
    XCTAssertEqual(self.style.layers.count, initialLayers.count + 1);
    [self.style removeLayer:fillLayer];
    XCTAssertEqual(self.style.layers.count, initialLayers.count);
}

- (void)testAddingLayersTwice {
    MGLShapeSource *source = [[MGLShapeSource alloc] initWithIdentifier:@"shapeSource" shape:nil options:nil];

    MGLBackgroundStyleLayer *backgroundLayer = [[MGLBackgroundStyleLayer alloc] initWithIdentifier:@"backgroundLayer"];
    [self.style addLayer:backgroundLayer];
    XCTAssertThrowsSpecificNamed([self.style addLayer:backgroundLayer], NSException, @"MGLRedundantLayerException");

    MGLCircleStyleLayer *circleLayer = [[MGLCircleStyleLayer alloc] initWithIdentifier:@"circleLayer" source:source];
    [self.style addLayer:circleLayer];
    XCTAssertThrowsSpecificNamed([self.style addLayer:circleLayer], NSException, @"MGLRedundantLayerException");

    MGLFillStyleLayer *fillLayer = [[MGLFillStyleLayer alloc] initWithIdentifier:@"fillLayer" source:source];
    [self.style addLayer:fillLayer];
    XCTAssertThrowsSpecificNamed([self.style addLayer:fillLayer], NSException, @"MGLRedundantLayerException");

    MGLLineStyleLayer *lineLayer = [[MGLLineStyleLayer alloc] initWithIdentifier:@"lineLayer" source:source];
    [self.style addLayer:lineLayer];
    XCTAssertThrowsSpecificNamed([self.style addLayer:lineLayer], NSException, @"MGLRedundantLayerException");

    MGLRasterStyleLayer *rasterLayer = [[MGLRasterStyleLayer alloc] initWithIdentifier:@"rasterLayer" source:source];
    [self.style addLayer:rasterLayer];
    XCTAssertThrowsSpecificNamed([self.style addLayer:rasterLayer], NSException, @"MGLRedundantLayerException");

    MGLSymbolStyleLayer *symbolLayer = [[MGLSymbolStyleLayer alloc] initWithIdentifier:@"symbolLayer" source:source];
    [self.style addLayer:symbolLayer];
    XCTAssertThrowsSpecificNamed([self.style addLayer:symbolLayer], NSException, @"MGLRedundantLayerException");
}

- (void)testAddingLayersWithDuplicateIdentifiers {
    // Just some source
    MGLVectorSource *source = [[MGLVectorSource alloc] initWithIdentifier:@"my-source" configurationURL:[NSURL URLWithString:@"mapbox://mapbox.mapbox-terrain-v2"]];
    [self.style addSource: source];

    // Add initial layer
    MGLFillStyleLayer *initial = [[MGLFillStyleLayer alloc] initWithIdentifier:@"my-layer" source:source];
    [self.style addLayer:initial];

    // Try to add the duplicate
    XCTAssertThrowsSpecificNamed([self.style addLayer:[[MGLFillStyleLayer alloc] initWithIdentifier:@"my-layer" source:source]], NSException, @"MGLRedundantLayerIdentifierException");
    XCTAssertThrowsSpecificNamed([self.style insertLayer:[[MGLFillStyleLayer alloc] initWithIdentifier:@"my-layer" source:source] belowLayer:initial],NSException, @"MGLRedundantLayerIdentifierException");
    XCTAssertThrowsSpecificNamed([self.style insertLayer:[[MGLFillStyleLayer alloc] initWithIdentifier:@"my-layer" source:source] aboveLayer:initial], NSException, @"MGLRedundantLayerIdentifierException");
    XCTAssertThrowsSpecificNamed([self.style insertLayer:[[MGLFillStyleLayer alloc] initWithIdentifier:@"my-layer" source:source] atIndex:0], NSException, @"MGLRedundantLayerIdentifierException");
    XCTAssertThrowsSpecificNamed([self.style insertLayer:[[MGLOpenGLStyleLayer alloc] initWithIdentifier:@"my-layer"] atIndex:0], NSException, @"MGLRedundantLayerIdentifierException");
}

- (void)testRemovingLayerBeforeAddingSameLayer {
    MGLShapeSource *source = [[MGLShapeSource alloc] initWithIdentifier:@"shape-source-removing-before-adding" shape:nil options:nil];

    // Attempting to find a layer with identifier will trigger an exception if the source associated with the layer is not added
    [self.style addSource:source];

    MGLFillStyleLayer *fillLayer = [[MGLFillStyleLayer alloc] initWithIdentifier:@"fill-layer" source:source];
    [self.style removeLayer:fillLayer];
    [self.style addLayer:fillLayer];
    XCTAssertNotNil([self.style layerWithIdentifier:fillLayer.identifier]);

    MGLRasterStyleLayer *rasterLayer = [[MGLRasterStyleLayer alloc] initWithIdentifier:@"raster-layer" source:source];
    [self.style removeLayer:rasterLayer];
    [self.style addLayer:rasterLayer];
    XCTAssertNotNil([self.style layerWithIdentifier:rasterLayer.identifier]);

    MGLSymbolStyleLayer *symbolLayer = [[MGLSymbolStyleLayer alloc] initWithIdentifier:@"symbol-layer" source:source];
    [self.style removeLayer:symbolLayer];
    [self.style addLayer:symbolLayer];
    XCTAssertNotNil([self.style layerWithIdentifier:symbolLayer.identifier]);

    MGLLineStyleLayer *lineLayer = [[MGLLineStyleLayer alloc] initWithIdentifier:@"line-layer" source:source];
    [self.style removeLayer:lineLayer];
    [self.style addLayer:lineLayer];
    XCTAssertNotNil([self.style layerWithIdentifier:lineLayer.identifier]);

    MGLCircleStyleLayer *circleLayer = [[MGLCircleStyleLayer alloc] initWithIdentifier:@"circle-layer" source:source];
    [self.style removeLayer:circleLayer];
    [self.style addLayer:circleLayer];
    XCTAssertNotNil([self.style layerWithIdentifier:circleLayer.identifier]);

    MGLBackgroundStyleLayer *backgroundLayer = [[MGLBackgroundStyleLayer alloc] initWithIdentifier:@"background-layer"];
    [self.style removeLayer:backgroundLayer];
    [self.style addLayer:backgroundLayer];
    XCTAssertNotNil([self.style layerWithIdentifier:backgroundLayer.identifier]);
}

- (void)testAddingLayerOfTypeABeforeRemovingLayerOfTypeBWithSameIdentifier {
    MGLShapeSource *source = [[MGLShapeSource alloc] initWithIdentifier:@"shape-source-identifier" shape:nil options:nil];
    [self.style addSource:source];

    // Add a fill layer
    MGLFillStyleLayer *fillLayer = [[MGLFillStyleLayer alloc] initWithIdentifier:@"some-identifier" source:source];
    [self.style addLayer:fillLayer];

    // Attempt to remove a line layer with the same identifier as the fill layer
    MGLLineStyleLayer *lineLayer = [[MGLLineStyleLayer alloc] initWithIdentifier:fillLayer.identifier source:source];
    [self.style removeLayer:lineLayer];

    XCTAssertTrue([[self.style layerWithIdentifier:fillLayer.identifier] isMemberOfClass:[MGLFillStyleLayer class]]);
}

- (NSString *)stringWithContentsOfStyleHeader {
    NSURL *styleHeaderURL = [[[NSBundle mgl_frameworkBundle].bundleURL
                              URLByAppendingPathComponent:@"Headers" isDirectory:YES]
                             URLByAppendingPathComponent:@"MGLStyle.h"];
    NSError *styleHeaderError;
    NSString *styleHeader = [NSString stringWithContentsOfURL:styleHeaderURL usedEncoding:nil error:&styleHeaderError];
    XCTAssertNil(styleHeaderError, @"Error getting contents of MGLStyle.h.");
    return styleHeader;
}

- (void)testClasses {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    XCTAssertEqual(self.style.styleClasses.count, 0);
#pragma clang diagnostic pop
}

- (void)testImages {
    NSString *imageName = @"TrackingLocationMask";
#if TARGET_OS_IPHONE
    MGLImage *image = [MGLImage imageNamed:imageName
                                  inBundle:[NSBundle bundleForClass:[self class]]
             compatibleWithTraitCollection:nil];
#else
    MGLImage *image = [[NSBundle bundleForClass:[self class]] imageForResource:imageName];
#endif
    XCTAssertNotNil(image);

    [self.style setImage:image forName:imageName];
    MGLImage *styleImage = [self.style imageForName:imageName];

    XCTAssertNotNil(styleImage);
    XCTAssertEqual(image.size.width, styleImage.size.width);
    XCTAssertEqual(image.size.height, styleImage.size.height);
}

- (void)testLayersOrder {
    NSString *filePath = [[NSBundle bundleForClass:self.class] pathForResource:@"amsterdam" ofType:@"geojson"];
    NSURL *url = [NSURL fileURLWithPath:filePath];
    MGLShapeSource *source = [[MGLShapeSource alloc] initWithIdentifier:@"sourceID" URL:url options:nil];
    [self.style addSource:source];

    MGLCircleStyleLayer *layer1 = [[MGLCircleStyleLayer alloc] initWithIdentifier:@"layer1" source:source];
    [self.style addLayer:layer1];

    MGLCircleStyleLayer *layer3 = [[MGLCircleStyleLayer alloc] initWithIdentifier:@"layer3" source:source];
    [self.style addLayer:layer3];

    MGLCircleStyleLayer *layer2 = [[MGLCircleStyleLayer alloc] initWithIdentifier:@"layer2" source:source];
    [self.style insertLayer:layer2 aboveLayer:layer1];

    MGLCircleStyleLayer *layer4 = [[MGLCircleStyleLayer alloc] initWithIdentifier:@"layer4" source:source];
    [self.style insertLayer:layer4 aboveLayer:layer3];

    MGLCircleStyleLayer *layer0 = [[MGLCircleStyleLayer alloc] initWithIdentifier:@"layer0" source:source];
    [self.style insertLayer:layer0 belowLayer:layer1];

    NSArray<MGLStyleLayer *> *layers = [self.style layers];
    NSUInteger startIndex = 0;
    if ([layers.firstObject.identifier isEqualToString:@"com.mapbox.annotations.points"]) {
        startIndex++;
    }

    XCTAssertEqualObjects(layers[startIndex++].identifier, layer0.identifier);
    XCTAssertEqualObjects(layers[startIndex++].identifier, layer1.identifier);
    XCTAssertEqualObjects(layers[startIndex++].identifier, layer2.identifier);
    XCTAssertEqualObjects(layers[startIndex++].identifier, layer3.identifier);
    XCTAssertEqualObjects(layers[startIndex++].identifier, layer4.identifier);
}

@end
