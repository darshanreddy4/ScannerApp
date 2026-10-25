import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/router_observer.dart';
import '../bloc/documents_cubit.dart';

/// Reloads the library whenever a screen opened on top of this one closes.
/// A document may have been saved, renamed or deleted there, and the list must not show old data.
class RefreshOnReturn extends StatefulWidget {
  const RefreshOnReturn({super.key, required this.child});
  final Widget child;

  @override
  State<RefreshOnReturn> createState() => _RefreshOnReturnState();
}

class _RefreshOnReturnState extends State<RefreshOnReturn> with RouteAware {
  ModalRoute<void>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == _route) return;
    if (_route != null) routeObserver.unsubscribe(this);
    _route = route;
    if (route != null) routeObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() => context.read<DocumentsCubit>().load();

  @override
  Widget build(BuildContext context) => widget.child;
}
