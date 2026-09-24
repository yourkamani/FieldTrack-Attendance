abstract class AdminAuthProvider {
  Future<AdminAuthResult> signUp({
    required String email,
    required String password,
    required String businessName,
  });
  Future<AdminAuthResult> signIn({required String email, required String password});
  Future<void> signOut();
}

class AdminAuthResult {
  final String adminId;
  final String businessId;
  final String email;
  AdminAuthResult({required this.adminId, required this.businessId, required this.email});
}