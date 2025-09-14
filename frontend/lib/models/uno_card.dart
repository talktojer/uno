class UNOCard {
  final String color;
  final String type;
  final int? value;

  UNOCard({
    required this.color,
    required this.type,
    this.value,
  });

  factory UNOCard.fromJson(Map<String, dynamic> json) {
    return UNOCard(
      color: json['color'],
      type: json['type'],
      value: json['value'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'color': color,
      'type': type,
      'value': value,
    };
  }
}
