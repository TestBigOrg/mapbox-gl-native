package com.mapbox.mapboxsdk.maps;

import android.support.v4.util.LongSparseArray;

import com.mapbox.mapboxsdk.annotations.Annotation;
import com.mapbox.mapboxsdk.annotations.BaseMarkerOptions;
import com.mapbox.mapboxsdk.annotations.Marker;
import com.mapbox.mapboxsdk.annotations.MarkerOptions;
import com.mapbox.mapboxsdk.annotations.MarkerViewManager;
import com.mapbox.mapboxsdk.geometry.LatLng;

import org.junit.Ignore;
import org.junit.Test;

import java.util.ArrayList;
import java.util.List;

import static junit.framework.Assert.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

//TODO Fix failing tests
// Proposed solution: https://github.com/powermock/powermock/wiki/SuppressUnwantedBehavior#suppress-static-initializer
// At the moment PowerMock isn't fully compatible with Mockito2 - https://github.com/powermock/powermock/issues/726
public class AnnotationManagerTest {

  @Ignore
  @Test
  public void checksAddAMarker() throws Exception {
    NativeMapView aNativeMapView = mock(NativeMapView.class);
    MapView aMapView = mock(MapView.class);
    LongSparseArray<Annotation> annotationsArray = new LongSparseArray<>();
    MarkerViewManager aMarkerViewManager = mock(MarkerViewManager.class);
    IconManager aIconManager = mock(IconManager.class);
    Annotations annotations = new AnnotationsFunctions(aNativeMapView, annotationsArray);
    Markers aMarkersManager = new MarkersFunctions(aNativeMapView, aMapView, annotationsArray, aIconManager,
      aMarkerViewManager);
    Polygons aPolygonsManager = new PolygonsFunctions(aNativeMapView, annotationsArray);
    Polylines aPolylinesManager = new PolylinesFunctions(aNativeMapView, annotationsArray);
    AnnotationManager annotationManager = new AnnotationManager(aNativeMapView, aMapView, annotationsArray,
      aMarkerViewManager,
      aIconManager, annotations, aMarkersManager, aPolygonsManager, aPolylinesManager);
    Marker aMarker = mock(Marker.class);
    long aId = 5L;
    when(aNativeMapView.addMarker(aMarker)).thenReturn(aId);
    BaseMarkerOptions aMarkerOptions = mock(BaseMarkerOptions.class);
    MapboxMap aMapboxMap = mock(MapboxMap.class);
    when(aMarkerOptions.getMarker()).thenReturn(aMarker);

    annotationManager.addMarker(aMarkerOptions, aMapboxMap);

    assertEquals(aMarker, annotationManager.getAnnotations().get(0));
    assertEquals(aMarker, annotationManager.getAnnotation(aId));
  }

  @Ignore
  @Test
  public void checksAddMarkers() throws Exception {
    NativeMapView aNativeMapView = mock(NativeMapView.class);
    MapView aMapView = mock(MapView.class);
    LongSparseArray<Annotation> annotationsArray = new LongSparseArray<>();
    MarkerViewManager aMarkerViewManager = mock(MarkerViewManager.class);
    IconManager aIconManager = mock(IconManager.class);
    Annotations annotations = new AnnotationsFunctions(aNativeMapView, annotationsArray);
    Markers aMarkersManager = new MarkersFunctions(aNativeMapView, aMapView, annotationsArray, aIconManager,
      aMarkerViewManager);
    Polygons aPolygonsManager = new PolygonsFunctions(aNativeMapView, annotationsArray);
    Polylines aPolylinesManager = new PolylinesFunctions(aNativeMapView, annotationsArray);
    AnnotationManager annotationManager = new AnnotationManager(aNativeMapView, aMapView, annotationsArray,
      aMarkerViewManager,
      aIconManager, annotations, aMarkersManager, aPolygonsManager, aPolylinesManager);
    long firstId = 1L;
    long secondId = 2L;
    List<BaseMarkerOptions> markerList = new ArrayList<>();
    MarkerOptions firstMarkerOption = new MarkerOptions().position(new LatLng()).title("first");
    MarkerOptions secondMarkerOption = new MarkerOptions().position(new LatLng()).title("second");
    markerList.add(firstMarkerOption);
    markerList.add(secondMarkerOption);
    MapboxMap aMapboxMap = mock(MapboxMap.class);
    when(aNativeMapView.addMarker(any(Marker.class))).thenReturn(firstId, secondId);

    annotationManager.addMarkers(markerList, aMapboxMap);

    assertEquals(2, annotationManager.getAnnotations().size());
    assertEquals("first", ((Marker) annotationManager.getAnnotations().get(0)).getTitle());
    assertEquals("second", ((Marker) annotationManager.getAnnotations().get(1)).getTitle());
    assertEquals("first", ((Marker) annotationManager.getAnnotation(firstId)).getTitle());
    assertEquals("second", ((Marker) annotationManager.getAnnotation(secondId)).getTitle());
  }
}