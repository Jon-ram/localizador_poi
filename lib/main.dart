import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Localizador de Puntos de Interés',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const MapaPage(),
    );
  }
}

class MapaPage extends StatefulWidget {
  const MapaPage({super.key});

  @override
  State<MapaPage> createState() => _MapaPageState();
}

class _MapaPageState extends State<MapaPage> {
  // UTXJ como posición inicial por si el GPS tarda
  static const LatLng _utxj = LatLng(20.2756, -97.9611);

  GoogleMapController? _mapController;
  StreamSubscription<Position>? _posSub;
  final Geocoding _geocoding = Geocoding();

  final Set<Marker> _marcadores = {};
  Position? _usuario;
  LatLng? _destino;
  double? _metros;
  String _direccion = 'Toca el mapa para elegir un destino';
  String? _error;

  @override
  void initState() {
    super.initState();
    _iniciarUbicacion();
  }

  // ---------- Permisos + ubicación ----------
  Future<Position> _obtenerUbicacion() async {
    final activo = await Geolocator.isLocationServiceEnabled();
    if (!activo) return Future.error('El GPS está desactivado');

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) {
        return Future.error('Permiso de ubicación denegado');
      }
    }
    if (perm == LocationPermission.deniedForever) {
      return Future.error(
        'Permiso denegado permanentemente, actívalo en Ajustes',
      );
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Future<void> _iniciarUbicacion() async {
    try {
      final pos = await _obtenerUbicacion();
      setState(() => _usuario = pos);
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 16),
      );

      // Stream en vivo; distanceFilter evita actualizaciones redundantes
      _posSub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5,
            ),
          ).listen((p) {
            setState(() => _usuario = p);
            _calcularDistancia();
          });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  // ---------- Marcador dinámico ----------
  Future<void> _agregarMarcador(LatLng punto) async {
    setState(() {
      _destino = punto;
      _marcadores
        ..clear()
        ..add(
          Marker(
            markerId: const MarkerId('destino'),
            position: punto,
            infoWindow: const InfoWindow(title: 'Destino'),
          ),
        );
    });
    _calcularDistancia();
    await _obtenerDireccion(punto);
  }

  // ---------- Distancia ----------
  void _calcularDistancia() {
    if (_usuario == null || _destino == null) return;
    final m = Geolocator.distanceBetween(
      _usuario!.latitude,
      _usuario!.longitude,
      _destino!.latitude,
      _destino!.longitude,
    );
    setState(() => _metros = m);
  }

  // ---------- Geocodificación inversa ----------
  Future<void> _obtenerDireccion(LatLng punto) async {
    try {
      final lugares = await _geocoding.placemarkFromCoordinates(
        punto.latitude,
        punto.longitude,
      );
      final p = lugares.first;
      final calle = p.street ?? '';
      final colonia = p.subLocality ?? '';
      setState(() => _direccion = '$calle, $colonia');
    } catch (_) {
      setState(() => _direccion = 'No se pudo obtener la dirección');
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Puntos de Interés')),
      body: Column(
        children: [
          Expanded(
            child: GoogleMap(
              initialCameraPosition: const CameraPosition(
                target: _utxj,
                zoom: 15.5,
              ),
              myLocationEnabled: _usuario != null,
              myLocationButtonEnabled: true,
              markers: _marcadores,
              onMapCreated: (c) {
                _mapController = c;
                if (_usuario != null) {
                  c.animateCamera(
                    CameraUpdate.newLatLngZoom(
                      LatLng(_usuario!.latitude, _usuario!.longitude),
                      16,
                    ),
                  );
                }
              },
              onTap: _agregarMarcador,
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                Text(
                  _usuario == null
                      ? 'Obteniendo ubicación...'
                      : 'Tú: ${_usuario!.latitude.toStringAsFixed(5)}, '
                            '${_usuario!.longitude.toStringAsFixed(5)}',
                ),
                const SizedBox(height: 4),
                Text(
                  _metros == null
                      ? 'Distancia: --'
                      : 'Distancia: ${_metros!.toStringAsFixed(1)} m',
                ),
                const SizedBox(height: 4),
                Text('Dirección: $_direccion'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}