import 'dart:async';
import 'dart:convert';
import 'dart:math' show pi;
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';

import 'constants.dart';

class OrderTrackingPage extends StatefulWidget {
  const OrderTrackingPage({Key? key}) : super(key: key);

  @override
  State<OrderTrackingPage> createState() => OrderTrackingPageState();
}

class OrderTrackingPageState extends State<OrderTrackingPage> {
  final Completer<GoogleMapController> _controller = Completer();

  static const LatLng sourceLocation = LatLng(39.753017, 30.492866);
  LatLng destination = LatLng(39.751058, 30.474697);
  LatLng veri = LatLng(0.0, 0.0);
  Set<Polyline> polylines = {};
  List<LatLng> polylineCoordinates = [];
  LocationData? currentLocation;
  bool isLoading = true;
  String errorMessage = '';
  StreamSubscription<LocationData>? _locationSubscription;
  Location location = Location();
  bool followUserLocation = true;
  Timer? timer;
  BitmapDescriptor? customIcon;
  BitmapDescriptor? currentLocationMarker;
  BitmapDescriptor? giris;
  BitmapDescriptor? son;
  void getCurrentLocation() async {
    try {
      currentLocation = await location.getLocation();
      setState(() {
        isLoading = false;
      });
    } catch (error) {
      setState(() {
        isLoading = false;
        errorMessage = 'Failed to fetch current location.';
      });
    }
  }

