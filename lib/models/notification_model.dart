class NotificationModel {
  final String id;
  final String userId;
  final String userName;
  final String userPhone;
  final String type;
  final String message;
  final bool isRead;
  final DateTime createdAt;

  NotificationModel({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userPhone,
    required this.type,
    required this.message,
    required this.isRead,
    required this.createdAt,
  });

  factory NotificationModel.fromMap(Map<String, dynamic> map) {
    return NotificationModel(
      id: map['id'],
      userId: map['user_id'],
      userName: map['user_name'],
      userPhone: map['user_phone'],
      type: map['type'],
      message: map['message'],
      isRead: map['is_read'] ?? false,
      createdAt: DateTime.parse(map['created_at']),
    );
  }
}