class Operator {
  final String id;
  final String name;
  final String password;
  final String role;

  Operator({
    required this.id,
    required this.name,
    required this.password,
    required this.role,
  });

  factory Operator.fromJson(Map<String, dynamic> json) {
    return Operator(
      id: json['id'] as String,
      name: json['name'] as String,
      password: json['password'] as String,
      role: json['role'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'password': password,
      'role': role,
    };
  }
} 