import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import 'brands.dart';
import 'data.dart';
import 'ui.dart';

/// A merchant's or bank's logo, or its initial on a tile while there's none.
/// Banks pass their [tint]: the initial in that colour on a soft tile instead of a gradient.
class MerchantAvatar extends StatelessWidget {
  const MerchantAvatar(this.name, {super.key, this.size = 40, this.dot, this.tint});
  final String name;
  final double size;
  final Color? dot;
  final Color? tint;
  @override
  Widget build(BuildContext context) {
    final c = nameColor(name, 0.45, 0.52);
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();
    final radius = size * (tint == null ? 0.32 : 0.3);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: [
        LogoTile(
          name,
          size: size,
          radius: radius,
          fallback: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: tint == null
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c, Color.lerp(c, kBg, 0.45)!]),
                  )
                : BoxDecoration(color: tint!.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(radius)),
            child: tint == null
                ? Text(initial, style: TextStyle(fontWeight: FontWeight.w700, fontSize: size * 0.42, color: Colors.white))
                : Text(initial, style: TextStyle(color: tint, fontWeight: FontWeight.w800, fontSize: size * 0.45)),
          ),
        ),
        if (dot != null)
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              width: size * 0.36,
              height: size * 0.36,
              decoration: BoxDecoration(
                color: dot,
                shape: BoxShape.circle,
                border: Border.all(color: kSurface, width: 2),
              ),
            ),
          ),
      ]),
    );
  }
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, this.size = 36});
  final double size;
  @override
  Widget build(BuildContext context) {
    final email = db.auth.currentUser?.email ?? '';
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [kAccent, kBlue])),
      child: email.isEmpty
          ? Icon(CupertinoIcons.person_fill, size: size * 0.55)
          : Text(email[0].toUpperCase(), style: display(size * 0.45, weight: FontWeight.w700)),
    );
  }
}
