package com.mapbox.mapboxsdk.maps;


import android.support.annotation.NonNull;
import android.support.v4.util.LongSparseArray;

import com.mapbox.mapboxsdk.annotations.Annotation;
import com.mapbox.mapboxsdk.annotations.Polyline;
import com.mapbox.mapboxsdk.annotations.PolylineOptions;

import java.util.ArrayList;
import java.util.List;

class PolylinesFunctions implements Polylines {

  private final NativeMapView nativeMapView;
  private final LongSparseArray<Annotation> annotations;

  PolylinesFunctions(NativeMapView nativeMapView, LongSparseArray<Annotation> annotations) {
    this.nativeMapView = nativeMapView;
    this.annotations = annotations;
  }

  @Override
  public Polyline addBy(@NonNull PolylineOptions polylineOptions, @NonNull MapboxMap mapboxMap) {
    Polyline polyline = polylineOptions.getPolyline();
    if (!polyline.getPoints().isEmpty()) {
      long id = nativeMapView != null ? nativeMapView.addPolyline(polyline) : 0;
      polyline.setMapboxMap(mapboxMap);
      polyline.setId(id);
      annotations.put(id, polyline);
    }
    return polyline;
  }

  @Override
  public List<Polyline> addBy(@NonNull List<PolylineOptions> polylineOptionsList, @NonNull MapboxMap mapboxMap) {
    int count = polylineOptionsList.size();
    Polyline polyline;
    List<Polyline> polylines = new ArrayList<>(count);

    if (count > 0) {
      for (PolylineOptions options : polylineOptionsList) {
        polyline = options.getPolyline();
        if (!polyline.getPoints().isEmpty()) {
          polylines.add(polyline);
        }
      }

      long[] ids = null;
      if (nativeMapView != null) {
        ids = nativeMapView.addPolylines(polylines);
      }

      long id = 0;
      Polyline p;

      for (int i = 0; i < polylines.size(); i++) {
        p = polylines.get(i);
        p.setMapboxMap(mapboxMap);
        if (ids != null) {
          id = ids[i];
        } else {
          // unit test
          id++;
        }
        p.setId(id);
        annotations.put(id, p);
      }
    }
    return polylines;
  }

  @Override
  public void update(Polyline polyline) {
    if (polyline == null) {
      return;
    }

    if (polyline.getId() == -1) {
      return;
    }

    nativeMapView.updatePolyline(polyline);

    int index = annotations.indexOfKey(polyline.getId());
    if (index > -1) {
      annotations.setValueAt(index, polyline);
    }
  }

  @Override
  public List<Polyline> obtainAll() {
    List<Polyline> polylines = new ArrayList<>();
    Annotation annotation;
    for (int i = 0; i < annotations.size(); i++) {
      annotation = annotations.get(annotations.keyAt(i));
      if (annotation instanceof Polyline) {
        polylines.add((Polyline) annotation);
      }
    }
    return polylines;
  }
}
