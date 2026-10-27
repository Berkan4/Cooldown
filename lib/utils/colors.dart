import 'package:flutter/material.dart';

/// Text/icon colour that stays readable on [background]: white, or near-black
/// for very light colours (a custom colour can be almost white).
Color foregroundOn(Color background) =>
    background.computeLuminance() > 0.6 ? const Color(0xDD000000) : Colors.white;
