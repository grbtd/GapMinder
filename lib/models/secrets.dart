// Contains the API credentials loaded from secrets.json
class Secrets {
  final String token;
  @Deprecated('Use token instead for rtt-ng API')
  final String username;
  @Deprecated('Use token instead for rtt-ng API')
  final String password;

  Secrets({
    this.token = "",
    this.username = "",
    this.password = ""
  });

  factory Secrets.fromJson(Map<String, dynamic> json) {
    return Secrets(
      token: json['token'] ?? "",
      username: json['username'] ?? "",
      password: json['password'] ?? "",
    );
  }
}
