import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoActivityIndicator;
import 'package:material_ui/material_ui.dart';

import 'pt_theme.dart';

class PTLoader extends StatelessWidget {
  const PTLoader({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CupertinoActivityIndicator(radius: size / 2, color: color ?? PTColors.primary),
    );
  }
}