  Future<void> getPolyPoints() async {
    PolylinePoints polylinePoints = PolylinePoints();

    try {
      PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
        google_api_key,
        PointLatLng(sourceLocation.latitude, sourceLocation.longitude),
        PointLatLng(destination.latitude, destination.longitude),
      );

      if (result.points.isNotEmpty) {
        setState(() {
          polylineCoordinates.clear();
          result.points.forEach((PointLatLng point) {
            polylineCoordinates.add(LatLng(point.latitude, point.longitude));
          });

          polylines.clear();
          polylines.add(
            Polyline(
              polylineId: PolylineId('route'),
              color: Colors.blue,
              width: 5,
              points: polylineCoordinates,
            ),
          );
        });
      }
    } catch (error) {
      setState(() {
        errorMessage = 'Failed to fetch polyline points.';
      });
    }
  }

  Future<void> fetchThingspeakData() async {
    var url = Uri.parse(
        'https://api.thingspeak.com/channels/2136820/feeds.json?api_key=3CEGAXXQSFKUK4VD&results=1');

    var response = await http.get(url);
    if (response.statusCode == 200) {
      var data = json.decode(response.body);
      var feeds = data['feeds'];
      if (feeds.length > 0) {
        var latestFeed = feeds[0];
        var latitude = double.parse(latestFeed['field1']);
        var longitude = double.parse(latestFeed['field2']);

        // Latitude ve longitude değerlerini kullanarak yeni hedef konumunu ayarla
        setState(() {
          veri = LatLng(latitude, longitude);
        });

        // Yeni hedef konumu için polyline ve kamera pozisyonunu güncelle
        await getPolyPoints();
        _updateCameraPosition(latitude, longitude);
      }
    } else {
      setState(() {
        errorMessage = 'Failed to fetch Thingspeak data.';
      });
    }
  }

  @override
  void initState() {
    super.initState();
    getCurrentLocation();
    getPolyPoints();
    fetchThingspeakData();
    _locationSubscription = location.onLocationChanged.listen((newLoc) {
      setState(() {
        currentLocation = newLoc;
      });
      if (_controller.isCompleted && followUserLocation) {
        _updateCameraPosition(newLoc.latitude!, newLoc.longitude!);
      }
    });

    // Veriyi güncellemek için belirli bir süre aralığı belirle
    const refreshInterval = Duration(seconds: 10);

    // Timer ile belirli süre aralığında veriyi güncelle
    timer = Timer.periodic(refreshInterval, (timer) {
      fetchThingspeakData();
    });

    _loadCustomIcon();
  }

  Future<void> _loadCustomIcon() async {
    customIcon = await BitmapDescriptor.fromAssetImage(
      ImageConfiguration(devicePixelRatio: 2.5),
      'images/ic_launcher.png', // Specify the file path of your custom icon
    );
    BitmapDescriptor? loadedCurrentLocationMarker = await BitmapDescriptor.fromAssetImage(
      ImageConfiguration(devicePixelRatio: 2.5),
      'images/konum.png',
    );
    BitmapDescriptor? loadedgiris = await BitmapDescriptor.fromAssetImage(
      ImageConfiguration(devicePixelRatio: 2.5),
      'images/konum1.png',
    );
    BitmapDescriptor? loadedson = await BitmapDescriptor.fromAssetImage(
      ImageConfiguration(devicePixelRatio: 2.5),
      'images/konum1.png',
    );
    setState(() {
      // Update the state with the loaded custom icon
      this.customIcon = customIcon;
      currentLocationMarker = loadedCurrentLocationMarker;
      giris = loadedgiris;
      son = loadedson;
    });
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    timer?.cancel(); // Timer'ı iptal et
    super.dispose();
  }

  void _updateCameraPosition(double latitude, double longitude) async {
    final GoogleMapController controller = await _controller.future;
    controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: LatLng(latitude, longitude), zoom: 17.5),
      ),
    );
  }

  double degreesToRadians(double degrees) {
    return degrees * (pi / 180.0);
  }

  double calculateDistance() {
    if (currentLocation == null) return 0.0;

    double lat1 = degreesToRadians(currentLocation!.latitude!);
    double lon1 = degreesToRadians(currentLocation!.longitude!);
    double lat2 = degreesToRadians(veri.latitude);
    double lon2 = degreesToRadians(veri.longitude);

    double earthRadius = 6371.0; // Earth radius in kilometers

    double dLat = lat2 - lat1;
    double dLon = lon2 - lon1;

    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    double distance = earthRadius * c; // Distance in kilometers

    return distance;
  }

  String calculateEstimatedTime() {
    double distanceInKm = calculateDistance();
    double averageSpeed = 40.0; // Average speed in km/h

    double estimatedTimeInHours = distanceInKm / averageSpeed;
    int estimatedTimeInMinutes = (estimatedTimeInHours * 60).round();

    return '$estimatedTimeInMinutes dakika';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Padding(
          padding: const EdgeInsets.fromLTRB(5, 5, 80, 5),
          child: Center(
            child: Text("ESOGÜ RİNG",
              style: TextStyle(color: Colors.black, fontSize: 16),
            ),
          ),
        ),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : errorMessage.isNotEmpty
          ? Center(child: Text(errorMessage))
          : Column(
        children: [
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: LatLng(
                  currentLocation!.latitude!,
                  currentLocation!.longitude!,
                ),
                zoom: 13.5,
              ),
              polylines: polylines,
              markers: {
                Marker(
                  markerId: const MarkerId("currentLocation"),
                  position: LatLng(
                    currentLocation!.latitude!,
                    currentLocation!.longitude!,
                  ),
                  icon: currentLocationMarker ?? BitmapDescriptor.defaultMarker,
                  infoWindow: InfoWindow(title: 'KONUMUNUZ'),
                ),
                Marker(
                  markerId: const MarkerId("source"),
                  position: sourceLocation,
                  icon: giris ?? BitmapDescriptor.defaultMarker,
                  infoWindow: InfoWindow(title: 'ESOGU GİRİŞ'),
                ),
                Marker(
                  markerId: const MarkerId("destination"),
                  position: destination,
                  icon: son ?? BitmapDescriptor.defaultMarker,
                  infoWindow: InfoWindow(title: 'ESOGU EĞİTİM FAKÜLTESİ'),
                ),
                Marker(
                  markerId: const MarkerId("veri"),
                  position: veri,
                  icon:customIcon ?? BitmapDescriptor.defaultMarker,
                  infoWindow: InfoWindow(title: '01 CSH 57'),
                ),
              },
              onMapCreated: (mapController) {
                _controller.complete(mapController);
                _updateCameraPosition(
                  currentLocation!.latitude!,
                  currentLocation!.longitude!,
                );
              },
              onCameraMove: (position) {
                followUserLocation = false;
              },
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Text(
              'Tahmini Varış Süresi: ${calculateEstimatedTime()}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
