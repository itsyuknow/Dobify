import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'colors.dart';

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> orders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchOrders();
  }

  Future<void> _fetchOrders() async {
    setState(() => _loading = true);
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final List data = await supabase
          .from('orders')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      setState(() {
        orders = data.map((e) => Map<String, dynamic>.from(e)).toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint("Order Fetch Error: $e");
      setState(() {
        orders = [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Orders"),
        backgroundColor: kPrimaryColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : orders.isEmpty
          ? const Center(child: Text("No orders placed yet."))
          : ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: orders.length,
        itemBuilder: (context, i) {
          final order = orders[i];
          final address = order['delivery_address'] ?? {};
          final total = order['total'] ?? 0;
          final status = order['status'] ?? "Unknown";
          final date = order['created_at']?.toString().substring(0, 10) ?? "";

          return Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.symmetric(vertical: 8),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Order #${order['id']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text("📍 ${address['address_line'] ?? 'No Address'}"),
                  Text("📅 $date"),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Total: ₹${total.toStringAsFixed(2)}",
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Chip(
                        label: Text(status,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        backgroundColor: status == 'Placed'
                            ? Colors.green
                            : status == 'Cancelled'
                            ? Colors.red
                            : Colors.grey,
                      )
                    ],
                  )
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
