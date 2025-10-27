import 'package:flutter/material.dart';

// Responsive scaling utilities
double appScale(BuildContext context) {
  final size = MediaQuery.of(context).size;
  final shortest = size.shortestSide;
  double scale = shortest / 1000;
  return scale.clamp(0.6, 1.8);
}

double sf(BuildContext context, double base) => base * appScale(context);

// Colors
Color teamColor(String team) {
  switch (team.toUpperCase()) {
    case 'BLUE':
      return Colors.blue;
    case 'GREEN':
      return Colors.green;
    case 'RED':
      return Colors.red;
    case 'WHITE':
      return Colors.grey;
    default:
      return Colors.black;
  }
}

Color aquacoulisseColor(String c) => teamColor(c);
