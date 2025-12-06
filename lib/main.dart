import 'dart:async';
import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'app/app_localizations.dart';
import 'app/register_cubits.dart';
import 'core/extensions/helper/push_notifications.dart';
import 'core/extensions/workspace.dart';
import 'core/utils/theme/project_color.dart';
import 'presentation/cubits/localizations_cubit.dart';
import 'presentation/cubits/location/ringtone_cubit.dart';
import 'presentation/screens/Splash/initial_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase
  await Firebase.initializeApp();

  // Hive
  await Hive.initFlutter();
  await Hive.openBox('appBox');

  // =============== ONESIGNAL 100% FUNCIONANDO ===============
  OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
  OneSignal.initialize("507fbc0c-c166-4a51-9409-71d02b837c2f");

  // Pede permissão de notificação na primeira vez
  OneSignal.Notifications.requestPermission(true);

  // Salva o Player ID no Hive e mostra no console
  OneSignal.User.pushSubscription.addObserver((state) {
    final playerId = state.current.id ?? '';
    if (kDebugMode) {
      print('════════════════════════════════════════');
      print('ONESIGNAL PLAYER ID: $playerId');
      print('════════════════════════════════════════');
    }
    Hive.box('appBox').put('onesignal_player_id', playerId);
  });

  // Notificações locais (já existe no projeto, só inicializa)
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const DarwinInitializationSettings iosSettings = DarwinInitializationSettings();
  const InitializationSettings initSettings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
  );
  await flutterLocalNotificationsPlugin.initialize(initSettings);

  // Tema
  notifires = ColorNotifires();

  // Firestore
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  static const platform = MethodChannel('com.tochegando.motoboy/floating_bubble');
  StreamSubscription<Position>? positionStreamSubscription;
  DateTime? lastUpdateTime;

  @override
  void initState() {
    super.initState();
    if (Platform.isIOS) {
      configureAudioSessionAndPermissions();
    }
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    positionStreamSubscription?.cancel();
    RingtoneHelper().stopRingtone();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    final appBox = Hive.box('appBox');
    final bool? driverStatus = appBox.get('driver_status');
    final String? driverId = appBox.get('driverId');

    if (driverStatus != true || driverId == null || driverId.isEmpty) return;

    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      if (Platform.isAndroid) {
        await _requestLocationPermissions();
        await _showFloatingBubble();

        positionStreamSubscription = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0,
          ),
        ).listen((Position position) async {
          await _updateDriverLocation(position, driverId);
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      if (Platform.isAndroid) await _hideFloatingBubble();
      positionStreamSubscription?.cancel();
    }
  }

  Future<void> _updateDriverLocation(Position position, String driverId) async {
    final now = DateTime.now();
    final int duration = int.parse(Hive.box('appBox').get("backgroundUpdatedLocation") ?? "10");

    if (lastUpdateTime != null && now.difference(lastUpdateTime!).inSeconds < duration) return;

    lastUpdateTime = now;

    try {
      final geoPoint = GeoFirePoint(GeoPoint(position.latitude, position.longitude));

      await FirebaseFirestore.instance.collection('drivers').doc(driverId).update({
        'geo': geoPoint.data,
        'timestamp': DateTime.now(),
      });

      // Atualiza localização no Realtime Database se tiver corrida ativa
      final doc = await FirebaseFirestore.instance.collection('drivers').doc(driverId).get();
      final data = doc.data();
      if (data != null && data['ride_request'] != null && (data['ride_request'] as Map).isNotEmpty) {
        final rideId = (data['ride_request'] as Map)['rideId'];
        await FirebaseDatabase.instance.ref().child('ride_requests').child(rideId).child('driverLocation').update({
          'lat': position.latitude,
          'lng': position.longitude,
        });
      }
    } catch (e) {
      BotToast.showText(text: "Erro ao atualizar localização: $e");
    }
  }

  Future<void> _requestLocationPermissions() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (Platform.isAndroid && await Permission.locationAlways.isDenied) {
      await Permission.locationAlways.request();
    }
  }

  Future<void> _showFloatingBubble() async {
    try {
      await platform.invokeMethod('showBubble');
    } catch (_) {}
  }

  Future<void> _hideFloatingBubble() async {
    try {
      await platform.invokeMethod('hideBubble');
    } catch (_) {}
  }

  Future<void> configureAudioSessionAndPermissions() async {
    try {
      await platform.invokeMethod('setupAudioSession');
      await platform.invokeMethod('requestMicrophonePermission');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [...RegisterCubits().providers],
      child: ChangeNotifierProvider.value(
        value: notifires!,
        child: ScreenUtilInit(
          designSize: const Size(375, 812),
          minTextAdapt: true,
          splitScreenMode: true,
          builder: (context, child) {
            return MaterialApp(
              builder: BotToastInit(),
              navigatorObservers: [BotToastNavigatorObserver()],
              navigatorKey: navigatorKey,
              theme: ThemeData(fontFamily: 'Gilroy Regular'),
              debugShowCheckedModeBanner: false,
              locale: const Locale('pt', 'BR'),
              supportedLocales: const [Locale('pt', 'BR')],
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: const InitialScreen(),
            );
          },
        ),
      ),
    );
  }
}
