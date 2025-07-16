import 'package:flutter/material.dart';

class CategorySelector extends StatelessWidget {
  final List<String> categories;
  final String selectedCategory;
  final Function(String) onCategorySelected;

  const CategorySelector({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final category = categories[index];
          final isSelected = category == selectedCategory;

          return GestureDetector(
            onTap: () => onCategorySelected(category),
            child: isSelected
                ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                category,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
                : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  category,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: 3,
                  width: 20,
                  color: Colors.green,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
