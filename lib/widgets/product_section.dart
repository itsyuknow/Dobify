import 'package:flutter/material.dart';
import '/widgets/colors.dart';
import '../data/mock_data.dart';

class ProductSection extends StatelessWidget {
  final String category;

  const ProductSection({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    final products = mockProductData[category] ?? [];

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        return Card(
          elevation: 3,
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: Image.asset(
              product['image'],
              height: 60,
              width: 60,
              fit: BoxFit.cover,
            ),
            title: Text(product['name']),
            subtitle: Text('₹${product['price']}'),
            trailing: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Add'),
            ),
          ),
        );
      },
    );
  }
}
