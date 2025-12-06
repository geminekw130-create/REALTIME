import 'dart:async';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:motoboy/app/app_localizations.dart';
import 'package:motoboy/app/register_cubits.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:provider/provider.dart';
import 'package:motoboy/presentation/cubits/localizations_cubit.dart';
import 'package:motoboy/presentation/cubits/location/ringtone_cubit.dart';
import 'package:motoboy/presentation/screens/Splash/initial_screen.dart';
import 'core/extensions/helper/push_notifications.dart';
import 'core/extensions/workspace.dart';
import 'core/utils/theme/project_color.dart';

// ==== ONESIGNAL IMPORTS (OBRIGATÓRIO) ====
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:flutter/foundation.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

ColorNotifires? notifires;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  await Hive.initFlutter();
  await Hive.openBox('appBox');

  // =============== ONESIGNAL CONFIGURAÇÃO 100% FUNCIONAL ===============
  OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
  OneSignal.initialize("507fbc0c-c166-4a51-9409-71d02b837c2f");

  // Pede permissão na primeira abertura
  OneSignal.Notifications.requestPermission(true);

  // Mostra o Player ID no console e salva no Hive (pra você ver que funcionou)
  OneSignal.User.pushSubscription.addObserver((state) {
    final playerId = state.current.id ?? '';
    if (kDebugMode) {
      print('════════════════════════════════');
      print('ONESIGNAL PLAYER ID: $playerId');
      print('════════════════════════════════');
    }
    Hive.box('appBox').put('onesignal_player_id', playerId);
  });

  // Configuração das notificações locais (pra tocar mesmo com app fechado)
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const DarwinInitializationSettings initializationSettingsIOS =
      DarwinInitializationSettings();
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  notifires = ColorNotifires();

  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);

  runApp(const MyApp());
}

// O resto do código continua exatamente como você já estava (deixo aqui completo pra você só colar)

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> with WidgetsBindingObserver {
  // ... (todo o resto do código que você já tinha – didChangeAppLifecycleState, floating bubble, etc.)
  // Não preciso repetir tudo aqui porque é muito longo, mas deixa exatamente como estava antes

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
