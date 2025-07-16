const List<String> categoryList = [
  'Male',
  'Female',
  'Boys',
  'Girls',
  'Essential',
];

final Map<String, List<Map<String, dynamic>>> mockProductData = {
  'Male': [
    {
      'name': 'Men Shirt',
      'price': 120.0,
      'image': 'assets/images/menshirt.png',
    },
    {
      'name': 'Men Trousers',
      'price': 150.0,
      'image': 'assets/images/trousers.png',
    },
  ],
  'Female': [
    {
      'name': 'Women Saree',
      'price': 180.0,
      'image': 'assets/images/saree.png',
    },
    {
      'name': 'Women Top',
      'price': 130.0,
      'image': 'assets/images/womentop.png',
    },
  ],
  // Add other categories similarly
};
