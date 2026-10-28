class UserModel {
  final String id;
  final String name;
  final String email;
  final String? youtubeToken;
  final String? googleId;
  final String? avatarUrl;
  final String authProvider; // 'email' ou 'google'
  final DateTime createdAt;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.youtubeToken,
    this.googleId,
    this.avatarUrl,
    this.authProvider = 'email',
    required this.createdAt,
  });

  bool get isYouTubeConnected => youtubeToken != null && youtubeToken!.isNotEmpty;
  bool get isGoogleAccount => authProvider == 'google';

  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    String? youtubeToken,
    String? googleId,
    String? avatarUrl,
    String? authProvider,
    DateTime? createdAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      youtubeToken: youtubeToken ?? this.youtubeToken,
      googleId: googleId ?? this.googleId,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      authProvider: authProvider ?? this.authProvider,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'youtubeToken': youtubeToken,
      'googleId': googleId,
      'avatarUrl': avatarUrl,
      'authProvider': authProvider,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      youtubeToken: map['youtubeToken'] as String?,
      googleId: map['googleId'] as String?,
      avatarUrl: map['avatarUrl'] as String?,
      authProvider: map['authProvider'] as String? ?? 'email',
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
