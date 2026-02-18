class Secrets {
  final String apiKey;

  Secrets({this.apiKey = ""});

  factory Secrets.fromJson(Map<String, dynamic> json) {
    return Secrets(
      // Support 'apiKey' or fallback to 'password' if you reuse the field
      apiKey: json['apiKey'] ?? json['password'] ?? '',
    );
  }
}