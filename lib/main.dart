import 'package:flutter/material.dart';

import 'app_identity.dart';
import 'app_globals.dart';
import 'data/app_database.dart';
import 'data/card_repository.dart';
import 'data/image_store.dart';
import 'data/subject_cache.dart';
import 'features/home/home_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  imageStore = await ImageStore.forApp();
  cardRepository = CardRepository(AppDatabase(), imageStore);
  subjectCache = SubjectCache(cardRepository);

  // 启动时顺手清一次过期的回收站记录。
  await cardRepository.purgeExpired(now: DateTime.now());

  runApp(const BaibaoxiangApp());
}

class BaibaoxiangApp extends StatelessWidget {
  const BaibaoxiangApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppIdentity.displayName,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
