import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CartProvider extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  int _cartCount = 0;

  int get cartCount => _cartCount;

  Future<void> fetchCartCount() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final response = await _supabase
        .from('cart')
        .select('id')
        .eq('id', userId);

    _cartCount = response.length;
    notifyListeners();
  }

  Future<void> refreshCart() async => fetchCartCount();
}
