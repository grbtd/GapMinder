// Contains the API credentials loaded from secrets.json
class Secrets {
  final String username;
  final String password;

  Secrets({this.username = "", this.password = ""});

  factory Secrets.fromJson(Map<String, dynamic> json) {
    return Secrets(
      username: json['username'],
      password: json['password'],
    );
  }
}
