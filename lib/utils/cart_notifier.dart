import 'package:flutter/material.dart';

class CartCountNotifier extends ValueNotifier<int> {
  CartCountNotifier() : super(0);
}

final cartCountNotifier = CartCountNotifier();
