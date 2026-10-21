import 'package:go_router/go_router.dart';

import '../features/documents/presentation/pages/document_detail_page.dart';
import '../features/documents/presentation/pages/home_page.dart';
import '../features/documents/presentation/pages/review_page.dart';
import '../features/scanner/presentation/pages/camera_page.dart';
import '../features/scanner/presentation/pages/crop_page.dart';
import '../features/scanner/presentation/pages/enhance_page.dart';
import '../features/settings/presentation/paywall_page.dart';
import 'router_observer.dart';

/// Scan sub-routes are nested under `/scan` so `pop()` from crop/enhance/review returns to the camera.
final GoRouter appRouter = GoRouter(
  observers: [routeObserver],
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => const HomePage(),
      routes: [
        GoRoute(
          path: 'document/:id',
          builder: (_, state) => DocumentDetailPage(documentId: state.pathParameters['id']!),
        ),
        GoRoute(path: 'paywall', builder: (_, _) => const PaywallPage()),
      ],
    ),
    GoRoute(
      path: '/scan',
      builder: (_, _) => const CameraPage(),
      routes: [
        GoRoute(path: 'crop', builder: (_, _) => const CropPage()),
        GoRoute(path: 'enhance', builder: (_, _) => const EnhancePage()),
        GoRoute(path: 'review', builder: (_, _) => const ReviewPage()),
      ],
    ),
  ],
);
