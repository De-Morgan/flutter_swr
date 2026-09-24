class Rating {
  const Rating({required this.rate, required this.count});

  factory Rating.fromJson(Map<String, dynamic> json) {
    return Rating(
      rate: (json['rate'] as num).toDouble(),
      count: json['count'] as int,
    );
  }

  final double rate;
  final int count;

  Map<String, dynamic> toJson() => {'rate': rate, 'count': count};
}

class Product {
  const Product({
    required this.id,
    required this.title,
    required this.price,
    required this.description,
    required this.category,
    required this.image,
    required this.rating,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as int,
      title: json['title']?.toString() ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      description: json['description']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      image: json['image']?.toString() ?? '',
      rating: json['rating'] == null
          ? const Rating(rate: 0, count: 0)
          : Rating.fromJson(json['rating'] as Map<String, dynamic>),
    );
  }

  final int id;
  final String title;
  final double price;
  final String description;
  final String category;
  final String image;
  final Rating rating;

  Product copyWith({String? title}) {
    return Product(
      id: id,
      title: title ?? this.title,
      price: price,
      description: description,
      category: category,
      image: image,
      rating: rating,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'price': price,
    'description': description,
    'category': category,
    'image': image,
    'rating': rating.toJson(),
  };
}
