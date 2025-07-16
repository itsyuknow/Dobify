import 'package:flutter/material.dart';
import '/widgets/colors.dart';
import '../data/mock_data.dart';

class CategoryCarousel extends StatelessWidget {
  final String selectedCategory;
  final Function(String) onCategorySelected;

  const CategoryCarousel({
    super.key,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: categoryList.length,
        itemBuilder: (context, index) {
          final category = categoryList[index];
          final isSelected = selectedCategory == category;

          return GestureDetector(
            onTap: () => onCategorySelected(category),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 6),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? kPrimaryColor : Colors.transparent,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: kPrimaryColor),
                boxShadow: isSelected
                    ? [
                  BoxShadow(
                    color: kPrimaryColor.withOpacity(0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  )
                ]
                    : [],
              ),
              child: Text(
                category,
                style: TextStyle(
                  color: isSelected ? Colors.white : kPrimaryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
